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

cc list
cc sub
cc api
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
