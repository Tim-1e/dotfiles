$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$expectedVersion = "v0.1.0"
$expectedCommit = "dfc0bd6ef4b6aafdafff5f6d732e28cc52cfcfc0"
$expectedInstallerSha256 = "40a116c2f83a25590ed9d1d74120354c00254ed719e1adda25c429282d57f54e"
$expectedArtifactSha256 = "f8fde14b05170a635d5837650fe587ba96dcdd1164d6f3e2706497a13beced5f"
$installer = Join-Path $repoRoot "scripts\install\cxcc.ps1"
$hook = Join-Path $repoRoot "run_before_10-install-cxcc.ps1.tmpl"
$dataFile = Join-Path $repoRoot ".chezmoidata.toml"
$profileSource = Join-Path $repoRoot "Documents\PowerShell\create_Microsoft.PowerShell_profile.ps1"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

foreach ($required in @($installer, $hook, $dataFile, $profileSource)) {
  Assert-True (Test-Path -LiteralPath $required -PathType Leaf) "Missing cxcc consumer file: $required"
}

$dataText = Get-Content -LiteralPath $dataFile -Raw
$hookText = Get-Content -LiteralPath $hook -Raw
$profileText = Get-Content -LiteralPath $profileSource -Raw
Assert-True ($dataText -match '(?m)^version = "v0\.1\.0"$') "dotfiles does not pin cxcc v0.1.0."
Assert-True $dataText.Contains($expectedCommit) "dotfiles does not pin an immutable cxcc commit."
Assert-True $dataText.Contains($expectedInstallerSha256) "dotfiles does not pin the PowerShell installer digest."
Assert-True $dataText.Contains($expectedArtifactSha256) "dotfiles does not pin the Windows artifact digest."
Assert-True $hookText.Contains("scripts\install\cxcc.ps1") "PowerShell hook does not invoke the cxcc consumer installer."
Assert-True $hookText.Contains(".cxcc.version") "PowerShell hook does not use the shared cxcc version pin."
Assert-True $hookText.Contains(".cxcc.commit") "PowerShell hook does not use the immutable cxcc commit pin."
Assert-True $hookText.Contains(".cxcc.installerPowerShellSha256") "PowerShell hook does not use the installer digest pin."
Assert-True $hookText.Contains(".cxcc.windowsArtifactSha256") "PowerShell hook does not use the artifact digest pin."
Assert-True ($profileText -match 'CXCC_HOME') "PowerShell profile does not honor CXCC_HOME."
Assert-True ($profileText -match 'load\.ps1') "PowerShell profile does not load the stable cxcc loader."
Assert-True ($profileText -notmatch 'Scripts\\ai-env\.ps1') "PowerShell profile still loads the legacy ai-env implementation."

$legacyPaths = @(
  "Documents/PowerShell/Scripts/ai-env.ps1",
  "dot_local/share/ai-env/ai-env.sh",
  "dot_local/share/ai-env/ai-health.mjs",
  "tools/codex-provider-bridge/ChildProcessJob.cs",
  "tools/codex-provider-bridge/CodexProviderBridge.csproj",
  "tools/codex-provider-bridge/Program.cs"
)
foreach ($legacyPath in $legacyPaths) {
  & git -C $repoRoot ls-files --error-unmatch -- $legacyPath *> $null
  $isTrackedAndPresent = $LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $repoRoot $legacyPath))
  Assert-True (-not $isTrackedAndPresent) "Legacy cxcc implementation is still tracked: $legacyPath"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cxcc-consumer-" + [guid]::NewGuid().ToString("N"))
$testHome = Join-Path $tempRoot "home"
$installRoot = Join-Path $testHome ".local\share\cxcc"
$downloadLog = Join-Path $tempRoot "download.log"
$installLog = Join-Path $tempRoot "install.log"
$envNames = @("INSTALL_CXCC", "CXCC_HOME", "AI_ENV_HOME", "CODEX_HOME", "CODEX_THREAD_ID", "CXCC_TEST_INSTALL_LOG")
$savedEnvironment = @{}
foreach ($name in $envNames) {
  $item = Get-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
  $savedEnvironment[$name] = if ($item) { [pscustomobject]@{ Exists = $true; Value = $item.Value } } else { [pscustomobject]@{ Exists = $false; Value = $null } }
}

try {
  $statePaths = @(
    (Join-Path $testHome ".ai-env\profiles.json"),
    (Join-Path $testHome ".ai-env\state.json"),
    (Join-Path $testHome ".ai-env\mcp.toml"),
    (Join-Path $testHome ".ai-secrets\secrets.toml"),
    (Join-Path $testHome ".codex\auth.json"),
    (Join-Path $testHome ".claude\.credentials.json")
  )
  foreach ($path in $statePaths) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null }
  [IO.File]::WriteAllText($statePaths[0], '{"sentinel":"profiles"}', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($statePaths[1], '{"sentinel":"state"}', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($statePaths[2], "[mcp.sentinel]`nenabled = false`n", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($statePaths[3], "[codex.sentinel]`nOPENAI_API_KEY = `"keep`"`n", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($statePaths[4], '{"sentinel":"auth"}', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($statePaths[5], '{"sentinel":"credentials"}', [Text.UTF8Encoding]::new($false))
  $stateHashes = @{}
  foreach ($path in $statePaths) { $stateHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }

  $fakeInstallerSource = Join-Path $tempRoot "fake-install.ps1"
  $fakeInstaller = @'
param([string]$Version, [string]$ArtifactPath, [string]$Sha256)
if ($Version -cne "v0.1.0") { throw "Unexpected fake installer version: $Version" }
if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "Fake artifact is missing." }
Add-Content -LiteralPath $env:CXCC_TEST_INSTALL_LOG -Value "$Version|$([IO.Path]::GetFileName($ArtifactPath))|$Sha256"
$root = $env:CXCC_HOME
$versionRoot = Join-Path $root "versions\$Version"
New-Item -ItemType Directory -Force -Path $versionRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $root ".cxcc-root"), "cxcc-install-root-v1`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $versionRoot "VERSION"), $Version, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $versionRoot ".artifact-sha256"), "$Sha256`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $root "current.json"), "{`"schema`":1,`"version`":`"$Version`",`"previous`":null}`n", [Text.UTF8Encoding]::new($false))
$payloadFiles = @(
  "load.ps1",
  "load.sh",
  "src\powershell\CxCc\CxCc.ps1",
  "src\shell\cxcc.sh",
  "src\shell\ai-health.mjs",
  "src\bridge\CodexProviderBridge\CodexProviderBridge.csproj",
  "templates\profiles.json"
)
foreach ($relativePath in $payloadFiles) {
  $path = Join-Path $versionRoot $relativePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  [IO.File]::WriteAllText($path, "# fake payload`n", [Text.UTF8Encoding]::new($false))
}
$loader = @(
  '$global:CXCC_CONSUMER_TEST_LOADER_COUNT = [int]$global:CXCC_CONSUMER_TEST_LOADER_COUNT + 1'
  'function global:cx { }'
  'function global:cc { }'
  'function global:mcp { }'
) -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $root "load.ps1"), $loader, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $root "load.sh"), "# fake shell loader`n", [Text.UTF8Encoding]::new($false))
'@
  [IO.File]::WriteAllText($fakeInstallerSource, $fakeInstaller, [Text.UTF8Encoding]::new($false))
  $testCommit = "1" * 40
  $testInstallerSha256 = (Get-FileHash -LiteralPath $fakeInstallerSource -Algorithm SHA256).Hash.ToLowerInvariant()
  $testArtifactSha256 = "a" * 64
  $installerArguments = @{
    Version = $expectedVersion
    Commit = $testCommit
    InstallerSha256 = $testInstallerSha256
    ArtifactSha256 = $testArtifactSha256
  }

  function global:Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [int]$TimeoutSec)
    Add-Content -LiteralPath $downloadLog -Value $Uri
    if ($Uri.EndsWith("/install.ps1", [StringComparison]::Ordinal)) {
      Copy-Item -LiteralPath $fakeInstallerSource -Destination $OutFile
    } else {
      [IO.File]::WriteAllText($OutFile, "fake artifact", [Text.UTF8Encoding]::new($false))
    }
  }

  function Assert-StatePreserved {
    foreach ($path in $statePaths) {
      Assert-True (((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) -ceq $stateHashes[$path]) "cxcc consumer changed user state: $path"
    }
  }

  $env:CXCC_HOME = $installRoot
  $env:AI_ENV_HOME = $testHome
  $env:CODEX_HOME = Join-Path $testHome ".codex"
  $env:CODEX_THREAD_ID = "cxcc-consumer-smoke"
  $env:CXCC_TEST_INSTALL_LOG = $installLog
  Remove-Item -LiteralPath Env:\INSTALL_CXCC -ErrorAction SilentlyContinue

  & $installer @installerArguments
  $downloadLines = @(Get-Content -LiteralPath $downloadLog)
  Assert-True ($downloadLines.Count -eq 2) "PowerShell consumer did not download the installer and artifact exactly once."
  Assert-True ($downloadLines[0] -ceq "https://raw.githubusercontent.com/Tim-1e/cxcc/$testCommit/install.ps1") "PowerShell consumer used a mutable installer URL."
  Assert-True ($downloadLines[1] -ceq "https://github.com/Tim-1e/cxcc/releases/download/$expectedVersion/cxcc-$expectedVersion-windows-x64.zip") "PowerShell consumer used an unexpected artifact URL."
  Assert-True ((Get-Content -LiteralPath $installLog -Raw).Trim() -ceq "$expectedVersion|cxcc-$expectedVersion-windows-x64.zip|$testArtifactSha256") "PowerShell consumer passed unexpected installer arguments."
  $current = Get-Content -LiteralPath (Join-Path $installRoot "current.json") -Raw | ConvertFrom-Json
  Assert-True ($current.schema -eq 1 -and $current.version -ceq $expectedVersion) "PowerShell consumer current.json is invalid."
  Assert-True ((Get-Content -LiteralPath (Join-Path $installRoot "versions\$expectedVersion\VERSION") -Raw) -ceq $expectedVersion) "PowerShell consumer payload VERSION is invalid."
  Assert-StatePreserved

  & $installer @installerArguments
  Assert-True (@(Get-Content -LiteralPath $downloadLog).Count -eq 2) "Repeated PowerShell apply downloaded cxcc again."
  Assert-StatePreserved

  Remove-Item -LiteralPath (Join-Path $installRoot "versions\$expectedVersion\src\powershell\CxCc\CxCc.ps1")
  & $installer @installerArguments
  Assert-True (@(Get-Content -LiteralPath $downloadLog).Count -eq 4) "PowerShell consumer ignored a damaged cxcc payload."
  Assert-StatePreserved

  Remove-Item -LiteralPath Function:\cx, Function:\cc, Function:\mcp -ErrorAction SilentlyContinue
  Remove-Variable -Name CXCC_CONSUMER_TEST_LOADER_COUNT -Scope Global -ErrorAction SilentlyContinue
  . $profileSource
  foreach ($name in @("cx", "cc", "mcp")) {
    Assert-True ($null -ne (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) "PowerShell profile did not define $name."
  }
  Assert-True ($global:CXCC_CONSUMER_TEST_LOADER_COUNT -eq 1) "PowerShell profile did not run the stable loader exactly once."

  [IO.Directory]::Delete($installRoot, $true)
  $env:INSTALL_CXCC = "0"
  & $installer @installerArguments
  Assert-True (-not (Test-Path -LiteralPath $installRoot)) "INSTALL_CXCC=0 created an install root."
  Assert-True (@(Get-Content -LiteralPath $downloadLog).Count -eq 4) "INSTALL_CXCC=0 accessed the network."
  Assert-StatePreserved

  $invalidVersionFailed = $false
  try { & $installer -Version "main" -Commit $testCommit -InstallerSha256 $testInstallerSha256 -ArtifactSha256 $testArtifactSha256 } catch { $invalidVersionFailed = $true }
  Assert-True $invalidVersionFailed "PowerShell consumer accepted an unpinned version."

  Remove-Item -LiteralPath Env:\INSTALL_CXCC -ErrorAction SilentlyContinue
  $env:CXCC_HOME = Join-Path $testHome "bad\cxcc"
  $checksumFailed = $false
  try { & $installer -Version $expectedVersion -Commit $testCommit -InstallerSha256 ("0" * 64) -ArtifactSha256 $testArtifactSha256 } catch { $checksumFailed = $true }
  Assert-True $checksumFailed "PowerShell consumer executed an installer with the wrong checksum."
  Assert-True (@(Get-Content -LiteralPath $downloadLog).Count -eq 5) "PowerShell checksum failure downloaded an artifact or retried unexpectedly."
  Assert-True (@(Get-Content -LiteralPath $installLog).Count -eq 2) "PowerShell checksum failure executed the installer."

  Write-Host "cxcc PowerShell consumer smoke passed."
} finally {
  Remove-Item -LiteralPath Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
  foreach ($name in $envNames) {
    if ($savedEnvironment[$name].Exists) { Set-Item -LiteralPath "Env:\$name" -Value $savedEnvironment[$name].Value }
    else { Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue }
  }
  Remove-Variable -Name CXCC_CONSUMER_TEST_LOADER_COUNT -Scope Global -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
