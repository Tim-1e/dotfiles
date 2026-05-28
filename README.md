# Dotfiles

Chezmoi-managed shell environment for Debian/Ubuntu style Linux systems.

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

- zsh, tmux, git, curl, wget, nano, fzf, build tools, locales
- Oh My Zsh plus `zsh-autosuggestions` and `zsh-syntax-highlighting`
- zoxide, TPM, rustup, uv
- cargo tools: `eza`, `bat`, `lolcrab`
- latest fastfetch release into `~/.local/bin`
- Node.js and npm by default when system package installation is enabled
- 0xProto Nerd Fonts into the current user's font directory

Without sudo, system packages are skipped. If `zsh` is not available but
`gcc`/`cc`, `make`, `tar`, and `xz` are present, zsh is built from source into
`~/.local`.
`fzf` and `eza` are installed from upstream release binaries into `~/.local/bin`
when system packages are skipped or unavailable.

On older systems with old glibc, the latest fastfetch prebuilt binary may be
incompatible. The installer falls back to fastfetch's polyfilled Linux binary
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

## Chezmoi files

- `dot_zshrc` -> `~/.zshrc`
- `dot_tmux.conf` -> `~/.tmux.conf`
- `dot_config/fastfetch/*` -> `~/.config/fastfetch/*`
- `run_onchange_before_00-install-env.sh.tmpl` runs `scripts/install.sh` before applying dotfiles when it changes
- `run_after_99-smoke-test.sh.tmpl` runs `test/smoke.sh` after applying dotfiles
