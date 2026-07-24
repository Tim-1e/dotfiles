[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [Parameter(Mandatory = $true)]
  [string]$Commit,
  [Parameter(Mandatory = $true)]
  [string]$InstallerSha256,
  [Parameter(Mandatory = $true)]
  [string]$ArtifactSha256
)

$ErrorActionPreference = "Stop"
$repository = "Tim-1e/cxcc"
$versionPattern = '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

if ($Version -notmatch $versionPattern) {
  throw "cxcc version must be an exact release tag such as v0.1.0."
}
if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "cxcc commit must be a full lowercase Git SHA." }
foreach ($digest in @($InstallerSha256, $ArtifactSha256)) {
  if ($digest -notmatch '^[0-9a-f]{64}$') { throw "cxcc SHA-256 pins must contain 64 lowercase hexadecimal characters." }
}

if ([string]::IsNullOrEmpty($env:INSTALL_CXCC)) {
  $shouldInstall = $false
  if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
    try {
      $answer = Read-Host "Install the cx/cc environment? [y/N]"
      $shouldInstall = ([string]$answer).Trim() -match '^(?i:y|yes)$'
    } catch {
      $shouldInstall = $false
    }
  }
} elseif ($env:INSTALL_CXCC -ceq "1") {
  $shouldInstall = $true
} elseif ($env:INSTALL_CXCC -ceq "0") {
  $shouldInstall = $false
} else {
  throw "INSTALL_CXCC must be 0 or 1."
}

if (-not $shouldInstall) {
  Write-Host "Skipping cxcc installation. Set INSTALL_CXCC=1 to install it."
  return
}

if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
  throw "cxcc $Version provides a Windows x64 artifact only. Set INSTALL_CXCC=0 to skip installation on this host."
}

$installRoot = if ($env:CXCC_HOME) {
  [Environment]::ExpandEnvironmentVariables($env:CXCC_HOME)
} else {
  Join-Path $HOME ".local\share\cxcc"
}

function Test-CxccCurrent {
  $markerPath = Join-Path $installRoot ".cxcc-root"
  $currentPath = Join-Path $installRoot "current.json"
  $versionRoot = Join-Path $installRoot "versions\$Version"
  $versionPath = Join-Path $versionRoot "VERSION"
  $requiredPaths = @(
    $markerPath,
    $currentPath,
    (Join-Path $installRoot "load.ps1"),
    (Join-Path $installRoot "load.sh"),
    $versionPath,
    (Join-Path $versionRoot ".artifact-sha256"),
    (Join-Path $versionRoot "load.ps1"),
    (Join-Path $versionRoot "load.sh"),
    (Join-Path $versionRoot "src\powershell\CxCc\CxCc.ps1"),
    (Join-Path $versionRoot "src\shell\cxcc.sh"),
    (Join-Path $versionRoot "src\shell\ai-health.mjs"),
    (Join-Path $versionRoot "src\bridge\CodexProviderBridge\CodexProviderBridge.csproj"),
    (Join-Path $versionRoot "templates\profiles.json")
  )
  foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
  }
  if ((Get-Content -LiteralPath $markerPath -Raw).Trim() -cne "cxcc-install-root-v1") { return $false }
  if ((Get-Content -LiteralPath $versionPath -Raw).Trim() -cne $Version) { return $false }
  if ((Get-Content -LiteralPath (Join-Path $versionRoot ".artifact-sha256") -Raw).Trim() -cne $ArtifactSha256) { return $false }
  try {
    $current = Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json
  } catch {
    return $false
  }
  return $current.schema -eq 1 -and [string]$current.version -ceq $Version
}

function Invoke-CxccDownload {
  param([string]$Uri, [string]$OutFile)

  for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
      Invoke-WebRequest -Uri $Uri -OutFile $OutFile -TimeoutSec 120
      return
    } catch {
      if ($attempt -eq 2) { throw }
      Write-Warning "cxcc download failed; retrying once: $($_.Exception.Message)"
      Start-Sleep -Seconds 1
    }
  }
}

if (Test-CxccCurrent) {
  Write-Host "cxcc $Version is already installed."
  return
}

$downloadRoot = Join-Path ([IO.Path]::GetTempPath()) ("cxcc-dotfiles-" + [guid]::NewGuid().ToString("N"))
$installer = Join-Path $downloadRoot "install.ps1"
$artifactName = "cxcc-$Version-windows-x64.zip"
$artifact = Join-Path $downloadRoot $artifactName
try {
  New-Item -ItemType Directory -Path $downloadRoot | Out-Null
  $installerUrl = "https://raw.githubusercontent.com/$repository/$Commit/install.ps1"
  Invoke-CxccDownload -Uri $installerUrl -OutFile $installer
  $actualInstallerSha256 = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualInstallerSha256 -cne $InstallerSha256) {
    throw "cxcc installer checksum mismatch. Expected $InstallerSha256, got $actualInstallerSha256."
  }

  $artifactUrl = "https://github.com/$repository/releases/download/$Version/$artifactName"
  Invoke-CxccDownload -Uri $artifactUrl -OutFile $artifact
  & $installer -Version $Version -ArtifactPath $artifact -Sha256 $ArtifactSha256
} finally {
  if (Test-Path -LiteralPath $downloadRoot) {
    Remove-Item -LiteralPath $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
