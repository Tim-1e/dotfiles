[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Text -notmatch $Pattern) {
    throw $Message
  }
}

$profileSource = Join-Path $SourceDir "Documents\PowerShell\create_Microsoft.PowerShell_profile.ps1"
$aiEnvSource = Join-Path $SourceDir "Documents\PowerShell\Scripts\ai-env.ps1"
$registrySource = Join-Path $SourceDir "dot_ai-env\create_profiles.json"

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("powershell-profile-smoke-" + [guid]::NewGuid().ToString("N"))
$testHome = Join-Path $tmpRoot "home"
$aiEnvTarget = Join-Path $testHome "Documents\PowerShell\Scripts\ai-env.ps1"
$registryTarget = Join-Path $testHome ".ai-env\profiles.json"
$stateTarget = Join-Path $testHome ".ai-env\state.json"

$envBackup = @{}
foreach ($name in @("CODEX_THREAD_ID", "AI_ENV_HOME", "AI_ENV_SCRIPT_HOME", "CODEX_HOME", "AI_CODEX_LABEL", "AI_CODEX_PROFILE", "AI_CLAUDE_LABEL", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL")) {
  $envBackup[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $aiEnvTarget), (Split-Path -Parent $registryTarget) | Out-Null
  Copy-Item -LiteralPath $aiEnvSource -Destination $aiEnvTarget -Force
  Copy-Item -LiteralPath $registrySource -Destination $registryTarget -Force
  Remove-Item -LiteralPath $stateTarget -ErrorAction SilentlyContinue

  $env:CODEX_THREAD_ID = "profile-smoke"
  $env:AI_ENV_HOME = $testHome
  $env:AI_ENV_SCRIPT_HOME = $testHome
  . $profileSource

  foreach ($functionName in @("act", "deact", "python", "cx", "cc")) {
    if (-not (Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
      throw "Profile did not define function: $functionName"
    }
  }

  $profileText = Get-Content -Raw -LiteralPath $profileSource
  Assert-Contains -Text $profileText -Pattern "chezmoi-ai-env begin" -Message "Profile is missing the ai-env begin marker."
  Assert-Contains -Text $profileText -Pattern "Scripts\\ai-env\.ps1" -Message "Profile does not load Scripts\ai-env.ps1."

  $cxHelp = (& { cx help } 6>&1 | Out-String)
  $ccHelp = (& { cc help } 6>&1 | Out-String)
  if ($cxHelp -notmatch "cx - switch Codex state") { throw "cx help output missing header after profile load." }
  if ($ccHelp -notmatch "cc - switch Claude Code state") { throw "cc help output missing header after profile load." }

  $expectedCodexHome = Join-Path $testHome ".codex"
  if ($env:CODEX_HOME -ne $expectedCodexHome) {
    throw "Unexpected CODEX_HOME after profile load: $env:CODEX_HOME"
  }

  Write-Host "PowerShell profile smoke check passed."
} finally {
  foreach ($name in $envBackup.Keys) {
    if ($null -eq $envBackup[$name]) {
      [Environment]::SetEnvironmentVariable($name, $null, "Process")
    } else {
      [Environment]::SetEnvironmentVariable($name, $envBackup[$name], "Process")
    }
  }
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
