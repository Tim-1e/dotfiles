#!/usr/bin/env bash

install_base_packages() {
  if is_termux; then
    if [ "$HAS_SYSTEM_INSTALL" != "1" ]; then
      echo "Skipping Termux packages; pkg is not available."
      return
    fi

    termux_pkg_install \
      zsh tmux curl wget git nano procps build-essential ca-certificates \
      openssh fzf python unzip xz-utils

    termux_pkg_install_optional zoxide eza bat fastfetch
    return
  fi

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

  if is_termux; then
    if [ "$HAS_SYSTEM_INSTALL" = "1" ]; then
      termux_pkg_install nodejs
    else
      echo "Skipping Node.js/npm; Termux pkg was not available."
    fi
    return
  fi

  if [ "$HAS_SYSTEM_INSTALL" != "1" ]; then
    echo "Skipping Node.js/npm; root/sudo was not enabled."
    return
  fi

  apt_install nodejs npm
}
