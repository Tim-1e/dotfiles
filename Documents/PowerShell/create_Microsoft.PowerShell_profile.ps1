[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$env:PYTHONUTF8 = "1"
$env:VIRTUAL_ENV_DISABLE_PROMPT = "1"

Import-Module PSReadLine -ErrorAction SilentlyContinue

$isPaseoTerminal = [bool]($env:PASEO_TERMINAL_ID -or $env:PASEO_TERMINAL)

if (-not $env:CODEX_THREAD_ID -and -not $isPaseoTerminal) {
  Import-Module Terminal-Icons -ErrorAction SilentlyContinue
}

if (Get-Module -ListAvailable -Name Microsoft.WinGet.CommandNotFound) {
  Import-Module -Name Microsoft.WinGet.CommandNotFound -ErrorAction SilentlyContinue
}

if ($Host.UI.SupportsVirtualTerminal -and (Get-Module -Name PSReadLine)) {
  try {
    Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
    Set-PSReadLineKeyHandler -Chord "Ctrl+RightArrow" -Function ForwardWord
  } catch {
    # Some constrained hosts do not support PSReadLine customization.
  }
}

function act {
  $localCandidates = @(".\.venv\Scripts\Activate.ps1")
  $globalPath = "C:\common_python_env\com_env\Scripts\activate.ps1"

  foreach ($path in $localCandidates) {
    if (Test-Path -LiteralPath $path) {
      Write-Host "Activating local virtual environment: $path" -ForegroundColor Cyan
      . $path
      return
    }
  }

  if (Test-Path -LiteralPath $globalPath) {
    Write-Host "No local venv found. Activating global environment: $globalPath" -ForegroundColor Yellow
    . $globalPath
    return
  }

  Write-Error "No local venv and global environment path does not exist: $globalPath"
}

function deact {
  if (Get-Command deactivate -ErrorAction SilentlyContinue) {
    deactivate
    Write-Host "Virtual environment deactivated" -ForegroundColor Green
  } else {
    Write-Host "No active virtual environment" -ForegroundColor Yellow
  }
}

function python {
  if ($env:VIRTUAL_ENV) {
    & "$env:VIRTUAL_ENV\Scripts\python.exe" @args
    return
  }

  Write-Host "No virtual environment detected." -ForegroundColor Red
  Write-Host "Run 'act' first." -ForegroundColor Yellow
}

if (($isPaseoTerminal -or -not $env:CODEX_THREAD_ID) -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
  $themeFile = if ($isPaseoTerminal) { "my_theme_paseo.json" } else { "my_theme.json" }
  $themePath = Join-Path $HOME "Documents\PowerShell\$themeFile"
  if (Test-Path -LiteralPath $themePath) {
    oh-my-posh init pwsh --config $themePath | Invoke-Expression
  } else {
    oh-my-posh init pwsh | Invoke-Expression
  }
}

# chezmoi-ai-env begin
$cxccRoot = if ($env:CXCC_HOME) { [Environment]::ExpandEnvironmentVariables($env:CXCC_HOME) } else { Join-Path $HOME '.local\share\cxcc' }
$cxccLoader = Join-Path $cxccRoot 'load.ps1'
if (Test-Path -LiteralPath $cxccLoader) {
  . $cxccLoader
}
# chezmoi-ai-env end
