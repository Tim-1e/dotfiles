[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$aiEnvDir = Join-Path $HOME ".ai-env"
$codexDir = Join-Path $HOME ".codex"
$profilesPath = Join-Path $aiEnvDir "profiles.json"
$statePath = Join-Path $aiEnvDir "state.json"
$secretsDir = Join-Path $HOME ".ai-secrets"
$secretsPath = Join-Path $secretsDir "secrets.toml"
$profilesBackup = $null
$stateBackup = $null
$secretsBackup = $null
$hadSecrets = $false

if (Test-Path -LiteralPath $profilesPath) {
  $profilesBackup = Get-Content -Raw -LiteralPath $profilesPath
}
if (Test-Path -LiteralPath $statePath) {
  $stateBackup = Get-Content -Raw -LiteralPath $statePath
}
if (Test-Path -LiteralPath $secretsPath) {
  $hadSecrets = $true
  $secretsBackup = Get-Content -Raw -LiteralPath $secretsPath
}

try {
  New-Item -ItemType Directory -Force -Path $aiEnvDir, $codexDir, $secretsDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $SourceDir "dot_ai-env/create_profiles.json") -Destination $profilesPath -Force
  Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
  @"
[codex.api]
OPENAI_API_KEY = "sk-test-codex"

[claude.api-docker]
ANTHROPIC_BASE_URL = "https://anyrouter.top"
ANTHROPIC_AUTH_TOKEN = "sk-test-token"
"@ | Set-Content -LiteralPath $secretsPath -Encoding UTF8

  . (Join-Path $SourceDir "Documents/PowerShell/Scripts/ai-env.ps1")

  $cxHelp = (& { cx help } 6>&1 | Out-String -Width 4096)
  $cxList = (& { cx list } 6>&1 | Out-String -Width 4096)
  $ccHelp = (& { cc help } 6>&1 | Out-String -Width 4096)
  $ccList = (& { cc list } 6>&1 | Out-String -Width 4096)
  $cxSwitch = (& { cx api } 6>&1 | Out-String -Width 4096)
  $openAiKey = $env:OPENAI_API_KEY
  $ccSwitch = (& { cc api:docker } 6>&1 | Out-String -Width 4096)

  if ($cxHelp -notmatch "cx - switch Codex state") { throw "cx help output missing header" }
  if ($cxList -notmatch "Codex profiles") { throw "cx list output missing header" }
  if ($cxList -notmatch "secrets\.toml#codex\.api") { throw "cx list did not report TOML secret source" }
  if ($ccHelp -notmatch "cc - switch Claude Code state") { throw "cc help output missing header" }
  if ($ccList -notmatch "Claude Code profiles") { throw "cc list output missing header" }
  if ($ccList -notmatch "secrets\.toml#claude\.api-docker") { throw "cc list did not report TOML secret source" }
  if ($cxSwitch -notmatch "Secret source: .*secrets\.toml#codex\.api") { throw "cx api did not load TOML secret" }
  if ($openAiKey -ne "sk-test-codex") { throw "cx api did not set OPENAI_API_KEY from TOML" }
  if ($ccSwitch -notmatch "Secret source: .*secrets\.toml#claude\.api-docker") { throw "cc api:docker did not load TOML secret" }
  if ($env:ANTHROPIC_AUTH_TOKEN -ne "sk-test-token") { throw "cc api:docker did not set ANTHROPIC_AUTH_TOKEN from TOML" }
  if ($env:CODEX_HOME -ne $codexDir) { throw "Unexpected CODEX_HOME: $env:CODEX_HOME" }

  Write-Host "AI env PowerShell smoke check passed."
} finally {
  if ($null -ne $profilesBackup) {
    New-Item -ItemType Directory -Force -Path $aiEnvDir | Out-Null
    Set-Content -LiteralPath $profilesPath -Value $profilesBackup -Encoding UTF8
  } else {
    Remove-Item -LiteralPath $profilesPath -ErrorAction SilentlyContinue
  }

  if ($null -ne $stateBackup) {
    New-Item -ItemType Directory -Force -Path $aiEnvDir | Out-Null
    Set-Content -LiteralPath $statePath -Value $stateBackup -Encoding UTF8
  } else {
    Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
  }

  if ($hadSecrets) {
    New-Item -ItemType Directory -Force -Path $secretsDir | Out-Null
    Set-Content -LiteralPath $secretsPath -Value $secretsBackup -Encoding UTF8
  } else {
    Remove-Item -LiteralPath $secretsPath -ErrorAction SilentlyContinue
  }
}
