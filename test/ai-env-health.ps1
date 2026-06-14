[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

# Offline health-subsystem tests. No real network: Get-AiProfileHealth is
# replaced with a fake that maps profile names to canned results, so we test
# the cache / prune / auto-select / status-mapping / command logic only.
$ErrorActionPreference = "Stop"

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("ai-env-health-" + [guid]::NewGuid().ToString("N"))
$testHome = Join-Path $tmpRoot "home"
$previousAiEnvHome = $env:AI_ENV_HOME
$previousNonInteractive = $env:AI_ENV_NONINTERACTIVE
$env:AI_ENV_HOME = $testHome
$env:AI_ENV_NONINTERACTIVE = "1"

$aiEnvDir = Join-Path $testHome ".ai-env"
$profilesPath = Join-Path $aiEnvDir "profiles.json"
$secretsDir = Join-Path $testHome ".ai-secrets"
$secretsPath = Join-Path $secretsDir "secrets.toml"
$healthPath = Join-Path $aiEnvDir "health.json"

function Assert-Eq($Name, $Actual, $Expected) {
  if ($Actual -ne $Expected) { throw "ASSERT $Name : expected '$Expected', got '$Actual'" }
  Write-Host "  ok: $Name = '$Actual'"
}
function Assert-Match($Name, $Actual, $Pattern) {
  if ($Actual -notmatch $Pattern) { throw "ASSERT $Name : '$Actual' did not match /$Pattern/" }
  Write-Host "  ok: $Name matches /$Pattern/"
}

try {
  New-Item -ItemType Directory -Force -Path $aiEnvDir, $secretsDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $SourceDir "dot_ai-env/create_profiles.json") -Destination $profilesPath -Force
  "" | Set-Content -LiteralPath $secretsPath -Encoding UTF8

  . (Join-Path $SourceDir "Documents/PowerShell/Scripts/ai-env.ps1")

  # --- FAKE the network probe: map profile names to canned health (no HTTP) ---
  function Get-AiProfileHealth {
    param($Tool, $Profile, $TimeoutSec = 20, $DegradedMs = 6000)
    switch (Get-AiProfileName -Profile $Profile) {
      "hgood" { [pscustomobject]@{ Status = "healthy";  LatencyMs = 120;  Method = "generation"; Error = $null } }
      "hbad"  { [pscustomobject]@{ Status = "down";     LatencyMs = 0;    Method = "none"; Error = "POST /v1/messages HTTP 401" } }
      "hslow" { [pscustomobject]@{ Status = "degraded"; LatencyMs = 9999; Method = "generation"; Error = "POST /v1/messages HTTP 429 (transient)" } }
      default { [pscustomobject]@{ Status = "down"; LatencyMs = 0; Method = "none"; Error = "POST /v1/messages HTTP 404" } }
    }
  }

  # Register test api profiles (no secrets needed: we only probe via the fake
  # and resolve names, never actually switch into them).
  cc add-api hgood --base-url https://h.test | Out-Null
  cc add-api hbad  --base-url https://h.test | Out-Null
  cc add-api hslow --base-url https://h.test | Out-Null
  cc add-api cyc-a --base-url https://h.test | Out-Null
  cc add-api cyc-b --base-url https://h.test | Out-Null

  Write-Host "[1] Format-AiHealthCell status icons"
  Assert-Match "healthy cell" (Format-AiHealthCell ([pscustomobject]@{ Status = "healthy"; LatencyMs = 120; Error = $null })) "🟢120ms"
  Assert-Match "degraded cell" (Format-AiHealthCell ([pscustomobject]@{ Status = "degraded"; Error = "HTTP 429 (transient)" })) "🟡429"
  Assert-Match "down cell" (Format-AiHealthCell ([pscustomobject]@{ Status = "down"; Error = "HTTP 401" })) "🔴401"
  Assert-Eq "skip cell" (Format-AiHealthCell ([pscustomobject]@{ Status = "skip"; Error = "x" })) "⏭"

  Write-Host "[2] probe-model set / clear"
  cc probe-model hgood my-sonnet | Out-Null
  $pm = (Get-AiProfileProbeTarget -Tool claude -Profile (Get-AiProfileByName -Tool claude -Name hgood)).ProbeModel
  Assert-Eq "probe_model set" $pm "my-sonnet"
  cc probe-model hgood | Out-Null
  $pm2 = (Get-AiProfileProbeTarget -Tool claude -Profile (Get-AiProfileByName -Tool claude -Name hgood)).ProbeModel
  Assert-Eq "probe_model cleared -> default haiku" $pm2 "claude-3-5-haiku-20241022"

  Write-Host "[3] default show / set"
  cc default hbad | Out-Null
  Assert-Eq "default set" (Get-AiDefaultProfileName -Tool claude) "hbad"
  Assert-Match "default show" (& { cc default } 6>&1 | Out-String) "claude default = hbad"

  Write-Host "[4] cache write / hit / fresh"
  Clear-AiHealthCache
  $pgood = Get-AiProfileByName -Tool claude -Name hgood
  $r1 = Get-AiProfileHealthCached -Tool claude -Profile $pgood
  Assert-Eq "first probe cached=false" $r1.Cached $false
  Assert-Eq "first probe status=healthy" $r1.Status "healthy"
  Assert-Eq "second probe cached=true" (Get-AiProfileHealthCached -Tool claude -Profile $pgood).Cached $true
  Assert-Eq "fresh probe cached=false" (Get-AiProfileHealthCached -Tool claude -Profile $pgood -Fresh).Cached $false
  Assert-Match "health.json written" (Get-Content -Raw -LiteralPath $healthPath) "claude.hgood"

  Write-Host "[5] orphan prune (Sync-AiHealthCache)"
  $cache = Read-AiHealthCache
  $cache["claude.ghost"] = [pscustomobject]@{ status = "down"; latencyMs = 0; error = "orphan"; probedAt = 1 }
  $cache | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $healthPath
  Sync-AiHealthCache -Tool claude
  $after = Read-AiHealthCache
  if ($after.ContainsKey("claude.ghost")) { throw "prune did NOT remove orphan claude.ghost" }
  if (-not $after.ContainsKey("claude.hgood")) { throw "prune removed a still-valid entry claude.hgood" }
  Write-Host "  ok: orphan pruned, valid entry kept"

  Write-Host "[6] auto-select skips down, picks first non-down (default first)"
  cc default hbad | Out-Null   # default is down
  Assert-Eq "auto-select picks healthy hgood" (Get-AiHealthyProfileName -Tool claude) "hgood"

  Write-Host "[7] next cycle (Get-AiNextProfileName)"
  Save-AiSelectedProfile -Tool claude -Name cyc-a
  Assert-Eq "next after cyc-a is cyc-b" (Get-AiNextProfileName -Tool claude) "cyc-b"

  Write-Host "[8] health command probes live; list shows cached Health WITHOUT probing"
  $healthOut = (& { cc health } 6>&1 | Out-String -Width 4096)
  Assert-Match "health header" $healthOut "profile health"
  Assert-Match "health shows hgood" $healthOut "hgood"
  # list shows a Health column (from cache) but must NOT trigger a live probe
  $keysBefore = (Read-AiHealthCache).Count
  $listOut = (& { cc list } 6>&1 | Out-String -Width 4096)
  $keysAfter = (Read-AiHealthCache).Count
  Assert-Match "list header" $listOut "Claude Code profiles"
  Assert-Match "list has Health col" $listOut "Health"
  if ($keysAfter -ne $keysBefore) { throw "cc list probed live (cache keys $keysBefore->$keysAfter); list must be cache-only" }
  Write-Host "  ok: list shows cached Health, did NOT probe (cache keys unchanged)"

  Write-Host ""
  Write-Host "AI env health check passed." -ForegroundColor Green
}
finally {
  if ($null -ne $previousAiEnvHome) { $env:AI_ENV_HOME = $previousAiEnvHome } else { Remove-Item Env:AI_ENV_HOME -ErrorAction SilentlyContinue }
  if ($null -ne $previousNonInteractive) { $env:AI_ENV_NONINTERACTIVE = $previousNonInteractive } else { Remove-Item Env:AI_ENV_NONINTERACTIVE -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
