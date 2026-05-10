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

## What it installs

- zsh, tmux, git, curl, wget, nano, fzf, build tools, locales
- Oh My Zsh plus `zsh-autosuggestions` and `zsh-syntax-highlighting`
- zoxide, TPM, rustup, uv
- cargo tools: `eza`, `bat`, `lolcrab`
- latest amd64 `.deb` release of fastfetch

## Chezmoi files

- `dot_zshrc` -> `~/.zshrc`
- `dot_tmux.conf` -> `~/.tmux.conf`
- `dot_config/fastfetch/*` -> `~/.config/fastfetch/*`
- `run_once_before_00-install-env.sh.tmpl` runs `scripts/install.sh` before applying dotfiles

## Docker smoke test

```sh
docker build -t dotfiles-test .
docker run --rm dotfiles-test sh /opt/dotfiles/test/smoke.sh
```
