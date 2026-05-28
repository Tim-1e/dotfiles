[CmdletBinding()]
param(
  [string]$SourceDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "0xProto")
)

$ErrorActionPreference = "Stop"

if ($env:INSTALL_FONTS -match "^(0|false|no)$") {
  Write-Host "Skipping 0xProto Nerd Fonts because INSTALL_FONTS=$env:INSTALL_FONTS."
  exit 0
}

if (-not $env:LOCALAPPDATA) {
  throw "LOCALAPPDATA is not set; cannot install user fonts on Windows."
}

$resolvedSource = (Resolve-Path -LiteralPath $SourceDir).Path
$fontFiles = @(Get-ChildItem -LiteralPath $resolvedSource -Filter "*.ttf" -File | Sort-Object Name)
if ($fontFiles.Count -eq 0) {
  Write-Host "Skipping 0xProto Nerd Fonts; no .ttf files found in $resolvedSource."
  exit 0
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

function Test-SameFileHash {
  param(
    [string]$Left,
    [string]$Right
  )

  if (-not (Test-Path -LiteralPath $Right)) {
    return $false
  }

  $leftItem = Get-Item -LiteralPath $Left
  $rightItem = Get-Item -LiteralPath $Right
  if ($leftItem.Length -ne $rightItem.Length) {
    return $false
  }

  try {
    $leftHash = (Get-FileHash -LiteralPath $Left -Algorithm SHA256).Hash
    $rightHash = (Get-FileHash -LiteralPath $Right -Algorithm SHA256).Hash
    return $leftHash -eq $rightHash
  } catch {
    return $false
  }
}

New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
New-Item -Force -Path $registryPath | Out-Null

foreach ($font in $fontFiles) {
  $destination = Join-Path $fontDir $font.Name

  if (-not (Test-SameFileHash -Left $font.FullName -Right $destination)) {
    try {
      Copy-Item -LiteralPath $font.FullName -Destination $destination -Force
    } catch {
      if (-not (Test-Path -LiteralPath $destination)) {
        throw
      }

      Write-Warning "Could not overwrite $destination; using the existing installed file. $($_.Exception.Message)"
    }
  }

  $registryName = Get-FontRegistryName -Font $font
  New-ItemProperty `
    -Path $registryPath `
    -Name $registryName `
    -Value $destination `
    -PropertyType String `
    -Force | Out-Null
}

try {
  if (-not ("Win32.NativeMethods" -as [type])) {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd,
    uint Msg,
    UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out UIntPtr lpdwResult);
'@ -ErrorAction Stop
  }

  $result = [UIntPtr]::Zero
  [Win32.NativeMethods]::SendMessageTimeout(
    [IntPtr]0xffff,
    0x001D,
    [UIntPtr]::Zero,
    $null,
    0x0002,
    1000,
    [ref]$result
  ) | Out-Null
} catch {
  Write-Verbose "Could not broadcast Windows font change notification: $($_.Exception.Message)"
}

Write-Host "Installed $($fontFiles.Count) 0xProto Nerd Font files to $fontDir."
