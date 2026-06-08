[CmdletBinding()]
param(
  [string]$SourceDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

function Install-ChezmoiFromGitHub {
  $archMap = @{
    X64 = "amd64"
    Arm64 = "arm64"
  }
  $arch = $archMap[[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()]
  if (-not $arch) {
    throw "Unsupported Windows architecture for chezmoi install: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
  }

  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/twpayne/chezmoi/releases/latest"
  $asset = $release.assets |
    Where-Object { $_.name -match "windows" -and $_.name -match $arch -and $_.name -match "\.zip$" } |
    Select-Object -First 1
  if (-not $asset) {
    throw "Could not find a chezmoi Windows $arch zip asset in the latest GitHub release."
  }

  $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("chezmoi-install-" + [guid]::NewGuid().ToString("N"))
  $zipPath = Join-Path $tempDir $asset.name
  $binDir = Join-Path $HOME ".local\bin"

  New-Item -ItemType Directory -Force -Path $tempDir, $binDir | Out-Null
  try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempDir -Force
    $exe = Get-ChildItem -LiteralPath $tempDir -Filter "chezmoi.exe" -Recurse -File | Select-Object -First 1
    if (-not $exe) {
      throw "Downloaded chezmoi archive did not contain chezmoi.exe."
    }

    Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $binDir "chezmoi.exe") -Force
    $env:PATH = "$binDir;$env:PATH"
    if ($env:GITHUB_PATH) {
      Add-Content -LiteralPath $env:GITHUB_PATH -Value $binDir
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathParts = @($userPath -split ";" | Where-Object { $_ })
    if ($pathParts -notcontains $binDir) {
      $newUserPath = if ($userPath) { "$binDir;$userPath" } else { $binDir }
      [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    }
  } finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id twpayne.chezmoi -e --source winget --accept-package-agreements --accept-source-agreements
  }

  if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
    Install-ChezmoiFromGitHub
  }
}

chezmoi apply --source $SourceDir
