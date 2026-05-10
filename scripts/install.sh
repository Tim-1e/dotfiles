#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export PATH="$CARGO_HOME/bin:$HOME/.local/bin:$PATH"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "This installer needs root or sudo for apt packages." >&2
    exit 1
  fi
fi

apt_install() {
  $SUDO apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=60 update
  $SUDO apt-get \
    -o Acquire::Retries=5 \
    -o Acquire::http::Timeout=60 \
    install -y --no-install-recommends "$@"
  $SUDO rm -rf /var/lib/apt/lists/*
}

install_base_packages() {
  apt_install \
    zsh tmux curl wget git nano procps build-essential ca-certificates sshfs \
    locales locales-all ncurses-term fzf python3 python3-venv unzip xz-utils \
    nodejs npm

  if command -v locale-gen >/dev/null 2>&1; then
    $SUDO locale-gen en_US.UTF-8 || true
    $SUDO locale-gen zh_CN.UTF-8 || true
    $SUDO update-locale LANG=en_US.UTF-8 || true
  fi
}

install_oh_my_zsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$zsh_custom/plugins"

  if [ ! -d "$zsh_custom/plugins/zsh-autosuggestions" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$zsh_custom/plugins/zsh-autosuggestions"
  fi

  if [ ! -d "$zsh_custom/plugins/zsh-syntax-highlighting" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$zsh_custom/plugins/zsh-syntax-highlighting"
  fi
}

install_zoxide() {
  if ! command -v zoxide >/dev/null 2>&1; then
    curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  fi
}

install_tpm() {
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
}

install_rust() {
  if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  fi
}

install_cargo_tools() {
  if command -v cargo >/dev/null 2>&1; then
    cargo install --locked eza || cargo install eza
    cargo install --locked bat || cargo install bat
    cargo install --locked lolcrab || cargo install lolcrab
  fi
}

install_fastfetch() {
  if command -v fastfetch >/dev/null 2>&1; then
    return
  fi

  local url deb
  url="$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
    | grep 'browser_download_url.*amd64.deb' \
    | head -n 1 \
    | cut -d '"' -f 4)"

  if [ -z "$url" ]; then
    echo "Could not find latest fastfetch amd64 deb release." >&2
    exit 1
  fi

  deb="$(mktemp --suffix=.deb)"
  curl -fsSL "$url" -o "$deb"
  $SUDO apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=60 update
  $SUDO apt-get \
    -o Acquire::Retries=5 \
    -o Acquire::http::Timeout=60 \
    install -y "$deb"
  rm -f "$deb"
  $SUDO rm -rf /var/lib/apt/lists/*
}

install_uv() {
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
}

install_claude() {
  if [ "${INSTALL_CLAUDE:-0}" != "1" ] || command -v claude >/dev/null 2>&1; then
    return
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}

main() {
  install_base_packages
  install_oh_my_zsh
  install_zoxide
  install_tpm
  install_rust
  install_cargo_tools
  install_fastfetch
  install_uv
  install_claude
}

main "$@"
