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

function Get-CodexDoctorArgs {
  param([Parameter(Mandatory = $true)]$Profile)

  $args = @("doctor", "--json")
  $profilePath = Get-CodexProfilePath -Profile $Profile
  $model = Get-TomlStringValue -Path $profilePath -Key "model"
  $provider = Get-TomlStringValue -Path $profilePath -Key "model_provider"

  if ($model) {
    $args += @("-c", "model=`"$model`"")
  }
  if ($provider) {
    $args += @("-c", "model_provider=`"$provider`"")
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

      $args += @("-c", "model_providers.$provider.name=`"$providerName`"")
      if ($baseUrl) {
        $args += @("-c", "model_providers.$provider.base_url=`"$baseUrl`"")
      }
      if ($wireApi) {
        $args += @("-c", "model_providers.$provider.wire_api=`"$wireApi`"")
      }
      if ($envKey) {
        $args += @("-c", "model_providers.$provider.env_key=`"$envKey`"")
      }
      if ($requiresOpenAiAuth) {
        $args += @("-c", "model_providers.$provider.requires_openai_auth=$requiresOpenAiAuth")
      }
    }
  }

  return $args
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

  return $secretSource
}

function New-CodexProfileConfig {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [AllowNull()][string]$BaseUrl,
    [AllowNull()][string]$Model
  )

  $mode = Get-AiProfileMode -Profile $Profile
  $profilePath = Get-CodexProfilePath -Profile $Profile
  if (Test-Path -LiteralPath $profilePath) {
    return $profilePath
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
  $runtimeProfile = Get-CodexRuntimeProfileName -Profile $Profile
  $providerName = $runtimeProfile
  $displayName = (Get-AiProfileName -Profile $Profile).Replace(":", " ")
  $modelValue = if ($Model) { $Model } else { "gpt-5.5" }

  if ($mode -eq "api") {
    $url = if ($BaseUrl) { $BaseUrl } else { "https://your-router.example/v1" }
    @"
model_provider = "$providerName"
model = "$modelValue"
disable_response_storage = true

[model_providers.$providerName]
name = "$displayName"
base_url = "$url"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
"@ | Set-Content -LiteralPath $profilePath -Encoding UTF8
  } else {
    @"
model_provider = "openai"
model = "$modelValue"
"@ | Set-Content -LiteralPath $profilePath -Encoding UTF8
  }

  return $profilePath
}

function Add-CodexApiProfile {
  param([string[]]$Arguments)

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cx add-api <name> [--base-url URL] [--model MODEL] [--home PATH]"
  }

  $name = [string]$parsed.Positionals[0]
  Assert-AiProfileName -Name $name
  $slug = Get-AiNameSlug -Name $name
  $profileHome = Get-AiOption -Options $parsed.Options -Name "home" -Default "~/.codex"
  $runtimeProfile = Get-AiOption -Options $parsed.Options -Name "profile" -Default "api-$($slug.Replace(':', '-'))"
  $secretId = Get-AiOption -Options $parsed.Options -Name "secret-id" -Default "codex.$name"
  $baseUrl = Get-AiOption -Options $parsed.Options -Name "base-url" -Default "https://your-router.example/v1"
  $model = Get-AiOption -Options $parsed.Options -Name "model" -Default "gpt-5.5"

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
  Add-AiProfileRegistration -Tool "codex" -Profile $profile | Out-Null
  $profilePath = New-CodexProfileConfig -Profile $profile -BaseUrl $baseUrl -Model $model
  Write-Host "Added Codex API profile '$name'."
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  CODEX_HOME: $(Expand-AiPath $profileHome)"
  Write-Host "  Config: $profilePath"
  Write-Host "  Secret: $script:AiSecretsPath [$secretId] with OPENAI_API_KEY"
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
  $profileHome = Get-AiOption -Options $parsed.Options -Name "home" -Default "~/.codex-$slug"
  $runtimeProfile = Get-AiOption -Options $parsed.Options -Name "profile" -Default "sub"
  $model = Get-AiOption -Options $parsed.Options -Name "model" -Default "gpt-5.5"

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

  $parsed = ConvertFrom-AiManagementArgs -Arguments $Arguments
  if ($parsed.Positionals.Count -lt 1) {
    throw "Usage: cc add-api <name> [--base-url URL]"
  }

  $name = [string]$parsed.Positionals[0]
  Assert-AiProfileName -Name $name
  $slug = Get-AiNameSlug -Name $name
  $secretId = Get-AiOption -Options $parsed.Options -Name "secret-id" -Default "claude.$name"
  $baseUrl = Get-AiOption -Options $parsed.Options -Name "base-url" -Default $script:ClaudeRouterBaseUrl

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
  Add-AiProfileRegistration -Tool "claude" -Profile $profile | Out-Null
  Write-Host "Added Claude Code API profile '$name'."
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  Base URL: $baseUrl"
  Write-Host "  Secret: $script:AiSecretsPath [$secretId] with ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN"
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

  Write-CodexDoctorSummary -Profile $Profile
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
  cx status          Print current saved/process state
  cx add-api NAME    Register a Codex API profile that shares ~/.codex by default
  cx add-sub NAME    Register an isolated Codex subscription CODEX_HOME
  cx remove NAME     Remove a Codex profile registration
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
  cc status          Print current saved/process state
  cc add-api NAME    Register a Claude Code API profile
  cc add-sub NAME    Register a Claude Code subscription label
  cc remove NAME     Remove a Claude Code profile registration
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
  Add commands only write profile metadata. Put real tokens in secrets.toml.
  Legacy ~/.ai-secrets/*.ps1 files are still accepted as a fallback.
"@ | Write-Host
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
      Profile = Get-CodexRuntimeProfileName -Profile $profile
      Ready = $ready
      Home = $profileHome
      Config = if (Test-Path -LiteralPath $profilePath) { $profilePath } else { "<missing> $profilePath" }
      Secret = if ($mode -eq "api") { Get-AiSecretDisplay -Tool "codex" -Profile $profile -Names @("OPENAI_API_KEY", "CODEX_API_KEY") } else { "<none>" }
      BaseUrl = Get-CodexBaseUrl -Profile $profile
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
      Ready = if ($secretOk) { "ok" } else { "missing secret" }
      Secret = if ($mode -eq "api") { Get-AiSecretDisplay -Tool "claude" -Profile $profile -Names @("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN") } else { "<none>" }
      BaseUrl = $baseUrl
    }
  }
}

function Show-CodexList {
  Write-Host "Codex profiles ($script:AiRegistryPath):"
  Get-CodexProfileRows | Format-Table Sel, Name, Mode, Ready, Profile, Home, Config, Secret, BaseUrl -AutoSize
}

function Show-ClaudeList {
  Write-Host "Claude Code profiles ($script:AiRegistryPath):"
  Get-ClaudeProfileRows | Format-Table Sel, Name, Mode, Ready, Secret, BaseUrl -AutoSize
}

function Show-CodexStatus {
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
    Write-CodexDoctorSummary -Profile $profile
  }
}

function Show-ClaudeStatus {
  $saved = Get-AiSavedProfileName -Tool "claude"
  Write-Host "Claude Code state:"
  Write-Host "  Registry: $script:AiRegistryPath"
  Write-Host "  State: $script:AiStatePath"
  Write-Host "  Saved: $saved"
  Write-Host "  Process label: $($env:AI_CLAUDE_LABEL ?? '<unset>')"
  Write-Host "  ANTHROPIC_BASE_URL: $($env:ANTHROPIC_BASE_URL ?? '<unset>')"
  Write-Host "  ANTHROPIC_API_KEY: $(Format-AiSecretPreview $env:ANTHROPIC_API_KEY)"
  Write-Host "  ANTHROPIC_AUTH_TOKEN: $(Format-AiSecretPreview $env:ANTHROPIC_AUTH_TOKEN)"
  Write-ClaudeExternalStatus
}

function cx {
  $remaining = @($args)

  if ($remaining.Count -gt 0) {
    switch (($remaining[0] ?? "").ToString().ToLowerInvariant()) {
      { $_ -in @("help", "-h", "--help", "/?") } { Show-CxHelp; return }
      "list" { Show-CodexList; return }
      "status" { Show-CodexStatus; return }
      "add-api" { Add-CodexApiProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "add-sub" { Add-CodexSubProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "remove" { Remove-CodexProfile -Arguments @($remaining | Select-Object -Skip 1); return }
    }
  }

  if ($remaining.Count -gt 0) {
    $profile = Get-AiProfileByName -Tool "codex" -Name ([string]$remaining[0])
    if (-not $profile) {
      throw "Unknown cx profile '$($remaining[0])'. Add it to $script:AiRegistryPath or run 'cx help'."
    }
    $remaining = @($remaining | Select-Object -Skip 1)
  } else {
    $profile = Get-AiProfileByName -Tool "codex" -Name (Get-AiNextProfileName -Tool "codex")
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
      "status" { Show-ClaudeStatus; return }
      "add-api" { Add-ClaudeApiProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "add-sub" { Add-ClaudeSubProfile -Arguments @($remaining | Select-Object -Skip 1); return }
      "remove" { Remove-ClaudeProfile -Arguments @($remaining | Select-Object -Skip 1); return }
    }
  }

  if ($remaining.Count -gt 0) {
    $profile = Get-AiProfileByName -Tool "claude" -Name ([string]$remaining[0])
    if (-not $profile) {
      throw "Unknown cc profile '$($remaining[0])'. Add it to $script:AiRegistryPath or run 'cc help'."
    }
    $remaining = @($remaining | Select-Object -Skip 1)
  } else {
    $profile = Get-AiProfileByName -Tool "claude" -Name (Get-AiNextProfileName -Tool "claude")
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
