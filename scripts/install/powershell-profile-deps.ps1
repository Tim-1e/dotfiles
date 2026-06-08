[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

function Install-ProfileModule {
  param([Parameter(Mandatory = $true)][string]$Name)

  if (Get-Module -ListAvailable -Name $Name) {
    Write-Host "PowerShell module already available: $Name"
    return
  }

  try {
    Write-Host "Installing PowerShell module: $Name"
    Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
  } catch {
    Write-Warning "Could not install module $Name. $($_.Exception.Message)"
  }
}

if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
  Write-Warning "Install-Module is not available. Skipping PowerShell module installation."
} else {
  Install-ProfileModule -Name "PSReadLine"
  Install-ProfileModule -Name "Terminal-Icons"
  Install-ProfileModule -Name "Microsoft.WinGet.CommandNotFound"
}

if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    try {
      Write-Host "Installing oh-my-posh with winget"
      winget install --id JanDeDobbeleer.OhMyPosh -e --source winget --accept-package-agreements --accept-source-agreements
    } catch {
      Write-Warning "Could not install oh-my-posh. $($_.Exception.Message)"
    }
  } else {
    Write-Warning "winget is not available. Skipping oh-my-posh installation."
  }
} else {
  Write-Host "oh-my-posh already available"
}
