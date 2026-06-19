[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("ai-env-smoke-" + [guid]::NewGuid().ToString("N"))
$testHome = Join-Path $tmpRoot "home"
$previousAiEnvHome = $env:AI_ENV_HOME
$previousNonInteractive = $env:AI_ENV_NONINTERACTIVE
$env:AI_ENV_HOME = $testHome
$env:AI_ENV_NONINTERACTIVE = "1"

$aiEnvDir = Join-Path $testHome ".ai-env"
$codexDir = Join-Path $testHome ".codex"
$profilesPath = Join-Path $aiEnvDir "profiles.json"
$statePath = Join-Path $aiEnvDir "state.json"
$secretsDir = Join-Path $testHome ".ai-secrets"
$secretsPath = Join-Path $secretsDir "secrets.toml"

try {
  New-Item -ItemType Directory -Force -Path $aiEnvDir, $codexDir, $secretsDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $SourceDir "dot_ai-env/create_profiles.json") -Destination $profilesPath -Force
  Copy-Item -LiteralPath (Join-Path $SourceDir "dot_codex/create_sub.config.toml") -Destination (Join-Path $codexDir "sub.config.toml") -Force
  Copy-Item -LiteralPath (Join-Path $SourceDir "dot_codex/create_api.config.toml") -Destination (Join-Path $codexDir "api.config.toml") -Force
  $sessionDir = Join-Path $codexDir "sessions\2026\06\09"
  New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
  @'
{"timestamp":"2026-06-09T00:00:00.000Z","type":"session_meta","payload":{"id":"stats-smoke","cwd":"I:\\CodeX_desk\\dotfiles"}}
{"timestamp":"2026-06-09T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":700,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}
'@ | Set-Content -LiteralPath (Join-Path $sessionDir "rollout-2026-06-09T00-00-00-stats-smoke.jsonl") -Encoding UTF8
  Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
  @"
[codex.api]
OPENAI_API_KEY = "sk-test-codex"

[codex.cxenvtest]
OPENAI_API_KEY = "sk-test-cxenv"

[claude.api-docker]
ANTHROPIC_BASE_URL = "https://anyrouter.top"
ANTHROPIC_AUTH_TOKEN = "sk-test-token"

[claude.envtest]
ANTHROPIC_AUTH_TOKEN = "sk-test-envtoken"
"@ | Set-Content -LiteralPath $secretsPath -Encoding UTF8

  . (Join-Path $SourceDir "Documents/PowerShell/Scripts/ai-env.ps1")

  $cxHelp = (& { cx help } 6>&1 | Out-String -Width 4096)
  $cxList = (& { cx list } 6>&1 | Out-String -Width 4096)
  $ccHelp = (& { cc help } 6>&1 | Out-String -Width 4096)
  $ccList = (& { cc list } 6>&1 | Out-String -Width 4096)
  $cxStats = (& { cx stats --days 365 } 6>&1 | Out-String -Width 4096)
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
  if ($cxHelp -notmatch "Auto-select a cached healthy Codex profile") { throw "cx help output missing auto-select wording" }
  if ($cxHelp -notmatch "cx edit") { throw "cx help output missing edit" }
  if ($cxHelp -notmatch "cx doctor") { throw "cx help output missing doctor" }
  if ($cxHelp -notmatch "cx next") { throw "cx help output missing next" }
  if ($cxList -notmatch "Codex profiles") { throw "cx list output missing header" }
  if ($cxList -notmatch "Health") { throw "cx list missing Health column" }
  if ($ccHelp -notmatch "cc - switch Claude Code state") { throw "cc help output missing header" }
  if ($ccHelp -notmatch "Auto-select a cached healthy Claude Code profile") { throw "cc help output missing auto-select wording" }
  if ($ccHelp -notmatch "cc edit") { throw "cc help output missing edit" }
  if ($ccHelp -notmatch "cc next") { throw "cc help output missing next" }
  if ($ccList -notmatch "Claude Code profiles") { throw "cc list output missing header" }
  if ($ccList -notmatch "Health") { throw "cc list missing Health column" }
  if ($cxStats -notmatch "Codex local token stats") { throw "cx stats output missing header" }
  if ($cxStats -notmatch "Total:\s+1\.2K \(1200\)") { throw "cx stats did not summarize fixture tokens" }
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
  if ($cxSwitch -notmatch "API local check: profile file=True; key=True") { throw "cx api switch missing local check" }
  if ($openAiKey -ne "sk-test-codex") { throw "cx api did not set OPENAI_API_KEY from TOML" }
  if ($ccSwitch -notmatch "Secret source: .*secrets\.toml#claude\.api-docker") { throw "cc api:docker did not load TOML secret" }
  if ($ccSwitch -notmatch "API local check: auth=True; url=True") { throw "cc api switch missing local check" }
  if ($env:ANTHROPIC_AUTH_TOKEN -ne "sk-test-token") { throw "cc api:docker did not set ANTHROPIC_AUTH_TOKEN from TOML" }
  if ($env:CODEX_HOME -ne $codexDir) { throw "Unexpected CODEX_HOME: $env:CODEX_HOME" }

  # --- per-profile env (--env): persisted in registry, exported on switch, cleared on switch-away ---
  $ccAddEnv = (& { cc add-api envtest --base-url https://claude.test --env ANTHROPIC_DEFAULT_SONNET_MODEL=glm-test-sonnet --env CLAUDE_CODE_AUTO_COMPACT_WINDOW=987654 } 6>&1 | Out-String -Width 4096)
  $cxAddEnv = (& { cx add-api cxenvtest --base-url https://router.test/v1 --env CODEX_EXTRA_FLAG=on } 6>&1 | Out-String -Width 4096)
  $registryAfterEnv = Get-Content -LiteralPath $profilesPath -Raw
  $ccEnvSwitch = (& { cc envtest } 6>&1 | Out-String -Width 4096)
  $ccEnvSonnet = $env:ANTHROPIC_DEFAULT_SONNET_MODEL
  $ccEnvWindow = $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW
  $ccEnvAway = (& { cc api:docker } 6>&1 | Out-String -Width 4096)
  $ccEnvSonnetAfterAway = $env:ANTHROPIC_DEFAULT_SONNET_MODEL
  $cxEnvSwitch = (& { cx cxenvtest } 6>&1 | Out-String -Width 4096)
  $cxEnvFlag = $env:CODEX_EXTRA_FLAG
  $cxEnvAway = (& { cx api } 6>&1 | Out-String -Width 4096)
  $cxEnvFlagAfterAway = $env:CODEX_EXTRA_FLAG

  if ($ccAddEnv -notmatch "Added Claude Code API profile 'envtest'") { throw "cc add-api --env did not report success" }
  if ($ccAddEnv -notmatch "Env:") { throw "cc add-api did not report Env summary" }
  if ($registryAfterEnv -notmatch "ANTHROPIC_DEFAULT_SONNET_MODEL") { throw "registry did not persist profile env map" }
  if ($ccEnvSonnet -ne "glm-test-sonnet") { throw "cc switch did not export ANTHROPIC_DEFAULT_SONNET_MODEL from profile env" }
  if ($ccEnvWindow -ne "987654") { throw "cc switch did not export CLAUDE_CODE_AUTO_COMPACT_WINDOW from profile env" }
  if ($ccEnvSonnetAfterAway) { throw "cc switch-away did not clear the previous profile env var (leak)" }
  if ($cxEnvFlag -ne "on") { throw "cx switch did not export CODEX_EXTRA_FLAG from profile env" }
  if ($cxEnvFlagAfterAway) { throw "cx switch-away did not clear the previous profile env var (leak)" }

  Write-Host "AI env PowerShell smoke check passed."
} finally {
  if ($null -ne $previousAiEnvHome) {
    $env:AI_ENV_HOME = $previousAiEnvHome
  } else {
    Remove-Item Env:AI_ENV_HOME -ErrorAction SilentlyContinue
  }
  if ($null -ne $previousNonInteractive) {
    $env:AI_ENV_NONINTERACTIVE = $previousNonInteractive
  } else {
    Remove-Item Env:AI_ENV_NONINTERACTIVE -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
