[CmdletBinding()]
param(
  [string]$SourceDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "0xProto")
)

$ErrorActionPreference = "Stop"

if ($env:INSTALL_FONTS -match "^(0|false|no)$") {
  Write-Host "Skipping Windows font smoke because INSTALL_FONTS=$env:INSTALL_FONTS."
  exit 0
}

$resolvedSource = (Resolve-Path -LiteralPath $SourceDir).Path
$fontFiles = @(Get-ChildItem -LiteralPath $resolvedSource -Filter "*.ttf" -File | Sort-Object Name)
if ($fontFiles.Count -eq 0) {
  throw "No .ttf files found in $resolvedSource."
}

$fontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
$registryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

function Get-FontRegistryName {
  param([System.IO.FileInfo]$Font)

  $fullNameByFile = @{
    "0xProtoNerdFont-Bold"          = "0xProto Nerd Font Bold"
    "0xProtoNerdFont-Italic"        = "0xProto Nerd Font Italic"
    "0xProtoNerdFont-Regular"       = "0xProto Nerd Font"
    "0xProtoNerdFontMono-Bold"      = "0xProto Nerd Font Mono Bold"
    "0xProtoNerdFontMono-Italic"    = "0xProto Nerd Font Mono Italic"
    "0xProtoNerdFontMono-Regular"   = "0xProto Nerd Font Mono"
    "0xProtoNerdFontMonoBold"       = "0xProto Nerd Font Mono Bold"
    "0xProtoNerdFontMonoItalic"     = "0xProto Nerd Font Mono Italic"
    "0xProtoNerdFontMonoRegular"    = "0xProto Nerd Font Mono"
    "0xProtoNerdFontPropo-Bold"     = "0xProto Nerd Font Propo Bold"
    "0xProtoNerdFontPropo-Italic"   = "0xProto Nerd Font Propo Italic"
    "0xProtoNerdFontPropo-Regular"  = "0xProto Nerd Font Propo"
  }

  $fullName = $fullNameByFile[$Font.BaseName]
  if (-not $fullName) {
    $fullName = $Font.BaseName
  }

  return "$fullName (TrueType)"
}

foreach ($font in $fontFiles) {
  $installedPath = Join-Path $fontDir $font.Name
  if (-not (Test-Path -LiteralPath $installedPath)) {
    throw "Missing installed Windows font file: $installedPath"
  }
}

$registryNames = @($fontFiles | ForEach-Object { Get-FontRegistryName -Font $_ } | Sort-Object -Unique)
$installedNames = @($fontFiles | ForEach-Object { $_.Name })

foreach ($registryName in $registryNames) {
  $value = (Get-ItemProperty -Path $registryPath -Name $registryName -ErrorAction Stop).$registryName
  if (-not (Test-Path -LiteralPath $value)) {
    throw "Registry value for ${registryName} points to missing file: $value"
  }

  if ($installedNames -notcontains (Split-Path -Leaf $value)) {
    throw "Unexpected registry value for ${registryName}: $value"
  }
}

Write-Host "Windows font smoke check passed."
