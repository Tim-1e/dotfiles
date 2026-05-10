#!/usr/bin/env bash

install_user_zsh() {
  if command -v zsh >/dev/null 2>&1; then
    return
  fi

  if ! command -v make >/dev/null 2>&1; then
    echo "Skipping user zsh build; make is not available."
    return
  fi

  if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    echo "Skipping user zsh build; no C compiler is available."
    return
  fi

  if ! command -v tar >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1; then
    echo "Skipping user zsh build; tar or xz is not available."
    return
  fi

  local build_dir archive jobs
  build_dir="$(mktemp -d)"
  archive="$build_dir/zsh-$ZSH_VERSION_TO_INSTALL.tar.xz"
  jobs="2"
  if command -v nproc >/dev/null 2>&1; then
    jobs="$(nproc)"
  fi

  echo "Building zsh $ZSH_VERSION_TO_INSTALL into $HOME/.local..."
  if curl -fsSL "https://www.zsh.org/pub/zsh-$ZSH_VERSION_TO_INSTALL.tar.xz" -o "$archive" \
    && tar -xf "$archive" -C "$build_dir" \
    && (
      cd "$build_dir/zsh-$ZSH_VERSION_TO_INSTALL"
      ./configure --prefix="$HOME/.local"
      make -j"$jobs"
      make install
    ); then
    rm -rf "$build_dir"
    return
  fi

  rm -rf "$build_dir"
  if [ "$HAS_SYSTEM_INSTALL" = "1" ]; then
    echo "Failed to build zsh." >&2
    exit 1
  fi

  echo "Skipping zsh after user build failed."
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
