[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Text -notmatch $Pattern) {
    throw $Message
  }
}

$profileSource = Join-Path $SourceDir "Documents\PowerShell\create_Microsoft.PowerShell_profile.ps1"

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("powershell-profile-smoke-" + [guid]::NewGuid().ToString("N"))
$testHome = Join-Path $tmpRoot "home"
$cxccRoot = Join-Path $testHome ".local\share\cxcc"
$cxccLoader = Join-Path $cxccRoot "load.ps1"

$envBackup = @{}
foreach ($name in @("CODEX_THREAD_ID", "CXCC_HOME")) {
  $envBackup[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
  New-Item -ItemType Directory -Force -Path $cxccRoot | Out-Null
  $loader = @'
$global:CXCC_PROFILE_SMOKE_LOADER_COUNT = [int]$global:CXCC_PROFILE_SMOKE_LOADER_COUNT + 1
function global:cx { }
function global:cc { }
function global:mcp { }
'@
  [IO.File]::WriteAllText($cxccLoader, $loader, [Text.UTF8Encoding]::new($false))

  $env:CODEX_THREAD_ID = "profile-smoke"
  $env:CXCC_HOME = $cxccRoot
  . $profileSource

  foreach ($functionName in @("act", "deact", "python", "cx", "cc", "mcp")) {
    if (-not (Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
      throw "Profile did not define function: $functionName"
    }
  }
  if ($global:CXCC_PROFILE_SMOKE_LOADER_COUNT -ne 1) { throw "Profile did not load cxcc exactly once." }

  $profileText = Get-Content -Raw -LiteralPath $profileSource
  Assert-Contains -Text $profileText -Pattern "chezmoi-ai-env begin" -Message "Profile is missing the ai-env begin marker."
  Assert-Contains -Text $profileText -Pattern "CXCC_HOME" -Message "Profile does not honor CXCC_HOME."
  Assert-Contains -Text $profileText -Pattern "load\.ps1" -Message "Profile does not load the stable cxcc loader."

  Write-Host "PowerShell profile smoke check passed."
} finally {
  foreach ($name in $envBackup.Keys) {
    if ($null -eq $envBackup[$name]) {
      [Environment]::SetEnvironmentVariable($name, $null, "Process")
    } else {
      [Environment]::SetEnvironmentVariable($name, $envBackup[$name], "Process")
    }
  }
  Remove-Variable -Name CXCC_PROFILE_SMOKE_LOADER_COUNT -Scope Global -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
