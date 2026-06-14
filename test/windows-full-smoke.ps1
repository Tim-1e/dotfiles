[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Assert-Command {
  param([Parameter(Mandatory = $true)][string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing command: $Name"
  }
}

function Assert-File {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing file: $Path"
  }
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $text = Get-Content -Raw -LiteralPath $Path
  if ($text -notmatch $Pattern) {
    throw $Message
  }
}

Assert-Command -Name "chezmoi"

$profilePath = $PROFILE.CurrentUserCurrentHost
$aiEnvPath = Join-Path $HOME "Documents\PowerShell\Scripts\ai-env.ps1"
$registryPath = Join-Path $HOME ".ai-env\profiles.json"
$codexHome = Join-Path $HOME ".codex"

Assert-File -Path $profilePath
Assert-File -Path $aiEnvPath
Assert-File -Path $registryPath
Assert-File -Path (Join-Path $codexHome "config.toml")
Assert-File -Path (Join-Path $codexHome "sub.config.toml")
Assert-File -Path (Join-Path $codexHome "api.config.toml")
Assert-File -Path (Join-Path $codexHome "zc-ultra.config.toml")
Assert-File -Path (Join-Path $HOME ".claude\settings.json")

Assert-Contains -Path $profilePath -Pattern "chezmoi-ai-env begin" -Message "PowerShell profile is missing the ai-env begin marker."
Assert-Contains -Path $profilePath -Pattern "Scripts\\ai-env\.ps1" -Message "PowerShell profile does not load Scripts\ai-env.ps1."

& (Join-Path $SourceDir "test\fonts-smoke.ps1") -SourceDir (Join-Path $SourceDir "0xProto")

$pwsh = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) {
  $pwsh = (Get-Process -Id $PID).Path
}

$probe = @'
$ErrorActionPreference = "Stop"
foreach ($name in @("cx", "cc")) {
  if (-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Missing profile function in child pwsh session: $name"
  }
}
$cxHelp = (& { cx help } 6>&1 | Out-String)
$ccHelp = (& { cc help } 6>&1 | Out-String)
$cxList = (& { cx list } 6>&1 | Out-String)
$ccList = (& { cc list } 6>&1 | Out-String)
if ($cxHelp -notmatch "cx - switch Codex state") { throw "cx help failed in child pwsh session." }
if ($ccHelp -notmatch "cc - switch Claude Code state") { throw "cc help failed in child pwsh session." }
if ($cxList -notmatch "Codex profiles") { throw "cx list failed in child pwsh session." }
if ($ccList -notmatch "Claude Code profiles") { throw "cc list failed in child pwsh session." }
$expectedCodexHome = Join-Path $HOME ".codex"
if ($env:CODEX_HOME -ne $expectedCodexHome) {
  throw "Unexpected child CODEX_HOME: $env:CODEX_HOME"
}
cx status | Out-String | Out-Null
cc status | Out-String | Out-Null
Write-Host "profile-child-session-ok"
'@

$previousThreadId = $env:CODEX_THREAD_ID
try {
  $env:CODEX_THREAD_ID = "windows-full-smoke"
  $output = & $pwsh -NoLogo -Command $probe 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output | Write-Host
    throw "Child pwsh profile session failed with exit code $LASTEXITCODE."
  }
  if (($output | Out-String) -notmatch "profile-child-session-ok") {
    $output | Write-Host
    throw "Child pwsh profile session did not print the success marker."
  }
} finally {
  if ($null -eq $previousThreadId) {
    Remove-Item Env:CODEX_THREAD_ID -ErrorAction SilentlyContinue
  } else {
    $env:CODEX_THREAD_ID = $previousThreadId
  }
}

Write-Host "Windows full install smoke check passed."
