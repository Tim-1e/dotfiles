$script:AiHome = if ($env:AI_ENV_HOME) { [Environment]::ExpandEnvironmentVariables($env:AI_ENV_HOME) } else { $HOME }
$script:AiConfigDir = Join-Path $script:AiHome ".ai-env"
$script:AiRegistryPath = Join-Path $script:AiConfigDir "profiles.json"
$script:AiStatePath = Join-Path $script:AiConfigDir "state.json"
$script:AiSecretsPath = Join-Path $script:AiHome ".ai-secrets\secrets.toml"
$script:LegacyAiStateDir = Join-Path $script:AiHome ".ai-state"
$script:ClaudeRouterBaseUrl = "https://anyrouter.top"

function Get-AiProperty {
  param(
    [AllowNull()]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    $Default = $null
  )

  if ($null -eq $Object) {
    return $Default
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($property) {
    return $property.Value
  }

  return $Default
}

function Expand-AiPath {
  param([AllowNull()][string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $null
  }

  $expanded = [Environment]::ExpandEnvironmentVariables($Path)
  if ($expanded -eq "~") {
    return $script:AiHome
  }

  if ($expanded.StartsWith("~/") -or $expanded.StartsWith("~\")) {
    return (Join-Path $script:AiHome $expanded.Substring(2))
  }

  return $expanded
}

function New-AiDefaultRegistry {
  return [pscustomobject]@{
    schema = 1
    defaults = [pscustomobject]@{
      codex = "sub"
      claude = "sub"
    }
    codex = @(
      [pscustomobject]@{
        name = "sub"
        aliases = @("subscription", "chatgpt")
        mode = "sub"
        home = "~/.codex"
        codex_profile = "sub"
        description = "ChatGPT/Codex subscription login cached under CODEX_HOME"
      },
      [pscustomobject]@{
        name = "api"
        aliases = @("router")
        mode = "api"
        home = "~/.codex"
        codex_profile = "api"
        secret_id = "codex.api"
        windows_secret = "~/.ai-secrets/codex-api.ps1"
        linux_secret = "~/.ai-secrets/codex-api.env"
        description = "Default Codex API router"
      }
    )
    claude = @(
      [pscustomobject]@{
        name = "sub"
        aliases = @("subscription", "claude-sub")
        mode = "sub"
        description = "Claude Code subscription/OAuth login"
      },
      [pscustomobject]@{
        name = "api"
        aliases = @("router", "claude-api")
        mode = "api"
        base_url = "https://anyrouter.top"
        secret_id = "claude.api"
        windows_secret = "~/.ai-secrets/claude-api.ps1"
        linux_secret = "~/.ai-secrets/claude-api.env"
        description = "Default Claude Code API router"
      }
    )
  }
}

function Get-AiRegistry {
  if (Test-Path -LiteralPath $script:AiRegistryPath) {
    try {
      return (Get-Content -Raw -LiteralPath $script:AiRegistryPath | ConvertFrom-Json)
    } catch {
      Write-Warning "Could not read $script:AiRegistryPath. $($_.Exception.Message)"
    }
  }

  return (New-AiDefaultRegistry)
}

function Get-AiToolProfiles {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $registry = Get-AiRegistry
  return @(Get-AiProperty -Object $registry -Name $Tool -Default @())
}

function Get-AiDefaultProfileName {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $registry = Get-AiRegistry
  $defaults = Get-AiProperty -Object $registry -Name "defaults"
  $default = Get-AiProperty -Object $defaults -Name $Tool -Default "sub"
  if ($default) {
    return [string]$default
  }

  return "sub"
}

function Test-AiProfileEnabled {
  param([Parameter(Mandatory = $true)]$Profile)

  $enabled = Get-AiProperty -Object $Profile -Name "enabled" -Default $true
  return ($enabled -ne $false)
}

function Get-AiProfileNames {
  param([Parameter(Mandatory = $true)]$Profile)

  $names = @([string](Get-AiProperty -Object $Profile -Name "name" -Default ""))
  $aliases = @(Get-AiProperty -Object $Profile -Name "aliases" -Default @())
  foreach ($alias in $aliases) {
    if ($alias) {
      $names += [string]$alias
    }
  }

  return ($names | Where-Object { $_ })
}

function Get-AiProfileByName {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $query = $Name.ToLowerInvariant()
  foreach ($profile in Get-AiToolProfiles -Tool $Tool) {
    if (-not (Test-AiProfileEnabled -Profile $profile)) {
      continue
    }

    foreach ($candidate in Get-AiProfileNames -Profile $profile) {
      if ($candidate.ToLowerInvariant() -eq $query) {
        return $profile
      }
    }
  }

  return $null
}

function Get-AiProfileName {
  param([Parameter(Mandatory = $true)]$Profile)

  return [string](Get-AiProperty -Object $Profile -Name "name" -Default "")
}

function Get-AiProfileMode {
  param([Parameter(Mandatory = $true)]$Profile)

  return [string](Get-AiProperty -Object $Profile -Name "mode" -Default "sub")
}

function Get-AiNextProfileName {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $profiles = @(Get-AiToolProfiles -Tool $Tool | Where-Object { Test-AiProfileEnabled -Profile $_ })
  if ($profiles.Count -eq 0) {
    return "sub"
  }

  $saved = Get-AiSavedProfileName -Tool $Tool
  for ($i = 0; $i -lt $profiles.Count; $i++) {
    if ((Get-AiProfileName -Profile $profiles[$i]).ToLowerInvariant() -eq $saved.ToLowerInvariant()) {
      return (Get-AiProfileName -Profile $profiles[($i + 1) % $profiles.Count])
    }
  }

  return (Get-AiDefaultProfileName -Tool $Tool)
}

function Get-AiLegacyStateName {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $legacyName = if ($Tool -eq "codex") { "cx.profile" } else { "cc.profile" }
  $legacyPath = Join-Path $script:LegacyAiStateDir $legacyName
  if (Test-Path -LiteralPath $legacyPath) {
    $value = (Get-Content -Raw -LiteralPath $legacyPath).Trim()
    if ($value) {
      return $value
    }
  }

  return $null
}

function Get-AiState {
  $state = [pscustomobject]@{
    codex = $null
    claude = $null
    updated_at = $null
  }

  if (Test-Path -LiteralPath $script:AiStatePath) {
    try {
      $loaded = Get-Content -Raw -LiteralPath $script:AiStatePath | ConvertFrom-Json
      foreach ($name in @("codex", "claude", "updated_at")) {
        $value = Get-AiProperty -Object $loaded -Name $name
        if ($null -ne $value) {
          $state.$name = $value
        }
      }
    } catch {
      Write-Warning "Could not read $script:AiStatePath. $($_.Exception.Message)"
    }
  }

  if (-not $state.codex) {
    $state.codex = Get-AiLegacyStateName -Tool "codex"
  }
  if (-not $state.claude) {
    $state.claude = Get-AiLegacyStateName -Tool "claude"
  }
  if (-not $state.codex) {
    $state.codex = Get-AiDefaultProfileName -Tool "codex"
  }
  if (-not $state.claude) {
    $state.claude = Get-AiDefaultProfileName -Tool "claude"
  }

  return $state
}

function Save-AiSelectedProfile {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $state = Get-AiState
  $state.$Tool = $Name
  $state.updated_at = (Get-Date).ToUniversalTime().ToString("o")
  New-Item -ItemType Directory -Force -Path $script:AiConfigDir | Out-Null
  $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:AiStatePath -Encoding UTF8
}

function Save-AiRegistry {
  param([Parameter(Mandatory = $true)]$Registry)

  New-Item -ItemType Directory -Force -Path $script:AiConfigDir | Out-Null
  $Registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:AiRegistryPath -Encoding UTF8
}

function Get-AiNameSlug {
  param([Parameter(Mandatory = $true)][string]$Name)

  $slug = $Name.Trim().ToLowerInvariant() -replace '[^a-z0-9_-]+', '-'
  $slug = $slug.Trim("-_")
  if (-not $slug) {
    throw "Profile name '$Name' does not contain any usable letters or numbers."
  }

  return $slug
}

function Assert-AiProfileName {
  param([Parameter(Mandatory = $true)][string]$Name)

  if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9:_-]*$') {
    throw "Profile name '$Name' is not supported. Use letters, numbers, ':', '_' or '-'."
  }
}

function Test-AiProfileNameExists {
  param(
    [Parameter(Mandatory = $true)]$Registry,
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $query = $Name.ToLowerInvariant()
  foreach ($profile in @(Get-AiProperty -Object $Registry -Name $Tool -Default @())) {
    foreach ($candidate in Get-AiProfileNames -Profile $profile) {
      if ($candidate.ToLowerInvariant() -eq $query) {
        return $true
      }
    }
  }

  return $false
}

function Add-AiProfileRegistration {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile
  )

  $name = Get-AiProfileName -Profile $Profile
  Assert-AiProfileName -Name $name
  $registry = Get-AiRegistry
  if (Test-AiProfileNameExists -Registry $registry -Tool $Tool -Name $name) {
    throw "$Tool profile '$name' already exists. Remove it first, or choose another name."
  }

  $profiles = @(Get-AiProperty -Object $registry -Name $Tool -Default @())
  $registry.$Tool = @($profiles + $Profile)
  Save-AiRegistry -Registry $registry
  return $Profile
}

function Remove-AiProfileRegistration {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $registry = Get-AiRegistry
  $query = $Name.ToLowerInvariant()
  $removed = $null
  $kept = @()
  foreach ($profile in @(Get-AiProperty -Object $registry -Name $Tool -Default @())) {
    $matches = $false
    foreach ($candidate in Get-AiProfileNames -Profile $profile) {
      if ($candidate.ToLowerInvariant() -eq $query) {
        $matches = $true
        break
      }
    }

    if ($matches) {
      $removed = $profile
    } else {
      $kept += $profile
    }
  }

  if (-not $removed) {
    throw "$Tool profile '$Name' does not exist."
  }

  $removedName = Get-AiProfileName -Profile $removed
  $registry.$Tool = @($kept)
  Save-AiRegistry -Registry $registry

  if ((Get-AiSavedProfileName -Tool $Tool).ToLowerInvariant() -eq $removedName.ToLowerInvariant()) {
    Save-AiSelectedProfile -Tool $Tool -Name (Get-AiDefaultProfileName -Tool $Tool)
  }

  return $removedName
}

function ConvertFrom-AiManagementArgs {
  param([string[]]$Arguments)

  $options = @{}
  $positionals = @()
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = [string]$Arguments[$i]
    if ($arg.StartsWith("--")) {
      $key = $arg.Substring(2)
      if (-not $key) {
        continue
      }
      if (($i + 1) -lt $Arguments.Count -and -not ([string]$Arguments[$i + 1]).StartsWith("--")) {
        $options[$key] = [string]$Arguments[$i + 1]
        $i++
      } else {
        $options[$key] = "true"
      }
    } else {
      $positionals += $arg
    }
  }

  return [pscustomobject]@{
    Positionals = $positionals
    Options = $options
  }
}

function Get-AiOption {
  param(
    [Parameter(Mandatory = $true)]$Options,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowNull()][string]$Default = $null
  )

  if ($Options.ContainsKey($Name) -and $Options[$Name]) {
    return [string]$Options[$Name]
  }

  return $Default
}

function Get-AiSavedProfileName {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $state = Get-AiState
  $saved = [string](Get-AiProperty -Object $state -Name $Tool -Default "")
  if ($saved) {
    return $saved
  }

  return (Get-AiDefaultProfileName -Tool $Tool)
}

function Get-AiSecretPath {
  param([Parameter(Mandatory = $true)]$Profile)

  $path = Get-AiProperty -Object $Profile -Name "windows_secret"
  if (-not $path) {
    $path = Get-AiProperty -Object $Profile -Name "secret"
  }

  return (Expand-AiPath $path)
}

function Get-AiSecretId {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile
  )

  $secretId = Get-AiProperty -Object $Profile -Name "secret_id"
  if ($secretId) {
    return [string]$secretId
  }

  return "$Tool.$(Get-AiProfileName -Profile $Profile)"
}

function Format-AiSecretPreview {
  param([AllowNull()][string]$Value)

  if (-not $Value) {
    return "<unset>"
  }

  if ($Value.Length -le 12) {
    return ($Value.Substring(0, [Math]::Min(4, $Value.Length)) + "...")
  }

  return ($Value.Substring(0, [Math]::Min(8, $Value.Length)) + "..." + $Value.Substring($Value.Length - 4))
}

function ConvertFrom-AiTomlValue {
  param([AllowNull()][string]$Value)

  if ($null -eq $Value) {
    return $null
  }

  $trimmed = $Value.Trim()
  if ($trimmed -match '^"((?:\\.|[^"])*)"') {
    try {
      return ($Matches[0] | ConvertFrom-Json)
    } catch {
      return $Matches[1]
    }
  }
  if ($trimmed -match "^'([^']*)'") {
    return $Matches[1]
  }
  if ($trimmed -match '^(true|false)\b') {
    return $Matches[1].ToLowerInvariant()
  }

  return (($trimmed -split '\s+#', 2)[0]).Trim()
}

function Get-AiTomlSecretSection {
  param([Parameter(Mandatory = $true)][string]$SecretId)

  $values = @{}
  if (-not (Test-Path -LiteralPath $script:AiSecretsPath)) {
    return $values
  }

  $current = ""
  foreach ($line in Get-Content -LiteralPath $script:AiSecretsPath) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }
    if ($trimmed -match '^\[([^\]]+)\]\s*$') {
      $current = $Matches[1].Trim()
      continue
    }
    if ($current -ne $SecretId) {
      continue
    }
    if ($trimmed -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$') {
      $values[$Matches[1]] = ConvertFrom-AiTomlValue $Matches[2]
    }
  }

  return $values
}

function Test-AiTomlSecretValues {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string[]]$Names
  )

  $section = Get-AiTomlSecretSection -SecretId (Get-AiSecretId -Tool $Tool -Profile $Profile)
  foreach ($name in $Names) {
    if ($section.ContainsKey($name) -and $section[$name]) {
      return $true
    }
  }

  return $false
}

function Set-AiEnvironmentFromTomlSecret {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string[]]$Names
  )

  $secretId = Get-AiSecretId -Tool $Tool -Profile $Profile
  $section = Get-AiTomlSecretSection -SecretId $secretId
  $loaded = $false
  foreach ($name in $Names) {
    if ($section.ContainsKey($name) -and $section[$name]) {
      Set-Item -Path "Env:$name" -Value ([string]$section[$name])
      $loaded = $true
    }
  }

  if ($loaded) {
    return "$script:AiSecretsPath#$secretId"
  }

  return $null
}

function Get-AiSecretDisplay {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string[]]$Names
  )

  if (Test-AiTomlSecretValues -Tool $Tool -Profile $Profile -Names $Names) {
    return "$script:AiSecretsPath#$(Get-AiSecretId -Tool $Tool -Profile $Profile)"
  }

  $legacy = Get-AiSecretPath -Profile $Profile
  if ($legacy) {
    if (Test-Path -LiteralPath $legacy) {
      return $legacy
    }
    return "<missing> $legacy"
  }

  return "<missing> $script:AiSecretsPath#$(Get-AiSecretId -Tool $Tool -Profile $Profile)"
}

function Get-TomlStringValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Key
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $pattern = "^\s*" + [regex]::Escape($Key) + "\s*=\s*(.+)$"
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match $pattern) {
      return [string](ConvertFrom-AiTomlValue $Matches[1])
    }
  }

  return $null
}

function Get-PowerShellEnvAssignment {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $pattern = "^\s*\`$env:" + [regex]::Escape($Name) + "\s*=\s*['`"]([^'`"]+)['`"]"
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match $pattern) {
      return $Matches[1]
    }
  }

  return $null
}

function Get-CodexHome {
  param([Parameter(Mandatory = $true)]$Profile)

  return (Expand-AiPath (Get-AiProperty -Object $Profile -Name "home" -Default "~/.codex"))
}

function Get-CodexRuntimeProfileName {
  param([Parameter(Mandatory = $true)]$Profile)

  $runtimeProfile = Get-AiProperty -Object $Profile -Name "codex_profile"
  if (-not $runtimeProfile) {
    $runtimeProfile = Get-AiProperty -Object $Profile -Name "profile"
  }
  if (-not $runtimeProfile) {
    $runtimeProfile = (Get-AiProfileName -Profile $Profile).Replace(":", "-")
  }

  return [string]$runtimeProfile
}

function Get-CodexProfilePath {
  param([Parameter(Mandatory = $true)]$Profile)

  return (Join-Path (Get-CodexHome -Profile $Profile) "$(Get-CodexRuntimeProfileName -Profile $Profile).config.toml")
}

function Get-CodexExternalCommand {
  $cmd = Get-Command codex -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) {
    throw "Could not find the real codex executable/script in PATH."
  }

  return $cmd.Source
}

function Get-CodexLoginStatusText {
  try {
    $codexCommand = Get-CodexExternalCommand
    return ((& $codexCommand login status 2>&1 | Out-String).Trim())
  } catch {
    return "unavailable: $($_.Exception.Message)"
  }
}

function Get-CodexProviderConfigArgs {
  param([Parameter(Mandatory = $true)]$Profile)

  $configArgs = @()
  $profilePath = Get-CodexProfilePath -Profile $Profile
  $model = Get-TomlStringValue -Path $profilePath -Key "model"
  $provider = Get-TomlStringValue -Path $profilePath -Key "model_provider"
  $reasoning = Get-TomlStringValue -Path $profilePath -Key "model_reasoning_effort"

  if ($model) {
    $configArgs += @("-c", "model=`"$model`"")
  }
  if ($provider) {
    $configArgs += @("-c", "model_provider=`"$provider`"")
  }
  if ($reasoning) {
    $configArgs += @("-c", "model_reasoning_effort=`"$reasoning`"")
  }

  if ($provider) {
    $baseUrl = Get-TomlStringValue -Path $profilePath -Key "base_url"
    $wireApi = Get-TomlStringValue -Path $profilePath -Key "wire_api"
    $envKey = Get-TomlStringValue -Path $profilePath -Key "env_key"
    $requiresOpenAiAuth = Get-TomlStringValue -Path $profilePath -Key "requires_openai_auth"
    $providerName = Get-TomlStringValue -Path $profilePath -Key "name"
    $hasProviderConfig = [bool]($baseUrl -or $wireApi -or $envKey -or $requiresOpenAiAuth -or $providerName)

    if (($provider -notin @("openai", "ollama", "lmstudio", "amazon-bedrock")) -or $hasProviderConfig) {
      if (-not $providerName) {
        $providerName = $provider
      }
      if (-not $wireApi) {
        $wireApi = "responses"
      }

      $configArgs += @("-c", "model_providers.$provider.name=`"$providerName`"")
      if ($baseUrl) {
        $configArgs += @("-c", "model_providers.$provider.base_url=`"$baseUrl`"")
      }
      if ($wireApi) {
        $configArgs += @("-c", "model_providers.$provider.wire_api=`"$wireApi`"")
      }
      if ($envKey) {
        $configArgs += @("-c", "model_providers.$provider.env_key=`"$envKey`"")
      }
      if ($requiresOpenAiAuth) {
        $configArgs += @("-c", "model_providers.$provider.requires_openai_auth=$requiresOpenAiAuth")
      }
    }
  }

  return $configArgs
}

function Get-CodexDoctorArgs {
  param([Parameter(Mandatory = $true)]$Profile)

  return @("doctor", "--json") + (Get-CodexProviderConfigArgs -Profile $Profile)
}

function Get-CodexDoctorReport {
  param([Parameter(Mandatory = $true)]$Profile)

  try {
    $codexCommand = Get-CodexExternalCommand
    $doctorArgs = Get-CodexDoctorArgs -Profile $Profile
    $json = & $codexCommand @doctorArgs 2>$null
    if (-not $json) {
      return $null
    }
    return ($json | ConvertFrom-Json)
  } catch {
    Write-Verbose "Codex doctor failed: $($_.Exception.Message)"
    return $null
  }
}

function Get-CodexCheck {
  param(
    [Parameter(Mandatory = $true)]$Report,
    [Parameter(Mandatory = $true)][string]$Name
  )

  return $Report.checks.PSObject.Properties[$Name].Value
}

function Write-CodexDoctorSummary {
  param([Parameter(Mandatory = $true)]$Profile)

  $report = Get-CodexDoctorReport -Profile $Profile
  if (-not $report) {
    Write-Host "  Doctor: unavailable"
    return
  }

  $auth = Get-CodexCheck -Report $report -Name "auth.credentials"
  $config = Get-CodexCheck -Report $report -Name "config.load"
  $reach = Get-CodexCheck -Report $report -Name "network.provider_reachability"
  $ws = Get-CodexCheck -Report $report -Name "network.websocket_reachability"
  $sandbox = Get-CodexCheck -Report $report -Name "sandbox.helpers"
  $threads = Get-CodexCheck -Report $report -Name "state.rollout_db_parity"
  $updates = Get-CodexCheck -Report $report -Name "updates.status"

  Write-Host "  Doctor: $($report.overallStatus), Codex $($report.codexVersion)"
  if ($config) {
    Write-Host "  Runtime: model=$($config.details.model); provider=$($config.details.'model provider'); mcp=$($config.details.'mcp servers')"
  }
  if ($auth) {
    Write-Host "  Auth: $($auth.status) - $($auth.summary)"
    if ($auth.details.'stored auth mode') {
      Write-Host "  Auth cache: $($auth.details.'stored auth mode'); api_key=$($auth.details.'stored API key'); chatgpt_tokens=$($auth.details.'stored ChatGPT tokens')"
    }
  }
  if ($reach) {
    Write-Host "  Network: $($reach.status) - $($reach.summary)"
  }
  if ($ws) {
    Write-Host "  WebSocket: $($ws.status) - $($ws.summary)"
  }
  if ($sandbox) {
    Write-Host "  Sandbox: approval=$($sandbox.details.'approval policy'); fs=$($sandbox.details.'filesystem sandbox'); net=$($sandbox.details.'network sandbox')"
  }
  if ($threads) {
    Write-Host "  Threads: active=$($threads.details.'rollout DB active rows'); archived=$($threads.details.'rollout DB archived rows'); providers=$($threads.details.'rollout DB model providers')"
  }
  if ($updates) {
    Write-Host "  Updates: $($updates.details.'latest version status')"
  }
}

function Get-ClaudeAuthStatusReport {
  try {
    $json = & claude auth status --json 2>$null
    if (-not $json) {
      return $null
    }
    return ($json | ConvertFrom-Json)
  } catch {
    Write-Verbose "Claude auth status failed: $($_.Exception.Message)"
    return $null
  }
}

function Write-ClaudeExternalStatus {
  $auth = Get-ClaudeAuthStatusReport
  if ($auth) {
    Write-Host "  Auth status: loggedIn=$($auth.loggedIn); method=$($auth.authMethod); provider=$($auth.apiProvider); source=$($auth.apiKeySource ?? '<none>')"
  } else {
    Write-Host "  Auth status: unavailable"
  }

  $statsPath = Join-Path $HOME ".claude\stats-cache.json"
  if (Test-Path -LiteralPath $statsPath) {
    try {
      $stats = Get-Content -Raw -LiteralPath $statsPath | ConvertFrom-Json
      Write-Host "  Local usage cache: sessions=$($stats.totalSessions); messages=$($stats.totalMessages); lastComputed=$($stats.lastComputedDate)"
    } catch {
      Write-Verbose "Could not read Claude stats cache: $($_.Exception.Message)"
    }
  }
}

function Get-LegacyCodexApiKey {
  $legacyAuthFiles = @(
    (Join-Path $HOME ".codex.API\auth.json"),
    (Join-Path $HOME ".codex-api\auth.json")
  )

  foreach ($authFile in $legacyAuthFiles) {
    if (-not (Test-Path -LiteralPath $authFile)) {
      continue
    }

    try {
      $auth = Get-Content -Raw -LiteralPath $authFile | ConvertFrom-Json
      if ($auth.OPENAI_API_KEY) {
        return [string]$auth.OPENAI_API_KEY
      }
    } catch {
      Write-Warning "Could not read legacy Codex API key from $authFile. $($_.Exception.Message)"
    }
  }

  return $null
}

function Get-AiToolEnvKeys {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $keys = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($profile in Get-AiToolProfiles -Tool $Tool) {
    $envObj = Get-AiProperty -Object $profile -Name "env"
    if ($envObj) {
      foreach ($prop in $envObj.PSObject.Properties) {
        [void]$keys.Add($prop.Name)
      }
    }
  }

  return $keys
}

function Clear-AiToolExtraEnv {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  foreach ($key in (Get-AiToolEnvKeys -Tool $Tool)) {
    Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
  }
}

function Set-AiProfileExtraEnv {
  param([Parameter(Mandatory = $true)]$Profile)

  $envObj = Get-AiProperty -Object $Profile -Name "env"
  if (-not $envObj) {
    return
  }

  foreach ($prop in $envObj.PSObject.Properties) {
    Set-Item -Path "Env:$($prop.Name)" -Value ([string]$prop.Value)
  }
}

function Get-AiProfileEnvSummary {
  param([Parameter(Mandatory = $true)]$Profile)

  $envObj = Get-AiProperty -Object $Profile -Name "env"
  if (-not $envObj) {
    return "<none>"
  }

  return [string]@($envObj.PSObject.Properties).Count
}

function Split-AiEnvArguments {
  param([string[]]$Arguments)

  $envMap = [ordered]@{}
  $rest = @()
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = [string]$Arguments[$i]
    if (($arg -eq "--env" -or $arg -eq "--set-env") -and ($i + 1) -lt $Arguments.Count) {
      $pair = [string]$Arguments[$i + 1]
      $i++
      $idx = $pair.IndexOf("=")
      if ($idx -lt 1) {
        throw "Invalid --env value '$pair'. Expected KEY=VALUE."
      }
      $envMap[$pair.Substring(0, $idx)] = $pair.Substring($idx + 1)
    } else {
      $rest += $arg
    }
  }

  return [pscustomobject]@{ Env = $envMap; Rest = @($rest) }
}

function Test-AiInteractive {
  if ($env:AI_ENV_NONINTERACTIVE) {
    return $false
  }
  try {
    if ([Console]::IsInputRedirected) {
      return $false
    }
  } catch {
    return $false
  }
  return $true
}

function Read-AiInput {
  param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Default = ""
  )

  $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
  $answer = Read-Host -Prompt $label
  if ([string]::IsNullOrWhiteSpace($answer)) {
    return $Default
  }
  return $answer.Trim()
}

function Read-AiSecretInput {
  param([Parameter(Mandatory = $true)][string]$Prompt)

  $secure = Read-Host -Prompt $Prompt -AsSecureString
  if (-not $secure -or $secure.Length -eq 0) {
    return ""
  }
  $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Add-AiTomlSecretValue {
  param(
    [Parameter(Mandatory = $true)][string]$SecretId,
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $sectionExists = $false
  if (Test-Path -LiteralPath $script:AiSecretsPath) {
    foreach ($line in Get-Content -LiteralPath $script:AiSecretsPath) {
      if ($line.Trim() -eq "[$SecretId]") {
        $sectionExists = $true
        break
      }
    }
  }
  if ($sectionExists) {
    return $false
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:AiSecretsPath) | Out-Null
  $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
  $block = @()
  if (Test-Path -LiteralPath $script:AiSecretsPath) {
    $block += ""
  }
  $block += "[$SecretId]"
  $block += "$Key = `"$escaped`""
  Add-Content -LiteralPath $script:AiSecretsPath -Value (($block -join "`n") + "`n") -Encoding UTF8
  return $true
}

function Resolve-AiSecretScaffold {
  param(
    [Parameter(Mandatory = $true)][string]$SecretId,
    [Parameter(Mandatory = $true)][string]$Key,
    [bool]$Interactive = $false
  )

  $existing = Get-AiTomlSecretSection -SecretId $SecretId
  if ($existing.ContainsKey($Key) -and $existing[$Key]) {
    return "$script:AiSecretsPath [$SecretId] $Key (already set)"
  }

  if ($Interactive) {
    $value = Read-AiSecretInput -Prompt "Enter $Key for [$SecretId] (blank to skip)"
    if ($value) {
      if (Add-AiTomlSecretValue -SecretId $SecretId -Key $Key -Value $value) {
        return "wrote $script:AiSecretsPath [$SecretId] $Key"
      }
      return "$script:AiSecretsPath [$SecretId] already present; left unchanged"
    }
  }

  return "add $Key to $script:AiSecretsPath [$SecretId]"
}

function Set-CodexProfileEnvironment {
  param([Parameter(Mandatory = $true)]$Profile)

  $mode = Get-AiProfileMode -Profile $Profile
  $name = Get-AiProfileName -Profile $Profile
  $env:CODEX_HOME = Get-CodexHome -Profile $Profile
  $env:AI_CODEX_PROFILE = Get-CodexRuntimeProfileName -Profile $Profile
  $env:AI_CODEX_LABEL = $name
  New-Item -ItemType Directory -Force -Path $env:CODEX_HOME | Out-Null
  Remove-Item Env:CODEX_API_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
  Clear-AiToolExtraEnv -Tool "codex"

  $secretSource = "<none>"
  if ($mode -eq "api") {
    $secret = Get-AiSecretPath -Profile $Profile
    $tomlSource = Set-AiEnvironmentFromTomlSecret -Tool "codex" -Profile $Profile -Names @("OPENAI_API_KEY", "CODEX_API_KEY")
    if ($tomlSource) {
      $secretSource = $tomlSource
    } elseif ($secret -and (Test-Path -LiteralPath $secret)) {
      . $secret
      $secretSource = $secret
    }

    if (-not $env:OPENAI_API_KEY -and $env:CODEX_API_KEY) {
      $env:OPENAI_API_KEY = $env:CODEX_API_KEY
    }

    if (-not $env:OPENAI_API_KEY -and $name -eq "api") {
      $legacyKey = Get-LegacyCodexApiKey
      if ($legacyKey) {
        $env:OPENAI_API_KEY = $legacyKey
        $secretSource = "legacy .codex.API auth.json"
      }
    }

    if (-not $env:OPENAI_API_KEY) {
      throw "cx $name needs OPENAI_API_KEY. Put it in $script:AiSecretsPath section [$(Get-AiSecretId -Tool 'codex' -Profile $Profile)] or $secret."
    }
  }

  Set-AiProfileExtraEnv -Profile $Profile
  return $secretSource
}

function Set-ClaudeProfileEnvironment {
  param([Parameter(Mandatory = $true)]$Profile)

  $mode = Get-AiProfileMode -Profile $Profile
  $name = Get-AiProfileName -Profile $Profile
  $env:AI_CLAUDE_LABEL = $name
  foreach ($envName in @("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL")) {
    Remove-Item "Env:$envName" -ErrorAction SilentlyContinue
  }
  Clear-AiToolExtraEnv -Tool "claude"

  $secretSource = "<none>"
  if ($mode -eq "api") {
    $secret = Get-AiSecretPath -Profile $Profile
    $tomlSource = Set-AiEnvironmentFromTomlSecret -Tool "claude" -Profile $Profile -Names @("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL")
    if ($tomlSource) {
      $secretSource = $tomlSource
    } elseif ($secret -and (Test-Path -LiteralPath $secret)) {
      . $secret
      $secretSource = $secret
    }

    if (-not $env:ANTHROPIC_API_KEY -and -not $env:ANTHROPIC_AUTH_TOKEN -and $name -eq "api") {
      $userApiKey = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User")
      $userAuthToken = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User")
      if ($userApiKey) {
        $env:ANTHROPIC_API_KEY = $userApiKey
        $secretSource = "user environment variable"
      }
      if ($userAuthToken) {
        $env:ANTHROPIC_AUTH_TOKEN = $userAuthToken
        $secretSource = "user environment variable"
      }
    }

    if (-not $env:ANTHROPIC_BASE_URL) {
      $env:ANTHROPIC_BASE_URL = [string](Get-AiProperty -Object $Profile -Name "base_url" -Default $script:ClaudeRouterBaseUrl)
    }

    if (-not $env:ANTHROPIC_API_KEY -and -not $env:ANTHROPIC_AUTH_TOKEN) {
      throw "cc $name needs ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN in $script:AiSecretsPath section [$(Get-AiSecretId -Tool 'claude' -Profile $Profile)] or $secret."
    }
  }

  Set-AiProfileExtraEnv -Profile $Profile
  return $secretSource
}

# Join an origin and a relative path into a URL (no double slashes).
function Join-Path-Uri {
  param([Parameter(Mandatory = $true)][string]$Origin, [Parameter(Mandatory = $true)][string]$Relative)
  $o = $Origin.TrimEnd('/')
  $r = $Relative.TrimStart('/')
  return "$o/$r"
}

# Returns probe target (base origin + auth headers) for a profile WITHOUT
# mutating $env:. Used by Get-AiProfileHealth so a `cc list` check never
# disturbs the current shell session.
function Get-AiProfileProbeTarget {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile
  )

  $result = [pscustomobject]@{
    BaseOrigin  = $null
    Headers     = @{}
    ProbeModel  = $null
    SecretOk    = $false
    SecretLabel = "<none>"
  }

  $mode = Get-AiProfileMode -Profile $Profile
  if ($mode -ne "api") {
    return $result
  }

  $secretId = Get-AiSecretId -Tool $Tool -Profile $Profile
  $section = Get-AiTomlSecretSection -SecretId $secretId
  $legacyPath = Get-AiSecretPath -Profile $Profile

  if ($Tool -eq "claude") {
    $baseUrl = $null
    if ($section.ContainsKey("ANTHROPIC_BASE_URL") -and $section["ANTHROPIC_BASE_URL"]) {
      $baseUrl = [string]$section["ANTHROPIC_BASE_URL"]
    } elseif ($legacyPath -and (Test-Path -LiteralPath $legacyPath)) {
      $baseUrl = Get-PowerShellEnvAssignment -Path $legacyPath -Name "ANTHROPIC_BASE_URL"
    }
    if (-not $baseUrl) {
      $baseUrl = [string](Get-AiProperty -Object $Profile -Name "base_url" -Default $script:ClaudeRouterBaseUrl)
    }

    $authToken = $null
    $apiKey = $null
    if ($section.ContainsKey("ANTHROPIC_AUTH_TOKEN") -and $section["ANTHROPIC_AUTH_TOKEN"]) {
      $authToken = [string]$section["ANTHROPIC_AUTH_TOKEN"]
    }
    if ($section.ContainsKey("ANTHROPIC_API_KEY") -and $section["ANTHROPIC_API_KEY"]) {
      $apiKey = [string]$section["ANTHROPIC_API_KEY"]
    }
    if (-not $authToken -and -not $apiKey -and $legacyPath -and (Test-Path -LiteralPath $legacyPath)) {
      $authToken = Get-PowerShellEnvAssignment -Path $legacyPath -Name "ANTHROPIC_AUTH_TOKEN"
      $apiKey = Get-PowerShellEnvAssignment -Path $legacyPath -Name "ANTHROPIC_API_KEY"
    }
    if (-not $authToken) { $authToken = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User") }
    if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User") }

    $headers = @{ "anthropic-version" = "2023-06-01" }
    if ($authToken) { $headers["Authorization"] = "Bearer $authToken" }
    if ($apiKey) { $headers["x-api-key"] = $apiKey }
    # Some relays gate on User-Agent (e.g. AixHan rejects unknown clients with a
    # 400 "Client not allowed ..."). Identify as the real Claude Code CLI so the
    # probe sees what an actual session sees. Override per-profile via `probe_ua`.
    $headers["User-Agent"] = [string](Get-AiProperty -Object $Profile -Name "probe_ua" -Default "claude-cli/1.0.119 (external, cli)")

    $result.BaseOrigin = $baseUrl
    $result.Headers = $headers
    $result.SecretOk = [bool]($authToken -or $apiKey)
    $result.SecretLabel = if ($result.SecretOk) { "$script:AiSecretsPath#$secretId" } else { "<none>" }
    $result.ProbeModel = [string](Get-AiProperty -Object $Profile -Name "probe_model" -Default "claude-3-5-haiku-20241022")
    return $result
  }

  # codex
  $apiKey = $null
  if ($section.ContainsKey("OPENAI_API_KEY") -and $section["OPENAI_API_KEY"]) {
    $apiKey = [string]$section["OPENAI_API_KEY"]
  }
  if (-not $apiKey -and $section.ContainsKey("CODEX_API_KEY") -and $section["CODEX_API_KEY"]) {
    $apiKey = [string]$section["CODEX_API_KEY"]
  }
  if (-not $apiKey -and $legacyPath -and (Test-Path -LiteralPath $legacyPath)) {
    $apiKey = Get-PowerShellEnvAssignment -Path $legacyPath -Name "OPENAI_API_KEY"
  }
  if (-not $apiKey) { $apiKey = Get-LegacyCodexApiKey }

  $result.BaseOrigin = (Get-CodexBaseUrl -Profile $Profile)
  $result.Headers = if ($apiKey) { @{ "Authorization" = "Bearer $apiKey" } } else { @{} }
  # Identify as the real Codex CLI for relays that gate on User-Agent.
  $result.Headers["User-Agent"] = [string](Get-AiProperty -Object $Profile -Name "probe_ua" -Default "codex_cli_rs/0.40.0 (external, cli)")
  $result.SecretOk = [bool]$apiKey
  $result.SecretLabel = if ($apiKey) { "$script:AiSecretsPath#$secretId" } else { "<none>" }

  # Probe with a cheap model by default (low cost + low latency). A profile may
  # override via `probe_model` — required for provider-specific namespaces that
  # do not serve GPT models (e.g. GLM -> set probe_model = "glm-4.5-flash").
  $result.ProbeModel = [string](Get-AiProperty -Object $Profile -Name "probe_model" -Default "gpt-5.4-mini")
  return $result
}

# Build a probe plan for one profile WITHOUT making any request. Returns either:
#   @{ Early = <result> }            -> no live probe (sub mode / missing config)
#   @{ Headers; Kind; Candidates }   -> ready to fire; Candidates is an array of
#                                       @{ Label; Url; Body; Check }. For codex
#                                       also EffLabel/AltLabel (wire_api driven).
# Splitting plan-building (pure, instant) from request-firing lets `cc/cx health`
# fire every profile's requests concurrently instead of one-by-one.
function Get-AiProfileProbePlan {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile
  )

  $mode = Get-AiProfileMode -Profile $Profile
  if ($mode -ne "api") {
    return @{ Early = [pscustomobject]@{ Status = "skip"; LatencyMs = 0; Method = $null; Error = "subscription mode (no remote probe)" } }
  }

  $target = Get-AiProfileProbeTarget -Tool $Tool -Profile $Profile
  if (-not $target.BaseOrigin) {
    return @{ Early = [pscustomobject]@{ Status = "down"; LatencyMs = 0; Method = $null; Error = "missing base_url" } }
  }
  if (-not $target.SecretOk) {
    return @{ Early = [pscustomobject]@{ Status = "down"; LatencyMs = 0; Method = $null; Error = "missing credentials" } }
  }

  $origin = [string]$target.BaseOrigin
  $origin = $origin.TrimEnd('/')
  $candidates = @()
  $effLabel = $null; $altLabel = $null

  if ($Tool -eq "claude") {
    $apiBase = if ($origin -match '/v1$') { ($origin -replace '/v1$', '') } else { $origin }
    $candidates += @{
      Label = "messages"
      Url   = Join-Path-Uri $apiBase "v1/messages"
      Body  = @{ model = $target.ProbeModel; max_tokens = 1; messages = @(@{ role = "user"; content = "." }) } |
        ConvertTo-Json -Depth 5 -Compress
      Check = "messages"
    }
  } else {
    $hasVersion   = $origin -match '/v\d+$'
    $responsesRel = if ($hasVersion) { "responses" } else { "v1/responses" }
    $chatRel      = if ($hasVersion) { "chat/completions" } else { "v1/chat/completions" }
    $model        = if ($target.ProbeModel) { $target.ProbeModel } else { "probe" }
    $candidates += @{
      Label = "responses"
      Url   = Join-Path-Uri $origin $responsesRel
      Body  = @{ model = $model; input = "."; max_output_tokens = 1 } | ConvertTo-Json -Depth 5 -Compress
      Check = "responses"
    }
    $candidates += @{
      Label = "chat"
      Url   = Join-Path-Uri $origin $chatRel
      Body  = @{ model = $model; max_tokens = 1; messages = @(@{ role = "user"; content = "." }) } |
        ConvertTo-Json -Depth 5 -Compress
      Check = "chat"
    }
    # verdict endpoint = the configured wire_api (default responses)
    $cfgPath = Get-CodexProfilePath -Profile $Profile
    $wireApi = $null
    if ($cfgPath -and (Test-Path -LiteralPath $cfgPath)) {
      $wireApi = Get-TomlStringValue -Path $cfgPath -Key "wire_api"
    }
    $effLabel = if ($wireApi -and $wireApi -match "chat") { "chat" } else { "responses" }
    $altLabel = if ($effLabel -eq "chat") { "responses" } else { "chat" }
  }

  return @{ Headers = $target.Headers; Kind = $Tool; Candidates = $candidates; EffLabel = $effLabel; AltLabel = $altLabel }
}

# Fire ONE probe request. Uses Invoke-RestMethod (Invoke-WebRequest stalls to
# timeout on some relays under PS7). Returns Ok/Code/LatencyMs/Detail/Body; the
# caller validates the body (Test-AiProbeBody) and applies the verdict.
function Invoke-AiProbeRequest {
  param($Url, $Headers, $Body, [int]$TimeoutSec = 20)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $r = [pscustomobject]@{ Ok = $false; Code = 0; LatencyMs = 0; Detail = $null; Body = $null }
  try {
    $j = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Body `
      -ContentType "application/json" -TimeoutSec $TimeoutSec -ErrorAction Stop
    $sw.Stop()
    $r.Code = 200
    $r.LatencyMs = [int]$sw.ElapsedMilliseconds
    $r.Body = $j
  } catch {
    $sw.Stop()
    $r.LatencyMs = [int]$sw.ElapsedMilliseconds
    if ($_.Exception.Response) {
      $r.Code = [int]$_.Exception.Response.StatusCode
      $r.Detail = "HTTP $($r.Code)"
    } else {
      $r.Detail = $_.Exception.Message
    }
  }
  return $r
}

# Validate a fired request's parsed body against its Check type (mutates $Req:
# sets Ok + Detail). A non-2xx Code is left as-is (not ok).
function Test-AiProbeBody {
  param($Req, [string]$Check)
  if ($Req.Code -lt 200 -or $Req.Code -ge 300) { return }
  $valid = $false
  $j = $Req.Body
  switch ($Check) {
    "messages"  { $valid = (($j.content -is [array]) -and ($j.content.Count -gt 0)) -or ($j.type -eq "message") }
    "responses" { $valid = (($j.output -is [array] -and $j.output.Count -gt 0) -or $j.output_text -or $j.status -eq "completed") }
    "chat"      { $valid = (($j.choices -is [array]) -and ($j.choices.Count -gt 0)) }
  }
  $Req.Ok = $valid
  if (-not $valid -and -not $Req.Detail) { $Req.Detail = "200 but no generated content" }
}

# Resolve a final health verdict from per-candidate results (a hashtable keyed
# by candidate Label -> request object from Invoke-AiProbeRequest). Instant.
function Resolve-AiProfileHealth {
  param($Plan, $Results, [int]$DegradedMs = 8000)

  if ($Plan.Kind -eq "claude") {
    $m = $Results["messages"]
    if ($m.Ok) {
      $st = if ($m.LatencyMs -gt $DegradedMs) { "degraded" } else { "healthy" }
      return [pscustomobject]@{ Status = $st; LatencyMs = $m.LatencyMs; Method = "generation"; Error = $null }
    }
    if ($m.Code -eq 429 -or ($m.Code -ge 500 -and $m.Code -lt 600)) {
      return [pscustomobject]@{ Status = "degraded"; LatencyMs = $m.LatencyMs; Method = "none"; Error = ("POST /v1/messages " + $m.Detail + " (transient)") }
    }
    return [pscustomobject]@{ Status = "down"; LatencyMs = $m.LatencyMs; Method = "none"; Error = ("POST /v1/messages " + $m.Detail) }
  }

  # codex: verdict = the endpoint matching the configured wire_api.
  $eff = $Results[$Plan.EffLabel]
  $alt = $Results[$Plan.AltLabel]
  if ($eff.Ok) {
    $st = if ($eff.LatencyMs -gt $DegradedMs) { "degraded" } else { "healthy" }
    return [pscustomobject]@{ Status = $st; LatencyMs = $eff.LatencyMs; Method = "generation:$($Plan.EffLabel)"; Error = $null }
  }
  $note = "POST /$($Plan.EffLabel) -> $($eff.Detail)"
  if ($alt.Ok) {
    $note += "; but /$($Plan.AltLabel) works -> set wire_api = `"$($Plan.AltLabel)`" in config.toml"
    return [pscustomobject]@{ Status = "degraded"; LatencyMs = $eff.LatencyMs; Method = "none"; Error = $note }
  }
  if ($eff.Code -eq 429 -or ($eff.Code -ge 500 -and $eff.Code -lt 600)) {
    $note += "; /$($Plan.AltLabel) -> $($alt.Detail) (transient)"
    return [pscustomobject]@{ Status = "degraded"; LatencyMs = $eff.LatencyMs; Method = "none"; Error = $note }
  }
  $note += "; /$($Plan.AltLabel) -> $($alt.Detail)"
  return [pscustomobject]@{ Status = "down"; LatencyMs = $eff.LatencyMs; Method = "none"; Error = $note }
}

# Probe a profile by issuing a real (cheap/free) API request and measuring
# latency. Returns: Status = healthy | degraded | down | skip; LatencyMs; Error.
#   Claude: GET {base}/v1/models (free), fall back to POST /v1/messages (1 token)
#   Codex:  GET {base}/v1/models (free)
# Never mutates the current process environment.
function Get-AiProfileHealth {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile,
    [int]$TimeoutSec = 20,
    [int]$DegradedMs = 8000
  )

  # Single-profile path (used by `cx doctor`, switch-time, etc.). `cc/cx health`
  # builds plans for ALL profiles and fires requests concurrently via
  # Invoke-AiProbeRequest directly; this wrapper stays sequential for one-off use.
  $plan = Get-AiProfileProbePlan -Tool $Tool -Profile $Profile
  if ($plan.ContainsKey("Early")) { return $plan.Early }

  $results = @{}
  foreach ($c in $plan.Candidates) {
    $req = Invoke-AiProbeRequest -Url $c.Url -Headers $plan.Headers -Body $c.Body -TimeoutSec $TimeoutSec
    Test-AiProbeBody -Req $req -Check $c.Check
    $results[$c.Label] = $req
  }
  return Resolve-AiProfileHealth -Plan $plan -Results $results -DegradedMs $DegradedMs
}

# --- Health cache (on-demand only; no background scheduler) ---
# Caches probe results in ~/.ai-env/health.json with a TTL so `cc list` / `cx
# list` and switch-time selection don't re-probe on every call. A probe fires
# only when the cache is stale or -Fresh is passed.

function Get-AiHealthCachePath {
  return (Join-Path $script:AiConfigDir "health.json")
}

function Read-AiHealthCache {
  $path = Get-AiHealthCachePath
  if (-not (Test-Path -LiteralPath $path)) { return @{} }
  try {
    $obj = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $h = @{}
    if ($obj) { foreach ($prop in $obj.PSObject.Properties) { $h[$prop.Name] = $prop.Value } }
    return $h
  } catch { return @{} }
}

function Write-AiHealthCacheEntry {
  param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)]$Entry)
  $path = Get-AiHealthCachePath
  $h = Read-AiHealthCache
  $h[$Key] = $Entry
  New-Item -ItemType Directory -Force -Path $script:AiConfigDir | Out-Null
  $h | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Clear-AiHealthCache {
  $path = Get-AiHealthCachePath
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
}

# Probe a profile with a TTL cache. Returns the health result plus ProbedAt
# (unix seconds) and a Cached flag (true if served from cache).
function Get-AiProfileHealthCached {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile,
    [switch]$Fresh,
    [switch]$CacheOnly,
    [int]$TtlSec = 300
  )

  $name = Get-AiProfileName -Profile $Profile
  $key = "$Tool.$name"

  # Fresh cache hit short-circuits (whether or not CacheOnly).
  if (-not $Fresh) {
    $cache = Read-AiHealthCache
    if ($cache.ContainsKey($key)) {
      $entry = $cache[$key]
      $probedAt = 0
      try { $probedAt = [int64]$entry.probedAt } catch { }
      $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      if ($probedAt -gt 0 -and ($now - $probedAt) -lt $TtlSec) {
        return [pscustomobject]@{
          Status    = [string]$entry.status
          LatencyMs = [int]$entry.latencyMs
          Method    = [string]$entry.method
          Error     = $entry.error
          ProbedAt  = $probedAt
          Cached    = $true
        }
      }
    }
  }

  # CacheOnly: never probe (keeps `list`/`status`/switch instant — a stale or
  # unprobed entry shows as skip ⏭, matching the lean list). Use `health` /
  # `status --refresh` to force a live probe.
  if ($CacheOnly) {
    return [pscustomobject]@{ Status = "skip"; LatencyMs = 0; Method = $null; Error = $null; ProbedAt = 0; Cached = $false }
  }

  $result = Get-AiProfileHealth -Tool $Tool -Profile $Profile
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  Write-AiHealthCacheEntry -Key $key -Entry ([pscustomobject]@{
      status    = $result.Status
      latencyMs = $result.LatencyMs
      method    = $result.Method
      error     = $result.Error
      probedAt  = $now
    })

  return [pscustomobject]@{
    Status    = $result.Status
    LatencyMs = $result.LatencyMs
    Method    = $result.Method
    Error     = $result.Error
    ProbedAt  = $now
    Cached    = $false
  }
}

function New-CodexProfileConfig {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [AllowNull()][string]$BaseUrl,
    [AllowNull()][string]$Model,
    [AllowNull()][string]$EnvKey,
    [AllowNull()][string]$ProviderName
  )

  $mode = Get-AiProfileMode -Profile $Profile
  $profilePath = Get-CodexProfilePath -Profile $Profile
  if (Test-Path -LiteralPath $profilePath) {
    return $profilePath
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
  $providerId = "api-router"
  $displayName = if ($ProviderName) { $ProviderName } else { (Get-AiProfileName -Profile $Profile).Replace(":", " ") }
  $keyName = if ($EnvKey) { $EnvKey } else { "OPENAI_API_KEY" }

  if ($mode -eq "api") {
    $url = if ($BaseUrl) { $BaseUrl } else { "https://your-router.example/v1" }
    $lines = @("model_provider = `"$providerId`"")
    if ($Model) {
      $lines += "model = `"$Model`""
    }
    $lines += @(
      "disable_response_storage = true"
      ""
      "[model_providers.$providerId]"
      "name = `"$displayName`""
      "base_url = `"$url`""
      "env_key = `"$keyName`""
    )
    (($lines -join "`n") + "`n") | Set-Content -LiteralPath $profilePath -Encoding UTF8
  } else {
    $lines = @("model_provider = `"openai`"")
    if ($Model) {
      $lines += "model = `"$Model`""
    }
    (($lines -join "`n") + "`n") | Set-Content -LiteralPath $profilePath -Encoding UTF8
  }

  return $profilePath
}

function Add-CodexApiProfile {
  param([string[]]$Arguments)

  $split = Split-AiEnvArguments -Arguments $Arguments
  $parsed = ConvertFrom-AiManagementArgs -Arguments $split.Rest
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cx add-api <name> [--base-url URL] [--env-key NAME] [--provider-name NAME] [--model MODEL] [--home PATH] [--env KEY=VALUE ...]"
  }

  $name = [string]$parsed.Positionals[0]
  Assert-AiProfileName -Name $name
  $slug = Get-AiNameSlug -Name $name
  $interactive = Test-AiInteractive
  $profileHome = Get-AiOption -Options $parsed.Options -Name "home" -Default "~/.codex"
  $runtimeProfile = Get-AiOption -Options $parsed.Options -Name "profile" -Default "api-$($slug.Replace(':', '-'))"
  $secretId = Get-AiOption -Options $parsed.Options -Name "secret-id" -Default "codex.$name"
  $model = Get-AiOption -Options $parsed.Options -Name "model"

  $baseUrl = Get-AiOption -Options $parsed.Options -Name "base-url"
  if (-not $baseUrl) {
    $baseUrl = if ($interactive) { Read-AiInput -Prompt "Codex base_url" -Default "https://your-router.example/v1" } else { "https://your-router.example/v1" }
  }
  $envKey = Get-AiOption -Options $parsed.Options -Name "env-key"
  if (-not $envKey) {
    $envKey = if ($interactive) { Read-AiInput -Prompt "Codex env_key (secret variable name)" -Default "OPENAI_API_KEY" } else { "OPENAI_API_KEY" }
  }
  $providerName = Get-AiOption -Options $parsed.Options -Name "provider-name"
  if (-not $providerName) {
    $providerName = if ($interactive) { Read-AiInput -Prompt "Codex provider display name" -Default $name } else { $name }
  }

  $profile = [pscustomobject]@{
    name = $name
    aliases = @()
    mode = "api"
    home = $profileHome
    codex_profile = $runtimeProfile
    secret_id = $secretId
    windows_secret = "~/.ai-secrets/codex-$slug.ps1"
    linux_secret = "~/.ai-secrets/codex-$slug.env"
    description = "Codex API profile"
  }
  if ($split.Env.Count -gt 0) {
    $profile | Add-Member -NotePropertyName "env" -NotePropertyValue ([pscustomobject]$split.Env)
  }
  Add-AiProfileRegistration -Tool "codex" -Profile $profile | Out-Null
  $profilePath = New-CodexProfileConfig -Profile $profile -BaseUrl $baseUrl -Model $model -EnvKey $envKey -ProviderName $providerName
  $secretState = Resolve-AiSecretScaffold -SecretId $secretId -Key $envKey -Interactive $interactive

  Write-Host "Added Codex API profile '$name'."
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  CODEX_HOME: $(Expand-AiPath $profileHome)"
  Write-Host "  Config: $profilePath"
  Write-Host "  Secret: $secretState"
  if ($split.Env.Count -gt 0) {
    Write-Host "  Env: $(@($split.Env.Keys) -join ', ')"
  }
}

function Add-CodexSubProfile {
  param([string[]]$Arguments)

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cx add-sub <name> [--home PATH] [--model MODEL]"
  }

  $name = [string]$parsed.Positionals[0]
  Assert-AiProfileName -Name $name
  $slug = Get-AiNameSlug -Name $name
  $interactive = Test-AiInteractive
  $profileHome = Get-AiOption -Options $parsed.Options -Name "home"
  if (-not $profileHome) {
    $profileHome = if ($interactive) { Read-AiInput -Prompt "Codex CODEX_HOME for this subscription" -Default "~/.codex-$slug" } else { "~/.codex-$slug" }
  }
  $runtimeProfile = Get-AiOption -Options $parsed.Options -Name "profile" -Default "sub"
  $model = Get-AiOption -Options $parsed.Options -Name "model"

  $profile = [pscustomobject]@{
    name = $name
    aliases = @()
    mode = "sub"
    home = $profileHome
    codex_profile = $runtimeProfile
    description = "Codex subscription profile"
  }
  Add-AiProfileRegistration -Tool "codex" -Profile $profile | Out-Null
  $profilePath = New-CodexProfileConfig -Profile $profile -Model $model
  Write-Host "Added Codex subscription profile '$name'."
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  CODEX_HOME: $(Expand-AiPath $profileHome)"
  Write-Host "  Config: $profilePath"
  Write-Host "  Login: CODEX_HOME=`"$(Expand-AiPath $profileHome)`" codex login"
}

function Remove-CodexProfile {
  param([string[]]$Arguments)

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cx remove <name> [--delete-config]"
  }

  $existing = Get-AiProfileByName -Tool "codex" -Name ([string]$parsed.Positionals[0])
  if (-not $existing) {
    throw "codex profile '$($parsed.Positionals[0])' does not exist."
  }
  $profilePath = Get-CodexProfilePath -Profile $existing
  $removed = Remove-AiProfileRegistration -Tool "codex" -Name ([string]$parsed.Positionals[0])
  if ((Get-AiOption -Options $parsed.Options -Name "delete-config") -eq "true") {
    Remove-Item -LiteralPath $profilePath -ErrorAction SilentlyContinue
  }

  Write-Host "Removed Codex profile '$removed'."
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  Config: $(if (Test-Path -LiteralPath $profilePath) { $profilePath } else { '<removed or absent>' })"
}

function Add-ClaudeApiProfile {
  param([string[]]$Arguments)

  $split = Split-AiEnvArguments -Arguments $Arguments
  $parsed = ConvertFrom-AiManagementArgs -Arguments $split.Rest
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cc add-api <name> [--base-url URL] [--env-key NAME] [--env KEY=VALUE ...]"
  }

  $name = [string]$parsed.Positionals[0]
  Assert-AiProfileName -Name $name
  $slug = Get-AiNameSlug -Name $name
  $interactive = Test-AiInteractive
  $secretId = Get-AiOption -Options $parsed.Options -Name "secret-id" -Default "claude.$name"

  $baseUrl = Get-AiOption -Options $parsed.Options -Name "base-url"
  if (-not $baseUrl) {
    $baseUrl = if ($interactive) { Read-AiInput -Prompt "Claude base_url" -Default $script:ClaudeRouterBaseUrl } else { $script:ClaudeRouterBaseUrl }
  }
  $envKey = Get-AiOption -Options $parsed.Options -Name "env-key"
  if (-not $envKey) {
    $envKey = if ($interactive) { Read-AiInput -Prompt "Claude secret variable (ANTHROPIC_AUTH_TOKEN or ANTHROPIC_API_KEY)" -Default "ANTHROPIC_AUTH_TOKEN" } else { "ANTHROPIC_AUTH_TOKEN" }
  }

  $profile = [pscustomobject]@{
    name = $name
    aliases = @()
    mode = "api"
    base_url = $baseUrl
    secret_id = $secretId
    windows_secret = "~/.ai-secrets/claude-$slug.ps1"
    linux_secret = "~/.ai-secrets/claude-$slug.env"
    description = "Claude Code API profile"
  }
  if ($split.Env.Count -gt 0) {
    $profile | Add-Member -NotePropertyName "env" -NotePropertyValue ([pscustomobject]$split.Env)
  }
  Add-AiProfileRegistration -Tool "claude" -Profile $profile | Out-Null
  $secretState = Resolve-AiSecretScaffold -SecretId $secretId -Key $envKey -Interactive $interactive

  Write-Host "Added Claude Code API profile '$name'."
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  Base URL: $baseUrl"
  Write-Host "  Secret: $secretState"
  if ($split.Env.Count -gt 0) {
    Write-Host "  Env: $(@($split.Env.Keys) -join ', ')"
  }
}

function Add-ClaudeSubProfile {
  param([string[]]$Arguments)

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cc add-sub <name>"
  }

  $name = [string]$parsed.Positionals[0]
  Assert-AiProfileName -Name $name
  $profile = [pscustomobject]@{
    name = $name
    aliases = @()
    mode = "sub"
    description = "Claude Code subscription profile"
  }
  Add-AiProfileRegistration -Tool "claude" -Profile $profile | Out-Null
  Write-Host "Added Claude Code subscription profile '$name'."
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  Login: claude /login"
}

function Remove-ClaudeProfile {
  param([string[]]$Arguments)

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cc remove <name>"
  }

  $removed = Remove-AiProfileRegistration -Tool "claude" -Name ([string]$parsed.Positionals[0])
  Write-Host "Removed Claude Code profile '$removed'."
  Write-Host "  Registry: $script:AiRegistryPath"
}

function Get-CodexRolloutTokenStats {
  param(
    [Parameter(Mandatory = $true)][string]$CodexHome,
    [int]$Days = 30
  )

  $sessionsDir = Join-Path $CodexHome "sessions"
  $cutoff = (Get-Date).ToUniversalTime().AddDays(-1 * $Days)
  $stats = [ordered]@{
    Sessions = 0
    Samples = 0
    Input = 0L
    CachedInput = 0L
    Output = 0L
    ReasoningOutput = 0L
    Total = 0L
    Since = $cutoff
  }

  if (-not (Test-Path -LiteralPath $sessionsDir)) {
    return [pscustomobject]$stats
  }

  foreach ($file in Get-ChildItem -LiteralPath $sessionsDir -Recurse -File -Filter "*.jsonl" -ErrorAction SilentlyContinue) {
    if ($file.LastWriteTimeUtc -lt $cutoff) {
      continue
    }

    $latest = $null
    $samples = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue) {
      if ($line -notlike '*"token_count"*') {
        continue
      }
      try {
        $json = $line | ConvertFrom-Json
        if ($json.type -ne "event_msg" -or $json.payload.type -ne "token_count") {
          continue
        }
        $usage = $json.payload.info.total_token_usage
        if ($usage) {
          $latest = $usage
          $samples++
        }
      } catch {
      }
    }

    if ($latest) {
      $stats.Sessions++
      $stats.Samples += $samples
      $stats.Input += [int64](Get-AiProperty -Object $latest -Name "input_tokens" -Default 0)
      $stats.CachedInput += [int64](Get-AiProperty -Object $latest -Name "cached_input_tokens" -Default (Get-AiProperty -Object $latest -Name "cache_read_input_tokens" -Default 0))
      $stats.Output += [int64](Get-AiProperty -Object $latest -Name "output_tokens" -Default 0)
      $stats.ReasoningOutput += [int64](Get-AiProperty -Object $latest -Name "reasoning_output_tokens" -Default 0)
      $total = [int64](Get-AiProperty -Object $latest -Name "total_tokens" -Default 0)
      if ($total -le 0) {
        $total = [int64](Get-AiProperty -Object $latest -Name "input_tokens" -Default 0) + [int64](Get-AiProperty -Object $latest -Name "output_tokens" -Default 0)
      }
      $stats.Total += $total
    }
  }

  return [pscustomobject]$stats
}

function Format-AiTokenCount {
  param([int64]$Value)

  if ($Value -ge 1000000) {
    return ("{0:N2}M" -f ($Value / 1000000.0))
  }
  if ($Value -ge 1000) {
    return ("{0:N1}K" -f ($Value / 1000.0))
  }
  return [string]$Value
}

function Format-AiTokenBar {
  param(
    [int64]$Value,
    [int64]$Total
  )

  if ($Total -le 0 -or $Value -le 0) {
    return ""
  }

  $width = [Math]::Max(1, [Math]::Round(($Value / [double]$Total) * 24))
  return ("#" * $width)
}

function Show-CodexStats {
  param([string[]]$Arguments)

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  $daysText = Get-AiOption -Options $parsed.Options -Name "days" -Default "30"
  $days = 30
  if (-not [int]::TryParse($daysText, [ref]$days) -or $days -lt 1) {
    throw "cx stats --days must be a positive integer."
  }

  $saved = Get-AiSavedProfileName -Tool "codex"
  $profile = Get-AiProfileByName -Tool "codex" -Name ($env:AI_CODEX_LABEL ?? $saved)
  if (-not $profile) {
    $profile = Get-AiProfileByName -Tool "codex" -Name (Get-AiDefaultProfileName -Tool "codex")
  }
  $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } elseif ($profile) { Get-CodexHome -Profile $profile } else { Join-Path $script:AiHome ".codex" }
  $stats = Get-CodexRolloutTokenStats -CodexHome $codexHome -Days $days

  Write-Host "Codex local token stats:"
  Write-Host "  CODEX_HOME: $codexHome"
  Write-Host "  Window: last $days days"
  Write-Host "  Sessions with usage: $($stats.Sessions)"
  Write-Host "  Token samples: $($stats.Samples)"
  Write-Host "  Total: $(Format-AiTokenCount $stats.Total) ($($stats.Total))"
  foreach ($row in @(
    @("input", $stats.Input),
    @("cached", $stats.CachedInput),
    @("output", $stats.Output),
    @("reasoning", $stats.ReasoningOutput)
  )) {
    $label = $row[0]
    $value = [int64]$row[1]
    Write-Host ("  {0,-9} {1,10}  {2}" -f $label, (Format-AiTokenCount $value), (Format-AiTokenBar -Value $value -Total $stats.Total))
  }
}

function Get-CodexBaseUrl {
  param([Parameter(Mandatory = $true)]$Profile)

  $profilePath = Get-CodexProfilePath -Profile $Profile
  $baseUrl = Get-TomlStringValue -Path $profilePath -Key "base_url"
  if (-not $baseUrl) {
    $baseUrl = Get-TomlStringValue -Path (Join-Path (Get-CodexHome -Profile $Profile) "config.toml") -Key "openai_base_url"
  }
  if (-not $baseUrl) {
    $baseUrl = "built-in OpenAI/ChatGPT endpoint"
  }

  return $baseUrl
}

function Write-CodexSwitchStatus {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [string]$SecretSource
  )

  $mode = Get-AiProfileMode -Profile $Profile
  $profilePath = Get-CodexProfilePath -Profile $Profile
  Write-Host "Codex state switched: $(Get-AiProfileName -Profile $Profile)"
  Write-Host "  Run next: codex"
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  CODEX_HOME: $env:CODEX_HOME"
  if (Test-Path -LiteralPath $profilePath) {
    Write-Host "  Profile: $(Get-CodexRuntimeProfileName -Profile $Profile) ($profilePath)"
  } else {
    Write-Host "  Profile: <default> ($profilePath missing)"
  }
  Write-Host "  Base URL: $(Get-CodexBaseUrl -Profile $Profile)"
  Write-Host "  Cached login: $(Get-CodexLoginStatusText)"

  if ($mode -eq "api") {
    Write-Host "  OPENAI_API_KEY: $(Format-AiSecretPreview $env:OPENAI_API_KEY)"
    Write-Host "  Secret source: $SecretSource"
    Write-Host "  API local check: profile file=$((Test-Path -LiteralPath $profilePath)); key=$([bool]$env:OPENAI_API_KEY)"
  } else {
    Write-Host "  OPENAI_API_KEY: <cleared>"
    Write-Host "  Subscription quota: not exposed by Codex CLI"
  }

  # Cached health line (instant — no network). `codex doctor` is deliberately
  # NOT run here: it does live network/websocket checks that stall the switch.
  # Use `cx doctor` for the full diagnostic on demand.
  $h = Get-AiProfileHealthCached -Tool "codex" -Profile $Profile -CacheOnly
  Write-Host ("  Health: " + (Format-AiHealthCell $h) + $(if ($h.Error) { "  " + $h.Error } else { '' }))
}

function Write-ClaudeSwitchStatus {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [string]$SecretSource
  )

  $mode = Get-AiProfileMode -Profile $Profile
  Write-Host "Claude Code state switched: $(Get-AiProfileName -Profile $Profile)"
  Write-Host "  Run next: claude"
  Write-Host "  Registry: $script:AiRegistryPath"
  if ($mode -eq "api") {
    Write-Host "  ANTHROPIC_BASE_URL: $env:ANTHROPIC_BASE_URL"
    Write-Host "  ANTHROPIC_API_KEY: $(Format-AiSecretPreview $env:ANTHROPIC_API_KEY)"
    Write-Host "  ANTHROPIC_AUTH_TOKEN: $(Format-AiSecretPreview $env:ANTHROPIC_AUTH_TOKEN)"
    Write-Host "  Secret source: $SecretSource"
    Write-Host "  API local check: auth=$([bool]($env:ANTHROPIC_API_KEY -or $env:ANTHROPIC_AUTH_TOKEN)); url=$([bool]$env:ANTHROPIC_BASE_URL)"
  } else {
    Write-Host "  Anthropic API env: <cleared>"
    Write-Host "  Subscription status: local Claude login is used if present"
  }

  Write-ClaudeExternalStatus
}

function Show-CxHelp {
  @"
cx - switch Codex state for this PowerShell session

Usage:
  cx                 Cycle through enabled Codex profiles
  cx sub             Use a named subscription profile
  cx sub:work        Use another subscription profile, if registered
  cx api             Use the default API profile
  cx api:docker      Use a named API profile
  cx list            List registry profiles and local file status
  cx status          Print current saved/process state; --refresh re-probes health
  cx stats           Summarize local rollout token usage
  cx add-api NAME    Register a Codex API profile that shares ~/.codex by default
                     Options: --base-url URL --env-key NAME --provider-name NAME
                              --model MODEL --home PATH --env KEY=VALUE
                     Prompts for missing base-url/env-key and the secret in a terminal.
  cx add-sub NAME    Register an isolated Codex subscription CODEX_HOME
  cx remove NAME     Remove a Codex profile registration
  cx probe-model NAME [MODEL]  Set/clear health-probe model (default gpt-5.4-mini)
  cx default [NAME]   Show/set the default (primary) profile
  cx edit            Open the profile registry (profiles.json) in $EDITOR
  cx health           Probe & report profile health (🟢🟡🔴, parallel); --fresh re-probes
  cx doctor           Run codex doctor full diagnostic (slow, on-demand)
  cx health-clear     Clear the health probe cache
  cx next            Cycle to the next enabled profile
  cx help            Show this help

Config:
  Registry: ~/.ai-env/profiles.json
  State:    ~/.ai-env/state.json
  Secrets:  ~/.ai-secrets/secrets.toml

After switching, run Codex separately:
  codex
  codex exec "your task"

Notes:
  cx does not launch Codex. The PowerShell codex shim injects --profile for runtime commands.
  Subscription uses codex login cached under the selected CODEX_HOME.
  API mode does not run codex login --with-api-key; it loads OPENAI_API_KEY only for this shell.
  Multiple API profiles can share ~/.codex. Multiple subscription accounts need separate home values.
  Add commands only write profile metadata and Codex config. Put real tokens in secrets.toml.
  Legacy ~/.ai-secrets/*.ps1 files are still accepted as a fallback.
"@ | Write-Host
}

function Show-CcHelp {
  @"
cc - switch Claude Code state for this PowerShell session

Usage:
  cc                 Cycle through enabled Claude Code profiles
  cc sub             Clear Anthropic API env and use local Claude subscription login
  cc sub:work        Use another subscription profile, if registered
  cc api             Use the default API profile
  cc api:docker      Use a named API profile
  cc list            List registry profiles and local file status
  cc status          Print current saved/process state; --refresh re-probes health
  cc add-api NAME    Register a Claude Code API profile
                     Options: --base-url URL --env-key NAME --env KEY=VALUE (repeatable)
                     Prompts for missing base-url and the secret in a terminal.
  cc add-sub NAME    Register a Claude Code subscription label
  cc remove NAME     Remove a Claude Code profile registration
  cc probe-model NAME [MODEL]  Set/clear health-probe model (default claude-3-5-haiku)
  cc default [NAME]   Show/set the default (primary) profile
  cc edit            Open the profile registry (profiles.json) in $EDITOR
  cc health           Probe & report profile health (🟢🟡🔴, parallel); --fresh re-probes
  cc health-clear     Clear the health probe cache
  cc next            Cycle to the next enabled profile
  cc help            Show this help

Config:
  Registry: ~/.ai-env/profiles.json
  State:    ~/.ai-env/state.json
  Secrets:  ~/.ai-secrets/secrets.toml

After switching, run Claude Code separately:
  claude

Notes:
  cc does not launch Claude Code. Claude reads the environment variables set in this shell.
  A Claude API profile can define base_url; otherwise https://anyrouter.top is used.
  --env adds non-secret per-profile vars (e.g. ANTHROPIC_DEFAULT_SONNET_MODEL,
    CLAUDE_CODE_AUTO_COMPACT_WINDOW) stored in the registry; exported on switch and
    cleared when switching to another profile so values do not leak.
  Add commands only write profile metadata. Put real tokens in secrets.toml.
  Legacy ~/.ai-secrets/*.ps1 files are still accepted as a fallback.
"@ | Write-Host
}

# Compact one-line health cell for list/status tables.
function Format-AiHealthCell {
  param([AllowNull()]$H)
  if (-not $H) { return "?" }
  $code = $null
  if ($H.Error -and ($H.Error -match 'HTTP (\d{3})')) { $code = $Matches[1] }
  switch ($H.Status) {
    "healthy"  { "🟢" + $H.LatencyMs + "ms" }
    "degraded" { "🟡" + ($(if ($code) { $code } else { "slow" })) }
    "down"     { "🔴" + ($(if ($code) { $code } else { "err" })) }
    "skip"     { "⏭" }
    default    { "?" }
  }
}

function Test-AiFreshFlag {
  param([AllowNull()][string[]]$Tokens)
  if (-not $Tokens) { return $false }
  foreach ($t in $Tokens) { if ($t -in @("--fresh", "-f")) { return $true } }
  return $false
}

# Health cell read ONLY from the cache (no live probe) — used by `list` so it
# stays fast/offline. Fresh cache -> status icon; stale/never-probed -> ⏭ to
# signal "run `<tool> health` to refresh".
function Get-AiHealthCellCached {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [Parameter(Mandatory = $true)]$Profile,
    [int]$TtlSec = 300
  )
  $key = "$Tool." + (Get-AiProfileName -Profile $Profile)
  $cache = Read-AiHealthCache
  if (-not $cache.ContainsKey($key)) { return "⏭" }
  $e = $cache[$key]
  $probedAt = 0
  try { $probedAt = [int64]$e.probedAt } catch { }
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($probedAt -gt 0 -and ($now - $probedAt) -lt $TtlSec) {
    return Format-AiHealthCell $e
  }
  return "⏭"
}

# Set or clear a profile's probe_model (the model used by Get-AiProfileHealth).
# Different relays serve different model sets — e.g. some only serve the latest
# 4.6 models and return "No available providers" for haiku, causing false 503s.
# Default probe models: claude=claude-3-5-haiku-20241022, codex=gpt-5.4-mini.
function Set-AiProfileProbeModel {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [string[]]$Arguments
  )

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: probe-model <name> [model]  (omit model to clear -> default)"
  }
  $query = ([string]$parsed.Positionals[0]).ToLowerInvariant()
  $model = if ($parsed.Positionals.Count -ge 2) { [string]$parsed.Positionals[1] } else { "" }

  $registry = Get-AiRegistry
  $found = $false
  foreach ($profile in @(Get-AiProperty -Object $registry -Name $Tool -Default @())) {
    $matched = $false
    foreach ($cand in Get-AiProfileNames -Profile $profile) {
      if ($cand.ToLowerInvariant() -eq $query) { $matched = $true; break }
    }
    if (-not $matched) { continue }
    $found = $true
    $pname = Get-AiProfileName -Profile $profile
    if ($model) {
      if ($profile.PSObject.Properties.Name -contains 'probe_model') {
        $profile.probe_model = $model
      } else {
        $profile | Add-Member -NotePropertyName probe_model -NotePropertyValue $model
      }
      Write-Host "Set $Tool '$pname' probe_model = $model"
    } else {
      if ($profile.PSObject.Properties.Name -contains 'probe_model') {
        $profile.PSObject.Properties.Remove('probe_model')
        Write-Host "Cleared $Tool '$pname' probe_model (back to default)"
      } else {
        Write-Host "$Tool '$pname' has no probe_model set (already default)"
      }
    }
    break
  }
  if (-not $found) { throw "$Tool profile '$($parsed.Positionals[0])' not found." }
  Save-AiRegistry -Registry $registry
}

# Auto-failover selection: return the first NON-down profile in priority order
# (default profile first, then the rest). Degraded/skip are usable; only down
# (🔴) is skipped. If everything is down, fall back to the default so a switch
# still succeeds (user can investigate via `list`). On-demand only — probes go
# through the cache, so this is cheap within the TTL window.
function Get-AiHealthyProfileName {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $defaultName = Get-AiDefaultProfileName -Tool $Tool
  $profiles = @(Get-AiToolProfiles -Tool $Tool | Where-Object { Test-AiProfileEnabled -Profile $_ })
  $defaultProfile = $null
  $others = @()
  foreach ($p in $profiles) {
    if ((Get-AiProfileName -Profile $p) -eq $defaultName) { $defaultProfile = $p } else { $others += $p }
  }
  $ordered = if ($defaultProfile) { @($defaultProfile) + $others } else { $others }

  foreach ($p in $ordered) {
    # Cache-only: no-arg cc/cx must stay instant. If the cache is empty/stale
    # every entry reads skip (not "down"), so the default is chosen without
    # probing. Run `cc health` first to populate health for auto-failover.
    $h = Get-AiProfileHealthCached -Tool $Tool -Profile $p -CacheOnly
    # Only auto-select a profile with a cached POSITIVE signal (healthy/
    # degraded). Unprobed api profiles and subscription profiles both read
    # "skip" and are NOT auto-selected (we can't confirm they're up). Run
    # `cc health` first to populate health for real auto-failover.
    if ($h.Status -eq "healthy" -or $h.Status -eq "degraded") {
      return (Get-AiProfileName -Profile $p)
    }
  }
  return $defaultName
}

# Show or set the default (primary) profile for a tool. With no name, prints the
# current default; with a name, validates it exists and writes defaults.<tool>.
function Set-AiDefaultProfile {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [string[]]$Arguments
  )

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  $current = Get-AiDefaultProfileName -Tool $Tool
  if ($parsed.Positionals.Count -lt 1) {
    Write-Host "$Tool default = $current"
    return
  }
  $name = [string]$parsed.Positionals[0]
  if (-not (Get-AiProfileByName -Tool $Tool -Name $name)) {
    throw "Unknown $Tool profile '$name'."
  }
  $registry = Get-AiRegistry
  $defaults = Get-AiProperty -Object $registry -Name "defaults"
  if (-not $defaults) {
    $defaults = [pscustomobject]@{}
    $registry | Add-Member -NotePropertyName defaults -NotePropertyValue $defaults
  }
  if ($defaults.PSObject.Properties.Name -contains $Tool) {
    $defaults.$Tool = $name
  } else {
    $defaults | Add-Member -NotePropertyName $Tool -NotePropertyValue $name
  }
  Save-AiRegistry -Registry $registry
  Write-Host "Set $Tool default = $name"
}

# Drop cache entries for profiles that no longer exist (keeps health.json tidy
# after `cc/cx remove`). Called from the list commands.
function Sync-AiHealthCache {
  param([Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool)

  $cache = Read-AiHealthCache
  if ($cache.Count -eq 0) { return }
  $valid = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($p in Get-AiToolProfiles -Tool $Tool) {
    [void]$valid.Add("$Tool." + (Get-AiProfileName -Profile $p))
  }
  $changed = $false
  foreach ($k in @($cache.Keys)) {
    if ($k.StartsWith("$Tool.") -and -not $valid.Contains($k)) { $cache.Remove($k); $changed = $true }
  }
  if ($changed) {
    $path = Get-AiHealthCachePath
    New-Item -ItemType Directory -Force -Path $script:AiConfigDir | Out-Null
    $cache | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
  }
}

function Get-CodexProfileRows {
  $saved = Get-AiSavedProfileName -Tool "codex"
  foreach ($profile in Get-AiToolProfiles -Tool "codex") {
    $mode = Get-AiProfileMode -Profile $profile
    $profileHome = Get-CodexHome -Profile $profile
    $profilePath = Get-CodexProfilePath -Profile $profile
    $secretOk = if ($mode -eq "api") {
      (Test-AiTomlSecretValues -Tool "codex" -Profile $profile -Names @("OPENAI_API_KEY", "CODEX_API_KEY")) -or
        ((Get-AiSecretPath -Profile $profile) -and (Test-Path -LiteralPath (Get-AiSecretPath -Profile $profile)))
    } else {
      $true
    }
    $configOk = Test-Path -LiteralPath $profilePath
    $ready = if ($mode -eq "api" -and -not $configOk) {
      "missing config"
    } elseif (-not $secretOk) {
      "missing secret"
    } elseif ($mode -eq "sub" -and -not $configOk) {
      "ok default"
    } else {
      "ok"
    }
    $name = Get-AiProfileName -Profile $profile
    [pscustomobject]@{
      Sel = if ($name -eq $saved) { "*" } else { " " }
      Name = $name
      Mode = $mode
      Health = Get-AiHealthCellCached -Tool "codex" -Profile $profile
      Profile = Get-CodexRuntimeProfileName -Profile $profile
      Ready = $ready
      Home = $profileHome
      Config = if (Test-Path -LiteralPath $profilePath) { $profilePath } else { "<missing> $profilePath" }
      Secret = if ($mode -eq "api") { Get-AiSecretDisplay -Tool "codex" -Profile $profile -Names @("OPENAI_API_KEY", "CODEX_API_KEY") } else { "<none>" }
      BaseUrl = Get-CodexBaseUrl -Profile $profile
      Env = Get-AiProfileEnvSummary -Profile $profile
    }
  }
}

function Get-ClaudeProfileRows {
  $saved = Get-AiSavedProfileName -Tool "claude"
  foreach ($profile in Get-AiToolProfiles -Tool "claude") {
    $mode = Get-AiProfileMode -Profile $profile
    $secret = if ($mode -eq "api") { Get-AiSecretPath -Profile $profile } else { "<none>" }
    $secretOk = if ($mode -eq "api") {
      (Test-AiTomlSecretValues -Tool "claude" -Profile $profile -Names @("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN")) -or
        ($secret -and (Test-Path -LiteralPath $secret))
    } else {
      $true
    }
    $name = Get-AiProfileName -Profile $profile
    $baseUrl = if ($mode -eq "api") {
      $secretId = Get-AiSecretId -Tool "claude" -Profile $profile
      $tomlSection = Get-AiTomlSecretSection -SecretId $secretId
      if ($tomlSection.ContainsKey("ANTHROPIC_BASE_URL") -and $tomlSection["ANTHROPIC_BASE_URL"]) {
        $tomlSection["ANTHROPIC_BASE_URL"]
      } elseif ($secret -and (Test-Path -LiteralPath $secret)) {
        $configured = Get-PowerShellEnvAssignment -Path $secret -Name "ANTHROPIC_BASE_URL"
        if ($configured) { $configured } else { Get-AiProperty -Object $profile -Name "base_url" -Default $script:ClaudeRouterBaseUrl }
      } else {
        Get-AiProperty -Object $profile -Name "base_url" -Default $script:ClaudeRouterBaseUrl
      }
    } else {
      "local Claude subscription login"
    }

    [pscustomobject]@{
      Sel = if ($name -eq $saved) { "*" } else { " " }
      Name = $name
      Mode = $mode
      Health = Get-AiHealthCellCached -Tool "claude" -Profile $profile
      Ready = if ($secretOk) { "ok" } else { "missing secret" }
      Secret = if ($mode -eq "api") { Get-AiSecretDisplay -Tool "claude" -Profile $profile -Names @("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN") } else { "<none>" }
      BaseUrl = $baseUrl
      Env = Get-AiProfileEnvSummary -Profile $profile
    }
  }
}

function Show-CodexList {
  Write-Host "Codex profiles ($script:AiRegistryPath):"
  Get-CodexProfileRows | Format-Table Sel, Name, Mode, Health, Profile, BaseUrl -AutoSize
  Write-Host "  (Health = cached snapshot, ⏭=stale/unprobed; run 'cx health' to refresh)" -ForegroundColor DarkGray
}

function Show-ClaudeList {
  Write-Host "Claude Code profiles ($script:AiRegistryPath):"
  Get-ClaudeProfileRows | Format-Table Sel, Name, Mode, Health, BaseUrl -AutoSize
  Write-Host "  (Health = cached snapshot, ⏭=stale/unprobed; run 'cc health' to refresh)" -ForegroundColor DarkGray
}

# Dedicated health report — keeps `list`/`status` focused on config; health is
# its own concern. Probes every profile via the cache; --fresh forces re-probe.
function Show-AiHealth {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("codex", "claude")][string]$Tool,
    [switch]$Fresh,
    [int]$DegradedMs = 8000,
    [int]$TimeoutSec = 10
  )
  Sync-AiHealthCache -Tool $Tool
  $label = if ($Tool -eq "codex") { "Codex" } else { "Claude Code" }
  $saved = Get-AiSavedProfileName -Tool $Tool
  $profiles = @(Get-AiToolProfiles -Tool $Tool)

  # Phase 1 (instant): build a plan per profile. Cached/Early results resolve
  # immediately; stale/missing profiles queue real requests. $display holds the
  # current cell/method/note for each profile so the table can be redrawn as
  # probes land (pending rows show ⏳…).
  $tasks = [System.Collections.Generic.List[object]]::new()
  $display = @{}            # name -> @{ Health; Method; Note; Pending }
  $plans = @{}              # name -> plan (for verdict)
  $expected = @{}           # name -> #candidates (1 claude / 2 codex)
  $cellOf = {
    param($h)
    if ($h) { Format-AiHealthCell $h } else { "?" }
  }
  foreach ($p in $profiles) {
    $n = Get-AiProfileName -Profile $p
    $plan = Get-AiProfileProbePlan -Tool $Tool -Profile $p
    if ($plan.ContainsKey("Early")) {
      $e = $plan.Early
      $display[$n] = @{ Health = (& $cellOf $e); Method = ($(if ($e.Method) { $e.Method } else { "-" })); Note = ($(if ($e.Error) { $e.Error } else { "" })); Pending = $false }
      continue
    }
    $plans[$n] = $plan
    $useCache = $false
    if (-not $Fresh) {
      $cached = Get-AiProfileHealthCached -Tool $Tool -Profile $p -CacheOnly
      if ($cached.Cached) {
        $display[$n] = @{ Health = (& $cellOf $cached); Method = ($(if ($cached.Method) { $cached.Method } else { "-" })); Note = ($(if ($cached.Error) { $cached.Error } else { "" })); Pending = $false }
        $useCache = $true
      }
    }
    if (-not $useCache) {
      $display[$n] = @{ Health = "⏳…"; Method = "-"; Note = "probing…"; Pending = $true }
      foreach ($c in $plan.Candidates) {
        $tasks.Add([pscustomobject]@{
          Name = $n; Label = $c.Label; Url = $c.Url; Headers = $plan.Headers; Body = $c.Body; Check = $c.Check; Timeout = $TimeoutSec
        })
      }
      $expected[$n] = @($plan.Candidates).Count
    }
  }

  # Build the table rows from the live $display state (final summary).
  $renderRows = {
    foreach ($p in $profiles) {
      $n = Get-AiProfileName -Profile $p
      $d = $display[$n]
      if (-not $d) { $d = @{ Health = "?"; Method = "-"; Note = ""; Pending = $false } }
      [pscustomobject]@{
        Sel    = if ($n -eq $saved) { "*" } else { " " }
        Name   = $n
        Health = $d.Health
        Method = $d.Method
        Note   = $d.Note
      }
    }
  }

  # Probe block: builtins only (no engine functions in the child runsape). Body
  # is validated INSIDE the block — objects crossing the runsape boundary get
  # XML-serialized, so `-is [array]` would fail in the parent; returning only
  # primitives sidesteps that.
  $probeBlock = {
    $t = $_; $timeout = $t.Timeout
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = [pscustomobject]@{ Name = $t.Name; Label = $t.Label; Ok = $false; Code = 0; LatencyMs = 0; Detail = $null }
    try {
      $j = Invoke-RestMethod -Uri $t.Url -Method Post -Headers $t.Headers -Body $t.Body `
        -ContentType "application/json" -TimeoutSec $timeout -ErrorAction Stop
      $sw.Stop()
      $r.Code = 200; $r.LatencyMs = [int]$sw.ElapsedMilliseconds
      $valid = $false
      switch ($t.Check) {
        "messages"  { $valid = (($j.content -is [array]) -and ($j.content.Count -gt 0)) -or ($j.type -eq "message") }
        "responses" { $valid = (($j.output -is [array] -and $j.output.Count -gt 0) -or $j.output_text -or $j.status -eq "completed") }
        "chat"      { $valid = (($j.choices -is [array]) -and ($j.choices.Count -gt 0)) }
      }
      $r.Ok = $valid
      if (-not $valid) { $r.Detail = "200 but no generated content" }
    } catch {
      $sw.Stop()
      $r.LatencyMs = [int]$sw.ElapsedMilliseconds
      if ($_.Exception.Response) { $r.Code = [int]$_.Exception.Response.StatusCode; $r.Detail = "HTTP " + $r.Code }
      else { $r.Detail = $_.Exception.Message }
    }
    $r
  }

  # Cache + display update for a profile once ALL its candidates are in.
  $finalize = {
    param($n)
    $h = Resolve-AiProfileHealth -Plan $plans[$n] -Results $reqs[$n] -DegradedMs $DegradedMs
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Write-AiHealthCacheEntry -Key "$Tool.$n" -Entry ([pscustomobject]@{
        status = $h.Status; latencyMs = $h.LatencyMs; method = $h.Method; error = $h.Error; probedAt = $now
      })
    $display[$n] = @{ Health = (Format-AiHealthCell $h); Method = ($(if ($h.Method) { $h.Method } else { "-" })); Note = ($(if ($h.Error) { $h.Error } else { "" })); Pending = $false }
  }

  $footer = "  (health " + ($(if ($Fresh) { "re-probed (fresh, parallel)" } else { "cached <=5min" })) + "; '" + $Tool + " health --fresh' re-probe, '" + $Tool + " health-clear' clears)"

  Write-Host "$label profile health ($script:AiRegistryPath):"

  # Probe concurrently and STREAM each result as it lands — one Write-Host line
  # per completed profile (fastest first). This is the watchdog/live feel the
  # user asked for, and it is terminal-safe: no ANSI cursor save/restore and no
  # in-place redraw (those can deadlock an interactive host with ForEach-Object
  # -Parallel, or mis-render under conhost). A final aligned table follows.
  if ($tasks.Count -gt 0) {
    $probeProfileCount = 0
    foreach ($n in $expected.Keys) { $probeProfileCount += 1 }
    Write-Host ("  probing {0} profile(s) in parallel (results stream as they resolve)…" -f $probeProfileCount) -ForegroundColor DarkGray
    $reqs = @{}; $doneCount = @{}
    $tasks | Microsoft.PowerShell.Core\ForEach-Object -Parallel $probeBlock -ThrottleLimit ([Math]::Max(8, $tasks.Count)) | ForEach-Object {
      if (-not $reqs.ContainsKey($_.Name)) { $reqs[$_.Name] = @{}; $doneCount[$_.Name] = 0 }
      $reqs[$_.Name][$_.Label] = $_
      $doneCount[$_.Name] += 1
      if ($doneCount[$_.Name] -ge $expected[$_.Name]) {
        & $finalize $_.Name
        $d = $display[$_.Name]
        Write-Host ("    {0} {1,-14} {2}" -f $d.Health, $_.Name, $d.Note) -ForegroundColor DarkGray
      }
    }
  }

  # Final registry-ordered summary (cached profiles land here too).
  Write-Host ""
  (& $renderRows) | Format-Table -AutoSize
  Write-Host $footer -ForegroundColor DarkGray
}

function Show-CodexStatus {
  param([switch]$Fresh)
  $saved = Get-AiSavedProfileName -Tool "codex"
  $profile = Get-AiProfileByName -Tool "codex" -Name ($env:AI_CODEX_LABEL ?? $saved)
  if (-not $profile) {
    $profile = Get-AiProfileByName -Tool "codex" -Name (Get-AiDefaultProfileName -Tool "codex")
  }

  $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Get-CodexHome -Profile $profile }
  Write-Host "Codex state:"
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  State: $script:AiStatePath"
  Write-Host "  Saved: $saved"
  Write-Host "  Process label: $($env:AI_CODEX_LABEL ?? '<unset>')"
  Write-Host "  Process profile: $($env:AI_CODEX_PROFILE ?? '<unset>')"
  Write-Host "  CODEX_HOME: $codexHome"
  Write-Host "  OPENAI_API_KEY: $(Format-AiSecretPreview $env:OPENAI_API_KEY)"
  Write-Host "  Cached login: $(Get-CodexLoginStatusText)"
  if ($profile) {
    $h = Get-AiProfileHealthCached -Tool "codex" -Profile $profile -Fresh:$Fresh -CacheOnly:(-not $Fresh)
    Write-Host ("  Health: " + (Format-AiHealthCell $h) + $(if ($h.Error) { "  " + $h.Error } else { '' }))
  }
}

# On-demand `codex doctor` (slow: real network/websocket checks). Kept out of
# `cx status` so status stays instant; run this only for the full Codex
# self-diagnostic. Injects the active profile's provider via -c overrides.
function Show-CodexDoctor {
  $saved = Get-AiSavedProfileName -Tool "codex"
  $profile = Get-AiProfileByName -Tool "codex" -Name ($env:AI_CODEX_LABEL ?? $saved)
  if (-not $profile) { $profile = Get-AiProfileByName -Tool "codex" -Name (Get-AiDefaultProfileName -Tool "codex") }
  if (-not $profile) { Write-Host "No codex profile to diagnose."; return }
  Write-CodexDoctorSummary -Profile $profile
}

function Show-ClaudeStatus {
  param([switch]$Fresh)
  $saved = Get-AiSavedProfileName -Tool "claude"
  Write-Host "Claude Code state:"
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  State: $script:AiStatePath"
  Write-Host "  Saved: $saved"
  Write-Host "  Process label: $($env:AI_CLAUDE_LABEL ?? '<unset>')"
  Write-Host "  ANTHROPIC_BASE_URL: $($env:ANTHROPIC_BASE_URL ?? '<unset>')"
  Write-Host "  ANTHROPIC_API_KEY: $(Format-AiSecretPreview $env:ANTHROPIC_API_KEY)"
  Write-Host "  ANTHROPIC_AUTH_TOKEN: $(Format-AiSecretPreview $env:ANTHROPIC_AUTH_TOKEN)"
  $cprofile = Get-AiProfileByName -Tool "claude" -Name ($env:AI_CLAUDE_LABEL ?? $saved)
  if (-not $cprofile) { $cprofile = Get-AiProfileByName -Tool "claude" -Name (Get-AiDefaultProfileName -Tool "claude") }
  if ($cprofile) {
    $h = Get-AiProfileHealthCached -Tool "claude" -Profile $cprofile -Fresh:$Fresh -CacheOnly:(-not $Fresh)
    Write-Host ("  Health: " + (Format-AiHealthCell $h) + $(if ($h.Error) { "  " + $h.Error } else { '' }))
  }
  Write-ClaudeExternalStatus
}

# ===========================================================================
# MCP module. ~/.ai-env/mcp.toml is the single source of truth for MCP servers
# across Claude Code and Codex. `mcp sync` pushes each enabled server to its
# targets (global):
#   Claude -> ~/.claude.json mcpServers      (direct JSON merge, atomic)
#   Codex  -> ~/.codex/config.toml [mcp_servers.NAME]  (native enabled flag)
# `enabled` is uniform: Claude has no per-server flag (disabled = omitted);
# Codex uses native enabled = false. Edit ONLY mcp.toml (mcp edit).
# Target paths honor env overrides (AI_CLAUDE_JSON_PATH / AI_CODEX_CONFIG_PATH)
# so tests can isolate without touching the real config files.
# ===========================================================================

function Get-AiMcpRegistryPath {
  return (Join-Path $script:AiConfigDir "mcp.toml")
}
function Get-AiClaudeJsonPath {
  if ($env:AI_CLAUDE_JSON_PATH) { return $env:AI_CLAUDE_JSON_PATH }
  return (Join-Path $HOME '.claude.json')
}
function Get-AiCodexConfigPath {
  if ($env:AI_CODEX_CONFIG_PATH) { return $env:AI_CODEX_CONFIG_PATH }
  return (Join-Path $HOME '.codex\config.toml')
}

# TOML array of strings: ["a", "b"] -> @('a','b')
function ConvertFrom-AiTomlStringArray {
  param([AllowNull()][string]$Raw)
  $list = @()
  if (-not $Raw) { return $list }
  foreach ($m in [regex]::Matches($Raw, '"((?:\\.|[^"])*)"')) { $list += $m.Groups[1].Value }
  return $list
}
# TOML inline table of strings: { K = "V" } -> @{K='V'}
function ConvertFrom-AiTomlInlineTable {
  param([AllowNull()][string]$Raw)
  $h = @{}
  if (-not $Raw) { return $h }
  foreach ($m in [regex]::Matches($Raw, '([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"((?:\\.|[^"])*)"')) { $h[$m.Groups[1].Value] = $m.Groups[2].Value }
  return $h
}

# Read mcp.toml -> ordered hashtable name -> entry(pscustomobject).
function Read-AiMcpRegistry {
  $path = Get-AiMcpRegistryPath
  $result = [ordered]@{}
  if (-not (Test-Path -LiteralPath $path)) { return $result }
  $current = $null
  foreach ($line in Get-Content -LiteralPath $path) {
    $t = "$line".Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    if ($t -match '^\[mcp\.([^\]]+)\]\s*$') {
      $current = $Matches[1].Trim()
      $result[$current] = [pscustomobject]@{
        Name = $current; Kind = 'stdio'; Command = @(); Url = $null; Env = @{}; Sync = @('claude', 'codex'); Enabled = $true
      }
      continue
    }
    if ($t -match '^\[') { $current = $null; continue }
    if (-not $current) { continue }
    if ($t -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$') {
      $key = $Matches[1]; $raw = $Matches[2].Trim()
      $e = $result[$current]
      switch ($key) {
        'command' { $e.Kind = 'stdio'; $e.Command = @(ConvertFrom-AiTomlStringArray $raw) }
        'url'     { $e.Kind = 'http'; $e.Url = [string](ConvertFrom-AiTomlValue $raw) }
        'env'     { $e.Env = ConvertFrom-AiTomlInlineTable $raw }
        'sync'    { $e.Sync = @(ConvertFrom-AiTomlStringArray $raw) }
        'enabled' { $e.Enabled = ($raw -match 'true') }
      }
    }
  }
  return $result
}

# --- Claude target (~/.claude.json mcpServers) ---
function Read-ClaudeMcpServerNames {
  $path = Get-AiClaudeJsonPath
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  try {
    $d = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ($d.mcpServers) { return @($d.mcpServers.PSObject.Properties.Name) }
  } catch { }
  return @()
}
# Build the object Claude stores for a server.
function ConvertTo-ClaudeMcpEntry {
  param([Parameter(Mandatory = $true)]$Entry)
  if ($Entry.Kind -eq 'http') { return [pscustomobject]@{ type = 'http'; url = [string]$Entry.Url } }
  $cmd = @($Entry.Command)
  $obj = [ordered]@{}
  if ($cmd.Count -gt 0) { $obj['command'] = [string]$cmd[0] }
  $obj['args'] = if ($cmd.Count -gt 1) { @($cmd[1..($cmd.Count - 1)]) } else { @() }
  if ($Entry.Env.Count -gt 0) { $obj['env'] = ($Entry.Env) }
  return [pscustomobject]$obj
}
# Upsert ($Entry) or remove ($Entry=$null) a server in .claude.json mcpServers.
# Atomic (tmp+move); preserves all other keys. Backs up once per path.
function Set-ClaudeMcpServer {
  param([Parameter(Mandatory = $true)][string]$Name, $Entry)
  $path = Get-AiClaudeJsonPath
  $bak = "$path.aienv.bak"
  if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $bak)) {
    Copy-Item -LiteralPath $path -Destination $bak -Force
  }
  $d = $null
  if (Test-Path -LiteralPath $path) {
    try { $d = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json } catch { $d = $null }
  }
  if (-not $d) { $d = [pscustomobject]@{ } }
  # copy existing mcpServers into a mutable hashtable (preserves siblings),
  # then upsert/remove the one entry, and write it back.
  $ms = @{ }
  if ($d.PSObject.Properties.Name -contains 'mcpServers' -and $d.mcpServers) {
    foreach ($p in $d.mcpServers.PSObject.Properties) { $ms[$p.Name] = $p.Value }
  }
  if ($Entry) {
    $ms[$Name] = (ConvertTo-ClaudeMcpEntry $Entry)
  } elseif ($ms.ContainsKey($Name)) {
    $ms.Remove($Name)
  }
  $d | Add-Member -NotePropertyName mcpServers -NotePropertyValue $ms -Force
  $tmp = "$path.tmp"
  ($d | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $path -Force
}

# --- Codex target (~/.codex/config.toml [mcp_servers.NAME]) ---
function Test-CodexMcpServer {
  param([Parameter(Mandatory = $true)][string]$Name)
  $path = Get-AiCodexConfigPath
  if (-not (Test-Path -LiteralPath $path)) { return $false }
  return [bool](Select-String -LiteralPath $path -Pattern ('^\[mcp_servers\.' + [regex]::Escape($Name) + '\]') -Quiet)
}
function ConvertTo-CodexMcpBlock {
  param([Parameter(Mandatory = $true)]$Entry)
  $lines = @("[mcp_servers.$($Entry.Name)]")
  if ($Entry.Kind -eq 'http') {
    $lines += 'url = "' + [string]$Entry.Url + '"'
  } else {
    $arr = (@($Entry.Command) | ForEach-Object { '"' + [string]$_ + '"' }) -join ', '
    $lines += 'command = [' + $arr + ']'
    if ($Entry.Env.Count -gt 0) {
      $pairs = ($Entry.Env.GetEnumerator() | ForEach-Object { [string]$_.Key + ' = "' + [string]$_.Value + '"' }) -join ', '
      $lines += 'env = { ' + $pairs + ' }'
    }
  }
  $lines += 'enabled = ' + $(if ($Entry.Enabled) { 'true' } else { 'false' })
  return ($lines -join "`n")
}
# Remove [mcp_servers.NAME] section; if $Block, append it. Preserves all other
# config.toml content (model, providers, user-managed mcp_servers, etc.).
function Set-CodexMcpServer {
  param([Parameter(Mandatory = $true)][string]$Name, [AllowEmptyString()][string]$Block)
  $path = Get-AiCodexConfigPath
  if (-not (Test-Path -LiteralPath $path)) {
    if (-not $Block) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    "" | Set-Content -LiteralPath $path -Encoding UTF8
  }
  $lines = @(Get-Content -LiteralPath $path)
  $out = New-Object System.Collections.Generic.List[string]
  $header = "[mcp_servers.$Name]"
  $skip = $false
  foreach ($l in $lines) {
    if ("$l".Trim() -match '^\[([^\]]+)\]\s*$') { $skip = ("[" + $Matches[1].Trim() + "]") -ceq $header }
    if ($skip) { continue }
    $out.Add($l)
  }
  if ($Block) {
    if ($out.Count -gt 0 -and "$($out[$out.Count - 1])".Trim() -ne '') { $out.Add('') }
    $out.Add($Block.TrimEnd())
  }
  ($out -join "`n") | Set-Content -LiteralPath $path -Encoding UTF8
}

# Push every mcp.toml entry to its targets (idempotent).
function Sync-AiMcp {
  $reg = Read-AiMcpRegistry
  $path = Get-AiMcpRegistryPath
  if ($reg.Count -eq 0) {
    Write-Host "No MCP servers in $path. Run 'mcp edit' to define some."
    return
  }
  $upserts = 0; $removes = 0
  foreach ($entry in $reg.Values) {
    foreach ($tool in @('claude', 'codex')) {
      $want = ($entry.Enabled -and ($entry.Sync -contains $tool))
      if ($tool -eq 'claude') {
        if ($want) { Set-ClaudeMcpServer -Name $entry.Name -Entry $entry; $upserts++ }
        else { Set-ClaudeMcpServer -Name $entry.Name -Entry $null; $removes++ }
      } else {
        $block = if ($want) { ConvertTo-CodexMcpBlock -Entry $entry } else { '' }
        Set-CodexMcpServer -Name $entry.Name -Block $block
        if ($want) { $upserts++ } else { $removes++ }
      }
    }
  }
  Write-Host "MCP sync done: $upserts upsert(s), $removes remove(s). Targets: Claude ($(Get-AiClaudeJsonPath)), Codex ($(Get-AiCodexConfigPath))."
}

# --- reverse direction: pull existing servers from targets into mcp.toml ---
function Read-ClaudeMcpServers {
  $path = Get-AiClaudeJsonPath
  $result = [ordered]@{ }
  if (-not (Test-Path -LiteralPath $path)) { return $result }
  try {
    $d = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ($d.mcpServers) { foreach ($p in $d.mcpServers.PSObject.Properties) { $result[$p.Name] = $p.Value } }
  } catch { }
  return $result
}
function Read-CodexMcpServers {
  $path = Get-AiCodexConfigPath
  $result = [ordered]@{ }
  if (-not (Test-Path -LiteralPath $path)) { return $result }
  $current = $null
  foreach ($line in Get-Content -LiteralPath $path) {
    $t = "$line".Trim()
    if ($t -match '^\[mcp_servers\.([^\]]+)\]\s*$') {
      $current = $Matches[1].Trim()
      $result[$current] = [pscustomobject]@{ Name = $current; Command = @(); Url = $null; Env = @{}; Enabled = $true }
      continue
    }
    if ($t -match '^\[') { $current = $null; continue }
    if (-not $current) { continue }
    if ($t -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$') {
      $key = $Matches[1]; $raw = $Matches[2].Trim(); $e = $result[$current]
      switch ($key) {
        'command' { $e.Command = @(ConvertFrom-AiTomlStringArray $raw) }
        'url'     { $e.Url = [string](ConvertFrom-AiTomlValue $raw) }
        'env'     { $e.Env = ConvertFrom-AiTomlInlineTable $raw }
        'enabled' { $e.Enabled = ($raw -match 'true') }
      }
    }
  }
  return $result
}
# Convert a Claude target entry -> mcp.toml entry shape.
function ConvertFrom-ClaudeMcpTarget {
  param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)]$Entry)
  $e = [pscustomobject]@{ Name = $Name; Kind = 'stdio'; Command = @(); Url = $null; Env = @{}; Sync = @('claude'); Enabled = $true }
  if ("$Entry.type" -in @('http', 'sse') -or $Entry.url) {
    $e.Kind = 'http'; $e.Url = [string]$Entry.url
  } else {
    if ($Entry.command -is [array]) { $e.Command = @($Entry.command) }
    else {
      $cmd = @(); if ($Entry.command) { $cmd += [string]$Entry.command }
      if ($Entry.args) { $cmd += @($Entry.args) }
      $e.Command = $cmd
    }
    if ($Entry.env) { foreach ($p in $Entry.env.PSObject.Properties) { $e.Env[$p.Name] = [string]$p.Value } }
  }
  return $e
}
# Convert a Codex target entry -> mcp.toml entry shape.
function ConvertFrom-CodexMcpTarget {
  param([Parameter(Mandatory = $true)]$Entry)
  $e = [pscustomobject]@{ Name = $Entry.Name; Kind = 'stdio'; Command = @(); Url = $null; Env = @{}; Sync = @('codex'); Enabled = $Entry.Enabled }
  if ($Entry.Url) { $e.Kind = 'http'; $e.Url = $Entry.Url } else { $e.Command = @($Entry.Command); $e.Env = $Entry.Env }
  return $e
}
# Serialize an mcp.toml entry -> TOML block text.
function ConvertTo-McpTomlBlock {
  param([Parameter(Mandatory = $true)]$Entry)
  $lines = @("[mcp.$($Entry.Name)]")
  if ($Entry.Kind -eq 'http') {
    $lines += 'url = "' + [string]$Entry.Url + '"'
  } else {
    $arr = (@($Entry.Command) | ForEach-Object { '"' + [string]$_ + '"' }) -join ', '
    $lines += 'command = [' + $arr + ']'
    if ($Entry.Env.Count -gt 0) {
      $pairs = ($Entry.Env.GetEnumerator() | ForEach-Object { [string]$_.Key + ' = "' + [string]$_.Value + '"' }) -join ', '
      $lines += 'env = { ' + $pairs + ' }'
    }
  }
  $lines += 'sync = [' + ((@($Entry.Sync) | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']'
  $lines += 'enabled = ' + $(if ($Entry.Enabled) { 'true' } else { 'false' })
  return ($lines -join "`n")
}
# Pull existing MCP servers from Claude + Codex targets into mcp.toml. Adds only
# names not already present (preserves your mcp.toml edits). -Name pulls one.
function Import-AiMcpFromTargets {
  param([string]$Name)
  $claude = Read-ClaudeMcpServers
  $codex = Read-CodexMcpServers
  $existing = Read-AiMcpRegistry
  if ($Name) {
    $names = @($Name)
    if (-not ($claude.Contains($Name) -or $codex.Contains($Name))) { Write-Host "'$Name' not found in Claude or Codex targets."; return }
  } else {
    $names = @(@($claude.Keys) + @($codex.Keys) | Select-Object -Unique)
  }
  if ($names.Count -eq 0) { Write-Host "No MCP servers found in targets to pull."; return }
  $added = 0; $skipped = 0; $newBlocks = @()
  foreach ($n in $names) {
    if ($existing.Contains($n)) { $skipped++; continue }
    $inC = $claude.Contains($n); $inX = $codex.Contains($n)
    if ($inC) { $e = ConvertFrom-ClaudeMcpTarget -Name $n -Entry $claude[$n] } else { $e = ConvertFrom-CodexMcpTarget -Entry $codex[$n] }
    $sync = @(); if ($inC) { $sync += 'claude' }; if ($inX) { $sync += 'codex' }
    $e.Sync = $sync
    $newBlocks += (ConvertTo-McpTomlBlock -Entry $e)
    $added++
  }
  if ($added -gt 0) {
    $path = Get-AiMcpRegistryPath
    if (-not (Test-Path -LiteralPath $path)) {
      New-Item -ItemType Directory -Force -Path $script:AiConfigDir | Out-Null
      "# ~/.ai-env/mcp.toml - pulled from Claude Code & Codex. Edit freely; run mcp sync to push back." | Set-Content -LiteralPath $path
    }
    $tail = (Get-Content -Raw -LiteralPath $path).TrimEnd()
    $sep = if ($tail -ne '') { "`n`n" } else { "" }
    Add-Content -LiteralPath $path -Value ($sep + ($newBlocks -join "`n`n") + "`n")
  }
  Write-Host "MCP pull: +$added added, $skipped skipped (already in mcp.toml). -> $(Get-AiMcpRegistryPath)"
}

function Show-AiMcpList {
  $reg = Read-AiMcpRegistry
  $path = Get-AiMcpRegistryPath
  if ($reg.Count -eq 0) { Write-Host "No MCP servers in $path. Run 'mcp edit'."; return }
  $claude = Read-ClaudeMcpServerNames
  $rows = foreach ($e in $reg.Values) {
    [pscustomobject]@{
      Name    = $e.Name
      Type    = if ($e.Kind -eq 'http') { 'http' } else { 'stdio' }
      Claude  = if ($claude -contains $e.Name) { 'yes' } else { '-' }
      Codex   = if (Test-CodexMcpServer -Name $e.Name) { 'yes' } else { '-' }
      Enabled = if ($e.Enabled) { 'on' } else { 'off' }
      Sync    = ($e.Sync -join ',')
    }
  }
  $rows | Format-Table -AutoSize
  Write-Host "  (yes = present in target's live config; run 'mcp sync' to align)" -ForegroundColor DarkGray
}

function Show-AiMcpGet {
  param([string]$Name)
  $reg = Read-AiMcpRegistry
  if (-not $Name) { Write-Host "Usage: mcp get NAME"; return }
  if (-not $reg.Contains($Name)) { Write-Host "No MCP server '$Name' in mcp.toml."; return }
  $e = $reg[$Name]
  Write-Host "mcp.$Name :"
  Write-Host "  kind    : $($e.Kind)"
  if ($e.Kind -eq 'http') { Write-Host "  url     : $($e.Url)" } else { Write-Host "  command : $($e.Command -join ' ')" }
  if ($e.Env.Count -gt 0) { Write-Host "  env     : " + (($e.Env.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ') }
  Write-Host "  sync    : $($e.Sync -join ', ')"
  Write-Host "  enabled : $($e.Enabled)"
  $claude = Read-ClaudeMcpServerNames
  Write-Host "  claude  : $(if ($claude -contains $Name) { 'present' } else { '-' })"
  Write-Host "  codex   : $(if (Test-CodexMcpServer -Name $Name) { 'present' } else { '-' })"
}

function Edit-AiMcpRegistry {
  $path = Get-AiMcpRegistryPath
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Force -Path $script:AiConfigDir | Out-Null
    @'
# ~/.ai-env/mcp.toml — single source of truth for MCP servers (Claude Code + Codex).
# `mcp sync` pushes each enabled server to global targets:
#   Claude -> ~/.claude.json mcpServers
#   Codex  -> ~/.codex/config.toml [mcp_servers.NAME]
# A server is EITHER stdio (command = [...]) OR http (url = "...").
# sync  = which tools get it (omit = both). enabled = false keeps it defined but skips it.

# [mcp.context7]
# command = ["npx", "-y", "@upstash/context7-mcp"]
# env = {}
# sync = ["claude", "codex"]
# enabled = true

# [mcp.figma]
# url = "https://mcp.figma.com/mcp"
# sync = ["codex"]
# enabled = false
'@ | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host "Created starter mcp.toml at $path"
  }
  $editor = if ($env:EDITOR) { $env:EDITOR } elseif ($env:VISUAL) { $env:VISUAL } elseif ($IsWindows) { 'notepad' } else { 'vi' }
  # mcp edit should open-and-return (non-blocking): drop any --wait/-w flag so
  # GUI editors (cursor/code) launch and hand the shell back immediately. The
  # global $EDITOR keeps --wait for tools that need blocking (e.g. git commit).
  $parts = @($editor -split '\s+' | Where-Object { $_ -and $_ -notin @('--wait', '-w') })
  if ($parts.Count -eq 0) { $parts = @('notepad') }
  $rest = @(); if ($parts.Count -gt 1) { $rest = @($parts[1..($parts.Count - 1)]) }; $rest += $path
  Write-Host "Opening $path with $($parts[0]) ..."
  & $parts[0] @rest
}

# `cc edit` / `cx edit` — jump straight to the profile registry (profiles.json),
# where base_url, model, probe_model, probe_ua, mode etc. live for every profile.
# Non-blocking: strips --wait so GUI editors (cursor/code) open and return.
function Edit-AiRegistry {
  $path = $script:AiRegistryPath
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Host "Registry not found: $path"
    return
  }
  $editor = if ($env:EDITOR) { $env:EDITOR } elseif ($env:VISUAL) { $env:VISUAL } elseif ($IsWindows) { 'notepad' } else { 'vi' }
  $parts = @($editor -split '\s+' | Where-Object { $_ -and $_ -notin @('--wait', '-w') })
  if ($parts.Count -eq 0) { $parts = @('notepad') }
  $rest = @(); if ($parts.Count -gt 1) { $rest = @($parts[1..($parts.Count - 1)]) }; $rest += $path
  Write-Host "Opening $path with $($parts[0]) ..."
  & $parts[0] @rest
}

function Show-AiMcpHelp {
  @'
mcp - manage MCP servers across Claude Code & Codex from ~/.ai-env/mcp.toml

Usage:
  mcp                 Show this help
  mcp list            List servers + whether each target has them
  mcp edit            Open mcp.toml in EDITOR (creates a starter if absent)
  mcp sync            Push mcp.toml -> Claude (~/.claude.json) & Codex (~/.codex/config.toml)
  mcp pull [NAME]     Import existing MCP servers FROM Claude & Codex into mcp.toml
  mcp get NAME        Show one server's config + target status

mcp.toml is the single source of truth; edit it, then `mcp sync` (idempotent).
enabled = false keeps a server defined but skips it on sync.
sync = ["claude"] or ["codex"] limits a server to one tool (omit = both).
'@ | Write-Host
}

function mcp {
  $remaining = @($args)
  if ($remaining.Count -eq 0 -or ($remaining[0] -in @('help', '-h', '--help'))) { Show-AiMcpHelp; return }
  switch (($remaining[0]).ToString().ToLowerInvariant()) {
    'list' { Show-AiMcpList; return }
    'edit' { Edit-AiMcpRegistry; return }
    'sync' { Sync-AiMcp; return }
    { $_ -in @('pull', 'import') } { Import-AiMcpFromTargets -Name ($remaining[1]); return }
    { $_ -in @('get', 'show') } { Show-AiMcpGet -Name ($remaining[1]); return }
    default { Write-Host "Unknown mcp command '$($remaining[0])'."; Show-AiMcpHelp; return }
  }
}

function cx {
  $remaining = @($args)

  if ($remaining.Count -gt 0) {
    switch (($remaining[0] ?? "").ToString().ToLowerInvariant()) {
      { $_ -in @("help", "-h", "--help", "/?") } { Show-CxHelp; return }
      "list" { Show-CodexList; return }
      "status" { Show-CodexStatus -Fresh:(Test-AiFreshFlag ($remaining | Select-Object -Skip 1)); return }
      "doctor" { Show-CodexDoctor; return }
      "edit" { Edit-AiRegistry; return }
      "health" { Show-AiHealth -Tool "codex" -Fresh:(Test-AiFreshFlag ($remaining | Select-Object -Skip 1)); return }
      "stats" { Show-CodexStats -Arguments @($remaining | Select-Object -Skip 1); return }
      "add-api" { Add-CodexApiProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "add-sub" { Add-CodexSubProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "remove" { Remove-CodexProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "probe-model" { Set-AiProfileProbeModel -Tool "codex" -Arguments @($remaining | Select-Object -Skip 1); return }
      "default" { Set-AiDefaultProfile -Tool "codex" -Arguments @($remaining | Select-Object -Skip 1); return }
      "health-clear" { Clear-AiHealthCache; Write-Host "health cache cleared"; return }
      "next" { $remaining = @((Get-AiNextProfileName -Tool "codex")) }
    }
  }

  if ($remaining.Count -gt 0) {
    $profile = Get-AiProfileByName -Tool "codex" -Name ([string]$remaining[0])
    if (-not $profile) {
      throw "Unknown cx profile '$($remaining[0])'. Add it to $script:AiRegistryPath or run 'cx help'."
    }
    $remaining = @($remaining | Select-Object -Skip 1)
  } else {
    $autoName = Get-AiHealthyProfileName -Tool "codex"
    $profile = Get-AiProfileByName -Tool "codex" -Name $autoName
    if ($profile) {
      $ah = Get-AiProfileHealthCached -Tool "codex" -Profile $profile
      Write-Host ("auto-select: $autoName " + (Format-AiHealthCell $ah)) -ForegroundColor DarkGray
    }
  }

  if ($remaining.Count -gt 0) {
    throw "cx only switches state and does not forward arguments. Run 'codex $($remaining -join ' ')' separately after switching."
  }

  Save-AiSelectedProfile -Tool "codex" -Name (Get-AiProfileName -Profile $profile)
  $secretSource = Set-CodexProfileEnvironment -Profile $profile
  Write-CodexSwitchStatus -Profile $profile -SecretSource $secretSource
}

function cc {
  $remaining = @($args)

  if ($remaining.Count -gt 0) {
    switch (($remaining[0] ?? "").ToString().ToLowerInvariant()) {
      { $_ -in @("help", "-h", "--help", "/?") } { Show-CcHelp; return }
      "list" { Show-ClaudeList; return }
      "status" { Show-ClaudeStatus -Fresh:(Test-AiFreshFlag ($remaining | Select-Object -Skip 1)); return }
      "edit" { Edit-AiRegistry; return }
      "health" { Show-AiHealth -Tool "claude" -Fresh:(Test-AiFreshFlag ($remaining | Select-Object -Skip 1)); return }
      "add-api" { Add-ClaudeApiProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "add-sub" { Add-ClaudeSubProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "remove" { Remove-ClaudeProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "probe-model" { Set-AiProfileProbeModel -Tool "claude" -Arguments @($remaining | Select-Object -Skip 1); return }
      "default" { Set-AiDefaultProfile -Tool "claude" -Arguments @($remaining | Select-Object -Skip 1); return }
      "health-clear" { Clear-AiHealthCache; Write-Host "health cache cleared"; return }
      "next" { $remaining = @((Get-AiNextProfileName -Tool "claude")) }
    }
  }

  if ($remaining.Count -gt 0) {
    $profile = Get-AiProfileByName -Tool "claude" -Name ([string]$remaining[0])
    if (-not $profile) {
      throw "Unknown cc profile '$($remaining[0])'. Add it to $script:AiRegistryPath or run 'cc help'."
    }
    $remaining = @($remaining | Select-Object -Skip 1)
  } else {
    $autoName = Get-AiHealthyProfileName -Tool "claude"
    $profile = Get-AiProfileByName -Tool "claude" -Name $autoName
    if ($profile) {
      $ah = Get-AiProfileHealthCached -Tool "claude" -Profile $profile
      Write-Host ("auto-select: $autoName " + (Format-AiHealthCell $ah)) -ForegroundColor DarkGray
    }
  }

  if ($remaining.Count -gt 0) {
    throw "cc only switches state and does not forward arguments. Run 'claude $($remaining -join ' ')' separately after switching."
  }

  Save-AiSelectedProfile -Tool "claude" -Name (Get-AiProfileName -Profile $profile)
  $secretSource = Set-ClaudeProfileEnvironment -Profile $profile
  Write-ClaudeSwitchStatus -Profile $profile -SecretSource $secretSource
}

function Test-CodexArgsHaveExplicitProfile {
  param([string[]]$Arguments)

  foreach ($arg in $Arguments) {
    if ($arg -eq "--profile" -or $arg -eq "-p" -or $arg -like "--profile=*") {
      return $true
    }
  }

  return $false
}

function Get-CodexFirstToken {
  param([string[]]$Arguments)

  $optionsWithValue = @(
    "-c", "--config", "-i", "--image", "-m", "--model", "-p", "--profile",
    "-s", "--sandbox", "-C", "--cd", "--add-dir", "-a", "--ask-for-approval",
    "--remote", "--remote-auth-token-env", "--local-provider"
  )

  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = $Arguments[$i]
    if ($arg -eq "--") {
      return $null
    }
    if ($optionsWithValue -contains $arg) {
      $i++
      continue
    }
    if ($arg.StartsWith("-")) {
      continue
    }
    return $arg
  }

  return $null
}

function Test-CodexShouldInjectProfile {
  param([string[]]$Arguments)

  if (Test-CodexArgsHaveExplicitProfile -Arguments $Arguments) {
    return $false
  }

  $first = Get-CodexFirstToken -Arguments $Arguments
  if (-not $first) {
    return $true
  }

  $knownNoProfile = @(
    "login", "logout", "doctor", "app", "completion", "update", "features", "help",
    "cloud", "app-server", "remote-control", "mcp-server", "exec-server", "mcp",
    "plugin", "sandbox", "debug", "apply", "archive", "unarchive"
  )
  if ($knownNoProfile -contains $first) {
    return $false
  }

  return $true
}

function codex {
  $arguments = @($args)
  $codexCommand = Get-CodexExternalCommand
  $saved = Get-AiSavedProfileName -Tool "codex"
  $profile = Get-AiProfileByName -Tool "codex" -Name ($env:AI_CODEX_LABEL ?? $saved)
  if (-not $profile) {
    $profile = Get-AiProfileByName -Tool "codex" -Name (Get-AiDefaultProfileName -Tool "codex")
  }

  Set-CodexProfileEnvironment -Profile $profile | Out-Null

  $profilePath = Get-CodexProfilePath -Profile $profile
  if ((Test-Path -LiteralPath $profilePath) -and (Test-CodexShouldInjectProfile -Arguments $arguments)) {
    $arguments = @("--profile", (Get-CodexRuntimeProfileName -Profile $profile)) + $arguments
  }

  & $codexCommand @arguments
}

function Initialize-AiEnvProfiles {
  $codexSaved = Get-AiSavedProfileName -Tool "codex"
  $codexProfile = Get-AiProfileByName -Tool "codex" -Name $codexSaved
  if ($codexProfile) {
    try {
      Set-CodexProfileEnvironment -Profile $codexProfile | Out-Null
    } catch {
      Write-Warning "Could not initialize saved Codex profile '$codexSaved'. $($_.Exception.Message)"
    }
  }

  $claudeSaved = Get-AiSavedProfileName -Tool "claude"
  $claudeProfile = Get-AiProfileByName -Tool "claude" -Name $claudeSaved
  if ($claudeProfile) {
    try {
      Set-ClaudeProfileEnvironment -Profile $claudeProfile | Out-Null
    } catch {
      Write-Warning "Could not initialize saved Claude Code profile '$claudeSaved'. $($_.Exception.Message)"
    }
  }
}

Initialize-AiEnvProfiles
