# Dotfiles

[![CI](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml)

Chezmoi-managed shell environment for Debian/Ubuntu style Linux systems, WSL,
Termux, and a small Windows PowerShell setup.

## One-command deploy

From a fresh Linux environment:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e
```

Equivalent explicit repository form:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

Local deploy from a cloned checkout:

```sh
bash ./bootstrap.sh
```

Windows deploy from a cloned checkout:

```powershell
.\bootstrap.ps1
```

Termux deploy:

```sh
pkg update
pkg install -y bash termux-exec git chezmoi
chezmoi init --apply Tim-1e/dotfiles
```

`termux-exec` provides `/usr/bin/env` and other standard paths that chezmoi
scripts rely on. Without it, the first apply may fail with
`fork/exec ... no such file or directory` even when bash is already installed.

Install Claude Code as part of the deploy:

```sh
INSTALL_CLAUDE=1 bash ./bootstrap.sh
```

Node.js and npm are installed by default when system package installation is enabled.
Skip them with:

```sh
INSTALL_NODE=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e
```

Skip fastfetch with:

```sh
INSTALL_FASTFETCH=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e
```

System packages are installed when running as root or when passwordless sudo is
available. If sudo needs a password, the installer asks before using it and
defaults to no. To force skipping sudo-managed packages:

```sh
DOTFILES_USE_SUDO=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e
```

To explicitly use sudo:

```sh
DOTFILES_USE_SUDO=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e
```

## What it installs

- zsh, tmux, git, curl, wget, nano, fzf, build tools, locales where available
- Oh My Zsh plus `zsh-autosuggestions` and `zsh-syntax-highlighting`
- zoxide, TPM, rustup, uv
- cargo tools: `eza`, `bat`, `lolcrab`
- modern CLI tools as user-level binaries in `~/.local/bin` (no root needed):
  `rg`, `fd`, `jq`, `yq`, `delta`, `dust`, `duf`, `sd`, `tldr`, `procs`, `xh`,
  `gping`, `btop` — see [Modern CLI tools](#modern-cli-tools)
- latest fastfetch release into `~/.local/bin`
- Node.js and npm by default when system package installation is enabled
- 0xProto Nerd Fonts into the current user's font directory
- Windows PowerShell profile helpers for `cx` and `cc`

Without sudo, system packages are skipped. If `zsh` is not available but
`gcc`/`cc`, `make`, `tar`, and `xz` are present, zsh is built from source into
`~/.local`.
`fzf` and `eza` are installed from upstream release binaries into `~/.local/bin`
when system packages are skipped or unavailable.

On Termux, packages are installed with `pkg` instead of `apt-get`, rust is
installed from Termux packages instead of rustup, and Linux release binaries are
skipped when they are not compatible with Android. Install `bash` and
`termux-exec` before the first `chezmoi apply` so run-on-change scripts can
execute.

On older Linux systems with old glibc, the latest fastfetch prebuilt binary may
be incompatible. The installer falls back to fastfetch's polyfilled Linux binary
when available, then skips fastfetch instead of failing the whole apply.

## Modern CLI tools

`scripts/install/modern-cli.sh` installs a set of modern, lightweight CLI tools
as **user-level** prebuilt binaries into `~/.local/bin` — no root or `sudo`, the
same approach as `fzf`/`eza`. Each tool is best-effort: a download or extract
failure prints a `Skipping …` line and never aborts the apply, and any tool
already on `PATH` is left untouched.

| Tool | Replaces / use | Tool | Replaces / use |
|------|----------------|------|----------------|
| `rg` (ripgrep) | fast recursive grep | `procs` | `ps`, readable |
| `fd` | friendly `find` | `btop` | `top`/`htop` monitor |
| `jq` | JSON processor | `xh` | HTTP client (curl/httpie) |
| `yq` | YAML/TOML processor | `gping` | `ping` with a live graph |
| `delta` | syntax-highlighted git diffs | `dust` | `du` as a tree |
| `sd` | simpler `sed` find/replace | `duf` | `df`, prettier |
| `tldr` | community example man pages | | |

`dot_zshrc` adds **safe interactive aliases** only where the replacement is a
drop-in: `du`→`dust`, `df`→`duf`, `ps`→`procs`, `ping`→`gping`,
`top`/`htop`→`btop`. `rg`/`fd`/`sd`/`jq`/`yq`/`xh`/`delta` are intentionally
**not** aliased over `grep`/`find`/`sed` (their flags differ and aliasing would
break scripts and muscle memory) — use them by name. When `fd` is present it
also backs fzf's file/dir walks via `FZF_DEFAULT_COMMAND`.

Binaries are pulled from each project's GitHub releases (x86_64 and arm64;
unsupported architectures are skipped). For `procs` (published only as a `.zip`)
the script uses `unzip` when present and otherwise a tiny built-in Node
extractor, so it still installs on minimal images without `unzip`. Skip this
whole layer with:

```sh
INSTALL_MODERN_CLI=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e
```

## Fonts

The bundled `0xProto` Nerd Font `.ttf` files are cross-platform, but each OS
needs a different user-level install location:

- Linux: `~/.local/share/fonts/0xProto`, followed by `fc-cache` when available
- macOS: `~/Library/Fonts`
- Windows: `%LOCALAPPDATA%\Microsoft\Windows\Fonts` plus HKCU font registry entries

On WSL, the Linux font install runs by default and also installs the fonts into
the Windows host through PowerShell when available. Set
`INSTALL_WINDOWS_FONTS_FROM_WSL=0` to skip the Windows host install. Set
`INSTALL_FONTS=0` to skip font installation entirely.

## AI Profiles

This repo includes lightweight shell functions for switching local Codex and
Claude Code environments without launching either tool:

```sh
cx list
cx sub
cx api
cx stats
cx add-api api:work --base-url https://router.example/v1
cx add-sub sub:work

cc list
cc sub
cc api
cc add-api api:work --base-url https://router.example
cc add-sub sub:work

cc health                 # probe profiles (🟢🟡🔴), cached 5min; --fresh to re-probe
cc                        # no arg: auto-select a healthy profile (skips 🔴 down)
cc default api:work       # set the primary profile
cc probe-model api glm-4.6  # per-profile probe model

mcp list                  # MCP servers + which tool has each
mcp sync                  # push ~/.ai-env/mcp.toml -> Claude & Codex
mcp pull                  # import existing MCP servers into mcp.toml
```

On Windows these are loaded from:

```text
~/Documents/PowerShell/Scripts/ai-env.ps1
```

On Linux they are loaded from:

```text
~/.local/share/ai-env/ai-env.sh
```

Profiles are registered in `~/.ai-env/profiles.json`. Real API keys and router
tokens stay outside git in `~/.ai-secrets/secrets.toml`. See
`secret_examples/README.md` for copy-and-edit examples.

Codex subscription profiles use their own `CODEX_HOME` when multiple ChatGPT
accounts are needed. Codex API profiles can share the normal `~/.codex` home and
only load `OPENAI_API_KEY` for the current shell. Claude Code profiles clear or
set Anthropic environment variables.

Use `cx add-api NAME` / `cc add-api NAME` to register a new API profile without
putting secrets in git. The commands update `~/.ai-env/profiles.json`; Codex API
profiles also create `~/.codex/<profile>.config.toml`. Put real tokens in
`~/.ai-secrets/secrets.toml` under the printed section name. Use
`cx remove NAME` or `cc remove NAME` to remove a registration. By default, Codex
API profiles keep `home: ~/.codex` so sessions and history remain shared across
projects.

`cx stats` gives a quick local-only usage view by scanning recent Codex rollout
JSONL files under `CODEX_HOME/sessions`. It reports total, input, cached input,
output, and reasoning token counts with a small text bar chart. It does not call
network APIs and does not estimate cost.

### Health checks and auto-failover

`cc health` / `cx health` probe each API profile by making a real, minimal
request to its actual wire endpoint (Claude `/v1/messages`; Codex `/responses`
then `/chat/completions`) and validating that a generation actually comes back —
not just that the endpoint is reachable. Results are classified as 🟢 healthy,
🟡 degraded (slow, or transient 429/5xx), 🔴 down (401/404/timeout), or ⏭ skip
(subscription profiles, which can't be probed remotely).

- Results are cached in `~/.ai-env/health.json` for 5 minutes; pass `--fresh` to
  re-probe. There is **no background daemon** — probes only run on `health`,
  `list`, `status`, or switch.
- `cc list` / `cx list` show a `Health` column read **from cache only** (no
  network); a stale or never-probed entry shows ⏭ as a hint to run `cc health`.
- Running `cc` / `cx` with no argument **auto-selects** the first non-down
  profile (default first), so a dead router is skipped automatically. `cc next`
  keeps the old cycle-to-next behavior.
- Relays serve different model sets, so the probe model can be per-profile:
  `cc probe-model NAME MODEL`. Without `probe_model`, Claude probes use
  `ANTHROPIC_MODEL`, then `ANTHROPIC_DEFAULT_HAIKU_MODEL`, then a cheap Haiku
  fallback; Codex probes use the runtime TOML `model`, then the global
  `~/.codex/config.toml` model, then a cheap GPT fallback. If a relay reports
  that the probe model is unsupported, set `probe_model` for that profile.
  `cc default NAME` sets the primary; `cc health-clear` clears the cache. The
  probe uses Node's built-in HTTPS (no `curl` dependency).

### MCP servers

`mcp` manages MCP servers for both Claude Code and Codex from a single source of
truth, `~/.ai-env/mcp.toml`:

```sh
mcp edit                  # open mcp.toml in $EDITOR (creates a starter if absent)
mcp list                  # servers + whether each target currently has them
mcp sync                  # push mcp.toml -> Claude & Codex (idempotent)
mcp pull [NAME]           # import existing servers from the targets into mcp.toml
mcp get NAME              # show one server's config + target status
```

Each `[mcp.NAME]` block is either stdio (`command = [...]`) or http
(`url = "..."`), with optional `env = { ... }`, `sync = ["claude", "codex"]`
(omit = both), and `enabled = false` to keep a server defined but skipped.
`mcp sync` writes globally — Claude `~/.claude.json` `mcpServers` (atomic JSON
merge that preserves your other keys, with a `.aienv.bak` backup) and Codex
`~/.codex/config.toml` `[mcp_servers.NAME]` (surgical block edit that preserves
model/providers and any servers you manage by hand). Disabled or unsynced
servers are removed from Claude and written with `enabled = false` on Codex.
`mcp.toml` is machine-local (not synced via chezmoi); copy
`secret_examples/mcp.toml.example` to start. Codex's official `@openai-curated`
connectors are managed by Codex itself and are intentionally out of scope.

Local Codex/Claude settings are conservative: the dotfiles create default
`~/.codex/*.config.toml`, `~/.claude/settings.json`, and
`~/.ai-env/profiles.json` only when those files are missing. Existing machine
settings are not overwritten.

## Chezmoi files

- `dot_zshrc` -> `~/.zshrc`
- `dot_tmux.conf` -> `~/.tmux.conf`
- `dot_config/fastfetch/*` -> `~/.config/fastfetch/*`
- `dot_local/share/ai-env/ai-env.sh` -> `~/.local/share/ai-env/ai-env.sh`
- `dot_ai-env/create_profiles.json` -> `~/.ai-env/profiles.json` if missing
- `dot_codex/create_*.toml` -> `~/.codex/*.toml` if missing
- `dot_claude/create_settings.json` -> `~/.claude/settings.json` if missing
- `Documents/PowerShell/Scripts/ai-env.ps1` -> Windows PowerShell helper script
- `run_onchange_before_00-install-env.sh.tmpl` runs `scripts/install.sh` before applying dotfiles when it changes
- `run_after_99-smoke-test.sh.tmpl` runs `test/smoke.sh` after applying dotfiles
