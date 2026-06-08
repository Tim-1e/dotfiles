[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("ai-env-smoke-" + [guid]::NewGuid().ToString("N"))
$testHome = Join-Path $tmpRoot "home"
$previousAiEnvHome = $env:AI_ENV_HOME
$env:AI_ENV_HOME = $testHome

$aiEnvDir = Join-Path $testHome ".ai-env"
$codexDir = Join-Path $testHome ".codex"
$profilesPath = Join-Path $aiEnvDir "profiles.json"
$statePath = Join-Path $aiEnvDir "state.json"
$secretsDir = Join-Path $testHome ".ai-secrets"
$secretsPath = Join-Path $secretsDir "secrets.toml"

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
  $cxAddApi = (& { cx add-api api:test --base-url https://router.test/v1 --model gpt-test } 6>&1 | Out-String -Width 4096)
  $cxAddSub = (& { cx add-sub sub:test } 6>&1 | Out-String -Width 4096)
  $ccAddApi = (& { cc add-api api:test --base-url https://claude.test } 6>&1 | Out-String -Width 4096)
  $ccAddSub = (& { cc add-sub sub:test } 6>&1 | Out-String -Width 4096)
  $cxManagedList = (& { cx list } 6>&1 | Out-String -Width 4096)
  $ccManagedList = (& { cc list } 6>&1 | Out-String -Width 4096)
  $codexApiTestConfig = Join-Path $codexDir "api-api-test.config.toml"
  $codexApiConfigExistsAfterAdd = Test-Path -LiteralPath $codexApiTestConfig
  $cxRemoveApi = (& { cx remove api:test --delete-config } 6>&1 | Out-String -Width 4096)
  $cxRemoveSub = (& { cx remove sub:test --delete-config } 6>&1 | Out-String -Width 4096)
  $ccRemoveApi = (& { cc remove api:test } 6>&1 | Out-String -Width 4096)
  $ccRemoveSub = (& { cc remove sub:test } 6>&1 | Out-String -Width 4096)
  $cxSwitch = (& { cx api } 6>&1 | Out-String -Width 4096)
  $openAiKey = $env:OPENAI_API_KEY
  $ccSwitch = (& { cc api:docker } 6>&1 | Out-String -Width 4096)

  if ($cxHelp -notmatch "cx - switch Codex state") { throw "cx help output missing header" }
  if ($cxList -notmatch "Codex profiles") { throw "cx list output missing header" }
  if ($cxList -notmatch "secrets\.toml#codex\.api") { throw "cx list did not report TOML secret source" }
  if ($ccHelp -notmatch "cc - switch Claude Code state") { throw "cc help output missing header" }
  if ($ccList -notmatch "Claude Code profiles") { throw "cc list output missing header" }
  if ($ccList -notmatch "secrets\.toml#claude\.api-docker") { throw "cc list did not report TOML secret source" }
  if ($cxHelp -notmatch "cx add-api NAME") { throw "cx help output missing add-api" }
  if ($ccHelp -notmatch "cc add-api NAME") { throw "cc help output missing add-api" }
  if ($cxAddApi -notmatch "Added Codex API profile 'api:test'") { throw "cx add-api did not report success" }
  if ($cxAddSub -notmatch "Added Codex subscription profile 'sub:test'") { throw "cx add-sub did not report success" }
  if ($ccAddApi -notmatch "Added Claude Code API profile 'api:test'") { throw "cc add-api did not report success" }
  if ($ccAddSub -notmatch "Added Claude Code subscription profile 'sub:test'") { throw "cc add-sub did not report success" }
  if ($cxManagedList -notmatch "api:test") { throw "cx list did not show added API profile" }
  if ($cxManagedList -notmatch "sub:test") { throw "cx list did not show added sub profile" }
  if ($ccManagedList -notmatch "api:test") { throw "cc list did not show added API profile" }
  if ($ccManagedList -notmatch "sub:test") { throw "cc list did not show added sub profile" }
  if (-not $codexApiConfigExistsAfterAdd) { throw "cx add-api did not write Codex config" }
  if ($cxRemoveApi -notmatch "Removed Codex profile 'api:test'") { throw "cx remove api did not report success" }
  if ($cxRemoveSub -notmatch "Removed Codex profile 'sub:test'") { throw "cx remove sub did not report success" }
  if ($ccRemoveApi -notmatch "Removed Claude Code profile 'api:test'") { throw "cc remove api did not report success" }
  if ($ccRemoveSub -notmatch "Removed Claude Code profile 'sub:test'") { throw "cc remove sub did not report success" }
  if (Test-Path -LiteralPath $codexApiTestConfig) { throw "cx remove --delete-config did not remove Codex config" }
  if ($cxSwitch -notmatch "Secret source: .*secrets\.toml#codex\.api") { throw "cx api did not load TOML secret" }
  if ($openAiKey -ne "sk-test-codex") { throw "cx api did not set OPENAI_API_KEY from TOML" }
  if ($ccSwitch -notmatch "Secret source: .*secrets\.toml#claude\.api-docker") { throw "cc api:docker did not load TOML secret" }
  if ($env:ANTHROPIC_AUTH_TOKEN -ne "sk-test-token") { throw "cc api:docker did not set ANTHROPIC_AUTH_TOKEN from TOML" }
  if ($env:CODEX_HOME -ne $codexDir) { throw "Unexpected CODEX_HOME: $env:CODEX_HOME" }

  Write-Host "AI env PowerShell smoke check passed."
} finally {
  if ($null -ne $previousAiEnvHome) {
    $env:AI_ENV_HOME = $previousAiEnvHome
  } else {
    Remove-Item Env:AI_ENV_HOME -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
