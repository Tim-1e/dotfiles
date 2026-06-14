# Secret Examples

Copy the relevant example into your local secret directory after applying the
dotfiles. Do not commit real secrets.

Profiles are registered in:

```text
~/.ai-env/profiles.json
```

The dotfiles source creates this file only if it is missing. Existing machines
keep their local registry, so merge new profile entries manually when needed.
That file is safe to sync because it only contains profile names, config paths,
base URLs, and secret file paths. Real tokens stay in:

```text
~/.ai-secrets/
```

## Preferred secret file

Use one TOML file for both Windows PowerShell and Linux/zsh:

```text
~/.ai-secrets/secrets.toml
```

Start from:

```text
secret_examples/ai-secrets.toml.example
```

The section name comes from `secret_id` in `~/.ai-env/profiles.json`.

```toml
[codex.api]
OPENAI_API_KEY = "sk-..."

[codex.api-myrouter]
OPENAI_API_KEY = "sk-..."

[claude.api]
ANTHROPIC_BASE_URL = "https://anyrouter.top"
ANTHROPIC_API_KEY = "sk-ant-..."
```

After editing, check readiness with:

```sh
cx list
cc list
```

On Windows:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.ai-secrets"
Copy-Item .\secret_examples\ai-secrets.toml.example "$HOME\.ai-secrets\secrets.toml"
```

On Linux:

```sh
mkdir -p "$HOME/.ai-secrets"
cp secret_examples/ai-secrets.toml.example "$HOME/.ai-secrets/secrets.toml"
chmod 600 "$HOME/.ai-secrets/secrets.toml"
```

## Per-profile env vars (non-secret)

A profile entry in `~/.ai-env/profiles.json` may carry an optional `env` object for
**non-secret** variables that should travel with the profile — e.g. GLM model mapping and
the auto-compact window:

```json
{
  "name": "glm",
  "mode": "api",
  "base_url": "https://open.bigmodel.cn/api/anthropic",
  "secret_id": "claude.glm",
  "env": {
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-4.5-air",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5.2[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2[1m]",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"
  }
}
```

These are exported when you switch to the profile (`cc glm` / `cx glm`) and cleared when you
switch to another profile, so values never leak between routers. Author them with the
repeatable `--env KEY=VALUE` flag:

```sh
cc add-api glm --base-url https://open.bigmodel.cn/api/anthropic \
  --env ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.2[1m] \
  --env CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
```

Because this is the registry (not `secrets.toml`), it is safe to sync. Keep real tokens out of it.

## Interactive add and secret scaffolding

In a terminal, `cc add-api` / `cx add-api` (and `cx add-sub`) prompt for any missing
`--base-url`, `--env-key`, and `--provider-name`, then prompt for the API key/token (hidden)
and write the missing `[tool.name]` section into `~/.ai-secrets/secrets.toml`. In a
non-interactive shell (CI, piped stdin, or `AI_ENV_NONINTERACTIVE=1`) it skips all prompts and
uses defaults, so scripts and tests never block.

The generated Codex config (`~/.codex/<runtime>.config.toml`) uses a unified provider id:

```toml
model_provider = "api-router"
disable_response_storage = true

[model_providers.api-router]
name = "<provider-name>"
base_url = "<base-url>"
env_key = "OPENAI_API_KEY"
```

Only `name` and `base_url` change per profile; pass `--env-key` to use a different secret
variable, or `--model` to pin a model line.

## Legacy fallback files

The helper still accepts the old platform-specific secret files. Use these only
when you cannot use `secrets.toml`.

Windows:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.ai-secrets"
Copy-Item .\secret_examples\windows\codex-api.ps1.example "$HOME\.ai-secrets\codex-api.ps1"
Copy-Item .\secret_examples\windows\claude-api.ps1.example "$HOME\.ai-secrets\claude-api.ps1"
```

Named API profiles use the same convention:

```powershell
# 1. Register the profile in ~/.ai-env/profiles.json.
# 2. Add the Codex runtime profile file.
# Example: cx api:aixhan -> codex --profile api-aixhan
Copy-Item .\secret_examples\codex\api-name.config.toml.example "$HOME\.codex\api-aixhan.config.toml"
Copy-Item .\secret_examples\windows\codex-api-name.ps1.example "$HOME\.ai-secrets\codex-api-aixhan.ps1"

# Claude Code: cc api:anyrouter after registering it in ~/.ai-env/profiles.json
Copy-Item .\secret_examples\windows\claude-api-name.ps1.example "$HOME\.ai-secrets\claude-api-anyrouter.ps1"
```

Linux:

```sh
mkdir -p "$HOME/.ai-secrets"
cp secret_examples/linux/codex-api.env.example "$HOME/.ai-secrets/codex-api.env"
cp secret_examples/linux/claude-api.env.example "$HOME/.ai-secrets/claude-api.env"
chmod 600 "$HOME"/.ai-secrets/*
```

Named Linux profiles use:

```sh
# Register the profile in ~/.ai-env/profiles.json first.
cp secret_examples/codex/api-name.config.toml.example "$HOME/.codex/api-aixhan.config.toml"
cp secret_examples/linux/codex-api-name.env.example "$HOME/.ai-secrets/codex-api-aixhan.env"
cp secret_examples/linux/claude-api-name.env.example "$HOME/.ai-secrets/claude-api-anyrouter.env"
```

Current default registry:

- `cx sub` -> `~/.codex/sub.config.toml`, ChatGPT subscription login from `codex login`
- `cx api` -> `~/.codex/api.config.toml` + `[codex.api]`
- `cc sub` -> clears Anthropic API environment and uses local Claude subscription login
- `cc api` -> `[claude.api]`
- `cc api:docker` -> `[claude.api-docker]`

Multiple Codex API profiles can share the same `home` value, usually
`~/.codex`, so sessions/history stay together. Multiple Codex subscription
accounts need different `home` values because `codex login` auth is cached under
`CODEX_HOME/auth.json`.
