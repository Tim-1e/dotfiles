# Dotfiles

[![CI](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml)

Language: [English](README.md) | [🇨🇳 中文](README.zh-CN.md) | [🇰🇷 한국어](README.ko.md) | [🇯🇵 日本語](README.ja.md)

Chezmoi-managed development environment for Linux, WSL, Termux, and Windows
PowerShell. The repo focuses on three layers:

- **Base environment**: shell, tmux, fonts, runtime installers, and safe
  cross-platform bootstrap behavior.
- **Modern CLI tools**: user-level installs of fast daily tools such as `rg`,
  `fd`, `jq`, `yq`, `delta`, `dust`, `duf`, `xh`, and `btop`.
- **AI workspace tools**: a pinned [cxcc](https://github.com/Tim-1e/cxcc)
  release provides `cx`, `cc`, and `mcp` for local Codex, Claude Code,
  API-router profiles, health checks, MCP sync, and secret-safe switching.

The dotfiles create missing defaults, but they avoid overwriting existing
machine-local settings. Secrets are never stored in this repository.

## What Gets Synchronized

| Area | What this repo manages | Main files |
|------|------------------------|------------|
| Base shell | zsh, Oh My Zsh plugins, tmux, fzf, zoxide, uv, rustup, locale guards | `dot_zshrc`, `dot_tmux.conf`, `scripts/install.sh` |
| Modern CLI | release-binary installs into `~/.local/bin`, best-effort and no root required | `scripts/install/modern-cli.sh` |
| Fonts | 0xProto Nerd Font for Linux, macOS, Windows, and WSL host installs | `0xProto/`, font run-on-change scripts |
| cxcc | Pinned cross-platform installer and stable shell loaders | `.chezmoidata.toml`, `scripts/install/cxcc.*`, `run_before_10-install-cxcc.*.tmpl` |
| Windows | PowerShell profile and compatibility hook that load cxcc | `Documents/PowerShell/create_Microsoft.PowerShell_profile.ps1`, `run_onchange_after_10-powershell-ai-env-hook.ps1.tmpl` |
| AI profiles | Codex/Claude profile registry, health cache, local state, default seed files | `dot_ai-env/`, `dot_codex/`, `dot_claude/` |
| MCP | Single local MCP registry, sync/pull helpers for Claude Code and Codex | `~/.ai-env/mcp.toml`, `mcp` helper |
| Secrets | Example templates only; real keys stay outside git | `secret_examples/`, `~/.ai-secrets/secrets.toml` |

## Quick Deploy

Fresh Linux or WSL:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

Local checkout:

```sh
git clone https://github.com/Tim-1e/dotfiles.git
cd dotfiles
bash ./bootstrap.sh
```

Windows PowerShell from a cloned checkout:

```powershell
.\bootstrap.ps1
```

Termux:

```sh
pkg update
pkg install -y bash termux-exec git chezmoi
chezmoi init --apply Tim-1e/dotfiles
```

`termux-exec` provides `/usr/bin/env` and other standard paths that chezmoi
scripts need during the first apply.

## Install Switches

```sh
INSTALL_CLAUDE=1 bash ./bootstrap.sh
INSTALL_NODE=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FASTFETCH=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_MODERN_CLI=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_CXCC=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FONTS=0 bash ./bootstrap.sh
INSTALL_WINDOWS_FONTS_FROM_WSL=0 bash ./bootstrap.sh
DOTFILES_USE_SUDO=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
DOTFILES_USE_SUDO=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

System packages are installed only when running as root or when sudo is
available. If sudo needs a password, the installer asks and defaults to no.
Without sudo, user-level tools still install where possible.

## Base Environment

The base layer installs or configures:

- zsh, tmux, git, curl, wget, nano, fzf, build tools, and locales where
  available
- Oh My Zsh with `zsh-autosuggestions` and `zsh-syntax-highlighting`
- zoxide, TPM, rustup, uv
- cargo tools: `eza`, `bat`, `lolcrab`
- latest compatible fastfetch in `~/.local/bin`
- Node.js and npm by default when system package installation is enabled
- 0xProto Nerd Fonts in the current user's font directory
- when selected, a pinned cxcc release plus PowerShell/Zsh loader hooks for
  `cx`, `cc`, and `mcp`

If `zsh` is unavailable but build tools are present, zsh is built into
`~/.local`. On older Linux systems, fastfetch falls back to its polyfilled
binary when available and otherwise skips without failing the entire apply.

## Modern CLI Tools

`scripts/install/modern-cli.sh` installs fast daily tools as user-level
prebuilt binaries in `~/.local/bin`. Each install is best-effort: failures print
a skip message and do not abort the full deploy.

| Tool | Use | Tool | Use |
|------|-----|------|-----|
| `rg` | fast recursive grep | `procs` | readable `ps` |
| `fd` | friendly `find` | `btop` | `top`/`htop` monitor |
| `jq` | JSON processor | `xh` | HTTP client |
| `yq` | YAML/TOML processor | `gping` | ping graph |
| `delta` | syntax-highlighted git diffs | `dust` | tree-style `du` |
| `sd` | simpler find/replace | `duf` | prettier `df` |
| `tldr` | example-based man pages | | |

Interactive aliases are conservative: `du` -> `dust`, `df` -> `duf`, `ps` ->
`procs`, `ping` -> `gping`, and `top`/`htop` -> `btop`. Tools with different
flags, such as `rg`, `fd`, `sd`, `jq`, `yq`, `xh`, and `delta`, are not aliased
over standard commands.

## CX/CC AI Profile Tools

The dotfiles can install a pinned cxcc release, then load its lightweight shell
functions for switching local Codex and Claude Code state without launching
either CLI. cxcc owns the command implementation and its cross-platform tests;
this repo owns the version pin, installation hook, loader wiring, and default
user configuration.

```sh
cx list
cx status
cx status --fresh
cx sub
cx api
cx next
cx stats
cx add-api api:work --base-url https://router.example/v1
cx add-sub sub:work
cx probe-model api:work gpt-example
cx edit

cc list
cc status
cc status --fresh
cc sub
cc api
cc next
cc add-api api:work --base-url https://router.example
cc add-sub sub:work
cc probe-model api:work claude-example
cc edit
```

Installed helper locations:

```text
PowerShell: ~/.local/share/cxcc/load.ps1
Bash/Zsh:  ~/.local/share/cxcc/load.sh
Payload:   ~/.local/share/cxcc/versions/v0.1.0/
```

The release tag, immutable commit, installer digest, and platform artifact
digests are stored together in `.chezmoidata.toml`. cxcc is not installed by
default. An interactive apply asks `Install the cx/cc environment? [y/N]`;
pressing Enter skips it. Set `INSTALL_CXCC=1` to install non-interactively or
`INSTALL_CXCC=0` to skip without prompting.

Runtime state:

```text
~/.ai-env/profiles.json       profile registry
~/.ai-env/state.json          selected profile state
~/.ai-env/health.json         cached health probe results
~/.ai-secrets/secrets.toml    real local secrets
```

`cx` / `cc` only switch the current shell environment. They do not launch Codex
or Claude Code; run `codex` or `claude` separately after switching.

### Profile Behavior

- Subscription profiles clear API-specific variables and use the local CLI
  login cache.
- API profiles load keys and router URLs from `~/.ai-secrets/secrets.toml`.
- Codex API profiles can share `~/.codex` so sessions/history stay together.
- Multiple Codex subscription accounts should use separate `CODEX_HOME`
  directories.
- `cx add-api` creates the matching `~/.codex/<profile>.config.toml`.
- `cx edit` / `cc edit` open `~/.ai-env/profiles.json` for registry changes
  that the helpers do not cover.

### Health, Status, and Probe Models

`cx health` and `cc health` make minimal real generation requests:

- Claude: `/v1/messages`
- Codex: `/responses`, with `/chat/completions` fallback

The probe validates generated content, not just HTTP reachability. Results are
cached for about 5 minutes.

- `cx list` / `cc list` show cached health only; no network request.
- `cx status` / `cc status` show current state, probe model, and cached health.
- `status --fresh` or `status --refresh` probes the selected profile live.
- Bare `cx` / `cc` auto-selects a cached healthy/degraded profile, preferring
  the configured default; `next` cycles manually.
- `probe_model` can be set per profile when a router does not serve the default
  model.
- Without `probe_model`, Claude probes use `ANTHROPIC_MODEL`, then
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`, then a cheap Haiku fallback. Codex probes
  use the runtime TOML model, then the global `~/.codex/config.toml` model, then
  a cheap GPT fallback.

Health table notes are intentionally short so TTY tables do not wrap. `status`
and switch output keep fuller errors for debugging.

## MCP Server Sync

`mcp` manages MCP servers for Claude Code and Codex from one local file:

```sh
mcp edit
mcp list
mcp get context7
mcp sync
mcp pull
mcp pull context7
```

Source of truth:

```text
~/.ai-env/mcp.toml
```

Example:

```toml
[mcp.context7]
command = ["npx", "-y", "@upstash/context7-mcp"]
sync = ["claude", "codex"]
enabled = true

[mcp.figma]
url = "https://mcp.figma.com/mcp"
sync = ["codex"]
enabled = false
```

`mcp sync` writes globally to Claude `~/.claude.json` and Codex
`~/.codex/config.toml`, preserving unrelated settings. Disabled servers are
omitted from Claude and written disabled/omitted for Codex according to helper
behavior. Codex's official `@openai-curated` connectors are managed by Codex
itself and are out of scope.

## Secrets

Real secrets belong in:

```text
~/.ai-secrets/secrets.toml
```

Use the profile's `secret_id` as the TOML section:

```toml
[codex.api]
OPENAI_API_KEY = "sk-..."

[claude.api]
ANTHROPIC_BASE_URL = "https://router.example"
ANTHROPIC_AUTH_TOKEN = "sk-..."
```

`secret_examples/` contains safe templates only. Do not commit real tokens,
OAuth files, generated auth state, or local MCP secrets.

## Chezmoi Map

| Source | Target |
|--------|--------|
| `dot_zshrc` | `~/.zshrc` |
| `dot_tmux.conf` | `~/.tmux.conf` |
| `dot_config/fastfetch/*` | `~/.config/fastfetch/*` |
| `.chezmoidata.toml`, `scripts/install/cxcc.*` | pinned cxcc release under `~/.local/share/cxcc` |
| `dot_ai-env/create_profiles.json` | `~/.ai-env/profiles.json` if missing |
| `dot_codex/create_*.toml` | `~/.codex/*.toml` if missing |
| `dot_claude/create_settings.json` | `~/.claude/settings.json` if missing |
| `Documents/PowerShell/create_Microsoft.PowerShell_profile.ps1` | Windows profile that loads `~/.local/share/cxcc/load.ps1` |
| `run_onchange_before_00-install-env.sh.tmpl` | installer hook |
| `run_before_10-install-cxcc.*.tmpl` | pinned cxcc install hooks |
| `run_after_99-smoke-test.sh.tmpl` | post-apply smoke hook |

Files prefixed with `create_` seed missing local config only. Existing machine
settings are left in place.

## Validation

```powershell
pwsh -NoProfile -File test/cxcc-consumer-smoke.ps1
pwsh -NoProfile -File test/powershell-profile-smoke.ps1 -SourceDir .
```

```sh
bash -n scripts/install/cxcc.sh test/cxcc-consumer-smoke.sh
bash test/cxcc-consumer-smoke.sh
```

## AI-Assisted Maintenance

This repository is maintained by Tim-1e with reviewed AI assistance. Claude,
Cursor Agent, and Codex have helped design, test, document, and harden the
environment tooling. AI contributions are recorded in commit trailers such as
`Co-authored-by`, while the repository owner reviews and ships the final state.
