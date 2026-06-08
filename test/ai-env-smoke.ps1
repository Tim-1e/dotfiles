[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$aiEnvDir = Join-Path $HOME ".ai-env"
$codexDir = Join-Path $HOME ".codex"
$profilesPath = Join-Path $aiEnvDir "profiles.json"
$statePath = Join-Path $aiEnvDir "state.json"
$profilesBackup = $null
$stateBackup = $null

if (Test-Path -LiteralPath $profilesPath) {
  $profilesBackup = Get-Content -Raw -LiteralPath $profilesPath
}
if (Test-Path -LiteralPath $statePath) {
  $stateBackup = Get-Content -Raw -LiteralPath $statePath
}

try {
  New-Item -ItemType Directory -Force -Path $aiEnvDir, $codexDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $SourceDir "dot_ai-env/create_profiles.json") -Destination $profilesPath -Force
  Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue

  . (Join-Path $SourceDir "Documents/PowerShell/Scripts/ai-env.ps1")

  $cxHelp = (& { cx help } 6>&1 | Out-String)
  $cxList = (& { cx list } 6>&1 | Out-String)
  $ccHelp = (& { cc help } 6>&1 | Out-String)
  $ccList = (& { cc list } 6>&1 | Out-String)

  if ($cxHelp -notmatch "cx - switch Codex state") { throw "cx help output missing header" }
  if ($cxList -notmatch "Codex profiles") { throw "cx list output missing header" }
  if ($ccHelp -notmatch "cc - switch Claude Code state") { throw "cc help output missing header" }
  if ($ccList -notmatch "Claude Code profiles") { throw "cc list output missing header" }
  if ($env:CODEX_HOME -ne $codexDir) { throw "Unexpected CODEX_HOME: $env:CODEX_HOME" }

  Write-Host "AI env PowerShell smoke check passed."
} finally {
  if ($null -ne $profilesBackup) {
    New-Item -ItemType Directory -Force -Path $aiEnvDir | Out-Null
    Set-Content -LiteralPath $profilesPath -Value $profilesBackup -Encoding UTF8
  } else {
    Remove-Item -LiteralPath $profilesPath -ErrorAction SilentlyContinue
  }

  if ($null -ne $stateBackup) {
    New-Item -ItemType Directory -Force -Path $aiEnvDir | Out-Null
    Set-Content -LiteralPath $statePath -Value $stateBackup -Encoding UTF8
  } else {
    Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
  }
}
