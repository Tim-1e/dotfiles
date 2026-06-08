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
