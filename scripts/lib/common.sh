#!/usr/bin/env bash

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export PATH="$CARGO_HOME/bin:$HOME/.local/bin:$PATH"

ZSH_VERSION_TO_INSTALL="${ZSH_VERSION_TO_INSTALL:-5.9}"
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
        if sudo -v; then
          SUDO="sudo"
          HAS_SYSTEM_INSTALL=1
        else
          echo "sudo authentication failed; skipping system packages."
        fi
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
    printf "sudo is available but needs authentication. Use it to install system packages? [y/N] "
    read -r answer
    case "$answer" in
      y|Y|yes|YES)
        if sudo -v; then
          SUDO="sudo"
          HAS_SYSTEM_INSTALL=1
        else
          echo "sudo authentication failed; skipping system packages."
        fi
        ;;
      *)
        echo "Skipping system packages."
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
    echo "INSTALL_FONTS=${INSTALL_FONTS:-1}"
    echo "INSTALL_WINDOWS_FONTS_FROM_WSL=${INSTALL_WINDOWS_FONTS_FROM_WSL:-1}"
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
