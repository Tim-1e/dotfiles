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
- `cx api` -> `~/.codex/api.config.toml` + `~/.ai-secrets/codex-api.*`
- `cx api:docker` -> `~/.codex/api-docker.config.toml` + `~/.ai-secrets/codex-api-docker.*`
- `cc sub` -> clears Anthropic API environment and uses local Claude subscription login
- `cc api` -> `~/.ai-secrets/claude-api.*`
- `cc api:docker` -> `~/.ai-secrets/claude-api-docker.*`

Multiple Codex API profiles can share the same `home` value, usually
`~/.codex`, so sessions/history stay together. Multiple Codex subscription
accounts need different `home` values because `codex login` auth is cached under
`CODEX_HOME/auth.json`.
