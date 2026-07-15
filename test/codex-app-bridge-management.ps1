param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-app-bridge-management-" + [guid]::NewGuid().ToString("N"))
$testHome = Join-Path $tmpRoot "home"
$bridgeHome = Join-Path $tmpRoot "bridge"
$previous = @{
  AI_ENV_HOME = $env:AI_ENV_HOME
  AI_CODEX_APP_BRIDGE_HOME = $env:AI_CODEX_APP_BRIDGE_HOME
  AI_CODEX_APP_BRIDGE_PROJECT = $env:AI_CODEX_APP_BRIDGE_PROJECT
  AI_CODEX_APP_REAL_CLI = $env:AI_CODEX_APP_REAL_CLI
  AI_CODEX_APP_BRIDGE_ENV_TARGET = $env:AI_CODEX_APP_BRIDGE_ENV_TARGET
  AI_CODEX_CONFIG_PATH = $env:AI_CODEX_CONFIG_PATH
  CODEX_CLI_PATH = $env:CODEX_CLI_PATH
}

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $testHome ".ai-env") | Out-Null
  Copy-Item -LiteralPath (Join-Path $SourceDir "dot_ai-env/create_profiles.json") -Destination (Join-Path $testHome ".ai-env/profiles.json")
  $env:AI_ENV_HOME = $testHome
  $env:AI_CODEX_APP_BRIDGE_HOME = $bridgeHome
  $env:AI_CODEX_APP_BRIDGE_PROJECT = Join-Path $SourceDir "tools/codex-provider-bridge/CodexProviderBridge.csproj"
  $trustedBundle = Join-Path $tmpRoot "trusted-bundle"
  New-Item -ItemType Directory -Force -Path $trustedBundle | Out-Null
  $trustedCli = Join-Path $trustedBundle "codex.exe"
  Copy-Item -LiteralPath (Get-Process -Id $PID -ErrorAction Stop).Path -Destination $trustedCli
  foreach ($helper in @("codex-command-runner.exe", "codex-code-mode-host.exe", "codex-windows-sandbox-setup.exe")) {
    [IO.File]::WriteAllText((Join-Path $trustedBundle $helper), "fixture-$helper", [Text.UTF8Encoding]::new($false))
  }
  $env:AI_CODEX_APP_REAL_CLI = $trustedCli
  $env:AI_CODEX_APP_BRIDGE_ENV_TARGET = "Process"
  $env:AI_CODEX_CONFIG_PATH = Join-Path $testHome ".codex/config.toml"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $env:AI_CODEX_CONFIG_PATH) | Out-Null
  [IO.File]::WriteAllText($env:AI_CODEX_CONFIG_PATH, "model_provider = `"openai`"`n", [Text.UTF8Encoding]::new($false))
  $env:CODEX_CLI_PATH = "C:\before-codex.exe"

  . (Join-Path $SourceDir "Documents/PowerShell/Scripts/ai-env.ps1")
  Invoke-CodexAppBridgeCommand -Arguments @("install") | Out-Null

  $bridgePath = Join-Path $bridgeHome "codex-provider-bridge.exe"
  $settingsPath = Join-Path $bridgeHome "codex-provider-bridge.json"
  $activationPath = Join-Path $bridgeHome "activation.json"
  foreach ($path in @($bridgePath, $settingsPath, $activationPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Install did not create $path" }
  }
  if ($env:CODEX_CLI_PATH -cne $bridgePath) { throw "Install did not activate CODEX_CLI_PATH" }
  $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -Depth 20
  $securedRealCli = Join-Path $bridgeHome "codex.exe"
  if ($settings.realCodexPath -cne $securedRealCli) { throw "Settings did not select the secured real CLI copy" }
  if ($settings.realCodexSha256 -cne (Get-FileHash -LiteralPath $env:AI_CODEX_APP_REAL_CLI -Algorithm SHA256).Hash) { throw "Settings did not pin the trusted source CLI hash" }
  if ((Get-FileHash -LiteralPath $securedRealCli -Algorithm SHA256).Hash -cne $settings.realCodexSha256) { throw "Secured real CLI copy does not match settings" }
  foreach ($helper in @("codex-command-runner.exe", "codex-code-mode-host.exe", "codex-windows-sandbox-setup.exe")) {
    $sourceHelper = Join-Path $trustedBundle $helper
    $securedHelper = Join-Path $bridgeHome $helper
    if (-not (Test-Path -LiteralPath $securedHelper -PathType Leaf)) { throw "Install omitted required helper $helper" }
    if ((Get-FileHash -LiteralPath $securedHelper -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $sourceHelper -Algorithm SHA256).Hash) { throw "Secured helper differs: $helper" }
  }
  if ((Get-Content -LiteralPath $settingsPath -Raw) -match '(?i)(api[_-]?key|bearer|token)') { throw "Bridge settings contain secret-like fields" }
  $installedStatus = Get-CodexAppBridgeStatus
  if (-not $installedStatus.IsCurrentAppCli) { throw "Status did not recognize the pinned CLI as current" }

  Invoke-CodexAppBridgeCommand -Arguments @("install") | Out-Null
  Invoke-CodexAppBridgeCommand -Arguments @("remove") | Out-Null
  if ($env:CODEX_CLI_PATH -cne "C:\before-codex.exe") { throw "Remove did not restore the pre-install CODEX_CLI_PATH" }

  $env:CODEX_CLI_PATH = "C:\new-user-choice.exe"
  Invoke-CodexAppBridgeCommand -Arguments @("remove") | Out-Null
  if ($env:CODEX_CLI_PATH -cne "C:\new-user-choice.exe") { throw "Remove without activation clobbered an unrelated CODEX_CLI_PATH" }

  $status = Get-CodexAppBridgeStatus
  if ($status.IsConfigured) { throw "Bridge still reports configured after remove" }
  Write-Host "Codex App bridge management tests passed"
} finally {
  foreach ($name in $previous.Keys) {
    $value = $previous[$name]
    if ($null -eq $value) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue } else { Set-Item "Env:$name" $value }
  }
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
