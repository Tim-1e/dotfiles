param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$projectPath = Join-Path $SourceDir "tools/codex-provider-bridge/CodexProviderBridge.csproj"
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-provider-bridge-test-" + [guid]::NewGuid().ToString("N"))
$publishDir = Join-Path $tmpRoot "publish"

function Start-TestProcess {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [string[]]$Arguments = @(),
    [string[]]$InputLines = @()
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new($Executable)
  foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [Diagnostics.Process]::Start($startInfo)
  foreach ($line in $InputLines) { $process.StandardInput.WriteLine($line) }
  $process.StandardInput.Close()
  if (-not $process.WaitForExit(15000)) {
    $process.Kill($true)
    throw "Process timed out: $Executable"
  }
  $result = [pscustomobject]@{
    ExitCode = $process.ExitCode
    Stdout = $process.StandardOutput.ReadToEnd()
    Stderr = $process.StandardError.ReadToEnd()
  }
  $process.Dispose()
  return $result
}

try {
  New-Item -ItemType Directory -Force -Path $tmpRoot, $publishDir | Out-Null
  & dotnet publish $projectPath -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o $publishDir --nologo
  if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

  $bridgePath = Join-Path $publishDir "codex-provider-bridge.exe"
  if (-not (Test-Path -LiteralPath $bridgePath -PathType Leaf)) { throw "Bridge executable was not published" }

  $fakeServerPath = Join-Path $tmpRoot "fake-app-server.ps1"
  @'
$ErrorActionPreference = "Stop"
[Console]::Error.WriteLine("ARGS=" + ($args | ConvertTo-Json -Compress))
while ($null -ne ($line = [Console]::In.ReadLine())) {
  [Console]::Out.WriteLine($line)
  [Console]::Out.Flush()
}
'@ | Set-Content -LiteralPath $fakeServerPath -Encoding UTF8

  $settingsPath = Join-Path $publishDir "codex-provider-bridge.json"
  [ordered]@{
    realCodexPath = (Get-Process -Id $PID).Path
    realCodexSha256 = (Get-FileHash -LiteralPath (Get-Process -Id $PID).Path -Algorithm SHA256).Hash
    realCodexPrefixArgs = @("-NoLogo", "-NoProfile", "-NonInteractive", "-File", $fakeServerPath)
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

  $listNull = '{"id":"list-null","method":"thread/list","params":{"modelProviders":null,"archived":false}}'
  $listFiltered = '{"id":"list-filtered","method":"thread/list","params":{"modelProviders":["openai"],"archived":true}}'
  $resume = '{"id":"resume","method":"thread/resume","params":{"threadId":"abc","modelProvider":"ai-env-app"}}'
  $invalid = 'not-json'
  $nonStringMethod = '{"id":"weird","method":7,"params":{}}'
  $result = Start-TestProcess -Executable $bridgePath -Arguments @("alpha", "with space") -InputLines @($listNull, $listFiltered, $resume, $invalid, $nonStringMethod)
  if ($result.ExitCode -ne 0) { throw "Bridge failed: $($result.Stderr)" }

  $lines = @($result.Stdout -split '\r?\n' | Where-Object { $_ -ne "" })
  if ($lines.Count -ne 5) { throw "Expected five stdout lines, got $($lines.Count): $($result.Stdout)" }
  foreach ($index in 0, 1) {
    $message = $lines[$index] | ConvertFrom-Json -Depth 20
    if ($message.method -ne "thread/list") { throw "List request method changed" }
    if ($null -eq $message.params.modelProviders -or @($message.params.modelProviders).Count -ne 0) {
      throw "thread/list modelProviders was not replaced with an empty array"
    }
  }
  if ($lines[2] -cne $resume) { throw "thread/resume was modified by the bridge" }
  if ($lines[3] -cne $invalid) { throw "Malformed non-JSON input was not forwarded unchanged" }
  if ($lines[4] -cne $nonStringMethod) { throw "JSON with a non-string method was not forwarded unchanged" }
  if ($result.Stderr -notmatch 'ARGS=\["alpha","with space"\]') { throw "Child arguments or stderr were not forwarded" }

  $missingDir = Join-Path $tmpRoot "missing-settings"
  New-Item -ItemType Directory -Force -Path $missingDir | Out-Null
  $missingBridge = Join-Path $missingDir "codex-provider-bridge.exe"
  Copy-Item -LiteralPath $bridgePath -Destination $missingBridge
  $missingResult = Start-TestProcess -Executable $missingBridge
  if ($missingResult.ExitCode -eq 0 -or $missingResult.Stdout) { throw "Bridge accepted missing settings" }
  if ($missingResult.Stderr -notmatch 'settings') { throw "Missing-settings error is not actionable" }

  [ordered]@{
    realCodexPath = (Get-Process -Id $PID).Path
    realCodexSha256 = ('0' * 64)
    realCodexPrefixArgs = @("-NoLogo", "-NoProfile", "-NonInteractive", "-File", $fakeServerPath)
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
  $hashMismatchResult = Start-TestProcess -Executable $bridgePath
  if ($hashMismatchResult.ExitCode -eq 0 -or $hashMismatchResult.Stdout) { throw "Bridge accepted a downstream hash mismatch" }
  if ($hashMismatchResult.Stderr -notmatch 'hash') { throw "Hash-mismatch error is not actionable" }

  [ordered]@{
    realCodexPath = $bridgePath
    realCodexSha256 = (Get-FileHash -LiteralPath $bridgePath -Algorithm SHA256).Hash
    realCodexPrefixArgs = @()
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
  $recursiveResult = Start-TestProcess -Executable $bridgePath
  if ($recursiveResult.ExitCode -eq 0 -or $recursiveResult.Stdout) { throw "Bridge accepted a recursive downstream path" }
  if ($recursiveResult.Stderr -notmatch 'itself|recursive') { throw "Recursion error is not actionable" }

  Write-Host "Codex provider bridge tests passed"
} finally {
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
