#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export PATH="$CARGO_HOME/bin:$HOME/.local/bin:$PATH"

SUDO=""
HAS_SYSTEM_INSTALL=0
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
STATE_FILE="$STATE_DIR/install.env"

setup_system_install() {
  if [ "$(id -u)" -eq 0 ]; then
    HAS_SYSTEM_INSTALL=1
    return
  fi

  case "${DOTFILES_USE_SUDO:-auto}" in
    0|false|no|NO|False)
      echo "Skipping system packages because DOTFILES_USE_SUDO=0."
      return
      ;;
    1|true|yes|YES|True)
      if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        HAS_SYSTEM_INSTALL=1
      else
        echo "sudo not found; skipping system packages."
      fi
      return
      ;;
  esac

  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo not found; skipping system packages."
    return
  fi

  if sudo -n true >/dev/null 2>&1; then
    SUDO="sudo"
    HAS_SYSTEM_INSTALL=1
    return
  fi

  if [ -t 0 ] && [ -t 1 ]; then
    printf "Use sudo to install system packages? [Y/n] "
    read -r answer
    case "$answer" in
      n|N|no|NO)
        echo "Skipping system packages."
        ;;
      *)
        SUDO="sudo"
        HAS_SYSTEM_INSTALL=1
        ;;
    esac
  else
    echo "sudo requires interaction; skipping system packages."
  fi
}

write_state() {
  mkdir -p "$STATE_DIR"
  {
    echo "SYSTEM_INSTALL=$HAS_SYSTEM_INSTALL"
    echo "INSTALL_NODE=${INSTALL_NODE:-1}"
  } > "$STATE_FILE"
}

apt_install() {
  $SUDO apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=60 update
  $SUDO apt-get \
    -o Acquire::Retries=5 \
    -o Acquire::http::Timeout=60 \
    install -y --no-install-recommends "$@"
  $SUDO rm -rf /var/lib/apt/lists/*
}

install_base_packages() {
  if [ "$HAS_SYSTEM_INSTALL" != "1" ]; then
    echo "Skipping apt packages; root/sudo was not enabled."
    return
  fi

  apt_install \
    zsh tmux curl wget git nano procps build-essential ca-certificates sshfs \
    locales locales-all ncurses-term fzf python3 python3-venv unzip xz-utils

  if command -v locale-gen >/dev/null 2>&1; then
    $SUDO locale-gen en_US.UTF-8 || true
    $SUDO locale-gen zh_CN.UTF-8 || true
    $SUDO update-locale LANG=en_US.UTF-8 || true
  fi
}

install_node() {
  if [ "${INSTALL_NODE:-1}" = "0" ] || command -v node >/dev/null 2>&1; then
    return
  fi

  if [ "$HAS_SYSTEM_INSTALL" != "1" ]; then
    echo "Skipping Node.js/npm; root/sudo was not enabled."
    return
  fi

  apt_install nodejs npm
}

install_oh_my_zsh() {
  if ! command -v zsh >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "Skipping Oh My Zsh; zsh or git is not available."
    return
  fi

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
  if ! command -v git >/dev/null 2>&1; then
    echo "Skipping TPM; git is not available."
    return
  fi

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
    install_cargo_tool eza
    install_cargo_tool bat
    install_cargo_tool lolcrab
  fi
}

install_cargo_tool() {
  local tool="$1"

  if command -v "$tool" >/dev/null 2>&1; then
    return
  fi

  if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    echo "Skipping $tool; no C compiler is available."
    return
  fi

  if cargo install --locked "$tool" || cargo install "$tool"; then
    return
  fi

  if [ "$HAS_SYSTEM_INSTALL" = "1" ]; then
    echo "Failed to install $tool." >&2
    exit 1
  fi

  echo "Skipping $tool after cargo install failed."
}

install_fastfetch() {
  if command -v fastfetch >/dev/null 2>&1; then
    return
  fi

  local arch archive asset_dir
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *)
      echo "Unsupported architecture for fastfetch: $(uname -m)" >&2
      return
      ;;
  esac

  archive="$(mktemp --suffix=.tar.gz)"
  asset_dir="fastfetch-linux-$arch"
  mkdir -p "$HOME/.local/bin"
  curl -fsSL "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/$asset_dir.tar.gz" -o "$archive"
  tar -xzf "$archive" --strip-components=3 -C "$HOME/.local/bin" "$asset_dir/usr/bin/fastfetch"
  chmod +x "$HOME/.local/bin/fastfetch"
  rm -f "$archive"
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
  setup_system_install
  write_state
  install_base_packages
  install_node
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
