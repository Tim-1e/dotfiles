# Codex App provider switch design

## Goal

Let the existing `cx` registry select a Codex App model provider without changing `CODEX_HOME`, copying API keys, or replacing ChatGPT login state.

## Interface

- `cx app-default` shows the App profile selection.
- `cx app-default NAME` validates an existing Codex profile, writes `defaults.codex_app`, and projects the profile into the shared App `config.toml`.
- Subscription profiles select the built-in `openai` provider.
- API profiles select a distinct managed provider ID, `ai-env-app`.

## Configuration mapping

Codex App has no native equivalent of the CLI `--profile` selector. The switch therefore updates only App-consumed settings in the base `config.toml`:

- top-level `model_provider`;
- optional model and reasoning settings already present in the selected profile file;
- `[model_providers.ai-env-app]` and `[model_providers.ai-env-app.auth]`.

The managed provider copies the selected profile's display name, base URL, and Responses wire API. It deliberately omits `env_key` and `requires_openai_auth`. Command-backed auth uses a fixed helper deployed directly to protected `~/.codex/app-auth` and reads the selected `secret_id` and key from the existing `~/.ai-secrets/secrets.toml` at request time.

## State and safety

- `defaults.codex` remains the CLI default; `defaults.codex_app` is independent.
- `auth.json`, sessions, projects, plugins, SQLite state, and Remote identifiers are not modified.
- Unrelated TOML sections are preserved, and repeated switching is idempotent.
- The API key is never written to `config.toml`, the registry, command arguments, or output.
- Live activation requires protected registry, secret-store, profile-config, App-config, and helper paths. The current broad sandbox ACLs on `~/.ai-env` and `~/.ai-secrets` must be repaired and verified before enabling command-backed auth.

## Reload behavior

The change is durable immediately. A running App may retain its current effective configuration, so closing and reopening Codex App is the supported reload boundary.

Because the switch changes the shared base `config.toml`, any other unprofiled app-server consumer using the same `CODEX_HOME` (for example an IDE integration) will also see the selected provider after it reloads.
