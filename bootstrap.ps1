[CmdletBinding()]
param(
  [string]$SourceDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id twpayne.chezmoi -e --source winget
  } else {
    throw "chezmoi is not installed and winget is not available. Install chezmoi, then rerun this script."
  }
}

chezmoi apply --source $SourceDir
