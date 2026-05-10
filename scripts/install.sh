#!/usr/bin/env bash
set -euo pipefail

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

install_user_fzf() {
  if command -v fzf >/dev/null 2>&1; then
    return
  fi

  local arch version archive member
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "Skipping fzf; unsupported architecture: $(uname -m)"
      return
      ;;
  esac

  version="$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest \
    | grep '"tag_name"' \
    | head -n 1 \
    | cut -d '"' -f 4 \
    | sed 's/^v//')"

  if [ -z "$version" ]; then
    echo "Skipping fzf; could not determine latest release."
    return
  fi

  archive="$(mktemp --suffix=.tar.gz)"
  mkdir -p "$HOME/.local/bin"
  if ! curl -fsSL "https://github.com/junegunn/fzf/releases/latest/download/fzf-$version-linux_$arch.tar.gz" -o "$archive"; then
    rm -f "$archive"
    echo "Skipping fzf; could not download release archive."
    return
  fi

  member="$(tar -tzf "$archive" | grep -E '(^|/)fzf$' | head -n 1)"
  if [ -z "$member" ]; then
    rm -f "$archive"
    echo "Skipping fzf; release archive did not contain fzf."
    return
  fi

  tar -xzf "$archive" -O "$member" > "$HOME/.local/bin/fzf"
  chmod +x "$HOME/.local/bin/fzf"
  rm -f "$archive"
}

install_user_eza() {
  if command -v eza >/dev/null 2>&1; then
    return
  fi

  local asset archive member
  case "$(uname -m)" in
    x86_64|amd64) asset="eza_x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64|arm64) asset="eza_aarch64-unknown-linux-gnu_no_libgit.tar.gz" ;;
    *)
      echo "Skipping eza binary install; unsupported architecture: $(uname -m)"
      return
      ;;
  esac

  archive="$(mktemp --suffix=.tar.gz)"
  mkdir -p "$HOME/.local/bin"
  if ! curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/$asset" -o "$archive"; then
    rm -f "$archive"
    echo "Skipping eza binary install; could not download $asset."
    return
  fi

  member="$(tar -tzf "$archive" | grep -E '(^|/)eza$' | head -n 1)"
  if [ -z "$member" ]; then
    rm -f "$archive"
    echo "Skipping eza binary install; release archive did not contain eza."
    return
  fi

  tar -xzf "$archive" -O "$member" > "$HOME/.local/bin/eza"
  chmod +x "$HOME/.local/bin/eza"
  rm -f "$archive"
}

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

  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
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
  if [ "${INSTALL_FASTFETCH:-1}" = "0" ]; then
    echo "Skipping fastfetch because INSTALL_FASTFETCH=0."
    return
  fi

  if command -v fastfetch >/dev/null 2>&1 && fastfetch --version >/dev/null 2>&1; then
    return
  fi

  local arch asset_dir polyfilled_asset
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *)
      echo "Unsupported architecture for fastfetch: $(uname -m)" >&2
      return
      ;;
  esac

  asset_dir="fastfetch-linux-$arch"
  install_fastfetch_tar "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/$asset_dir.tar.gz" "$asset_dir" \
    && return

  polyfilled_asset="fastfetch-linux-$arch-polyfilled"
  install_fastfetch_tar "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/$polyfilled_asset.tar.gz" "$asset_dir" \
    && return
  install_fastfetch_zip "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/$polyfilled_asset.zip" \
    && return

  echo "Skipping fastfetch; no compatible binary was found for this system."
  rm -f "$HOME/.local/bin/fastfetch"
}

install_fastfetch_tar() {
  local url asset_dir archive
  url="$1"
  asset_dir="$2"
  archive="$(mktemp --suffix=.tar.gz)"
  mkdir -p "$HOME/.local/bin"

  if ! curl -fsSL "$url" -o "$archive"; then
    rm -f "$archive"
    return 1
  fi

  if ! tar -xzf "$archive" --strip-components=3 -C "$HOME/.local/bin" "$asset_dir/usr/bin/fastfetch"; then
    rm -f "$archive"
    return 1
  fi

  chmod +x "$HOME/.local/bin/fastfetch"
  if "$HOME/.local/bin/fastfetch" --version >/dev/null 2>&1; then
    rm -f "$archive"
    return
  fi

  echo "fastfetch binary from $url is not compatible with this system."
  rm -f "$HOME/.local/bin/fastfetch"
  rm -f "$archive"
  return 1
}

install_fastfetch_zip() {
  local url archive
  url="$1"
  archive="$(mktemp --suffix=.zip)"
  mkdir -p "$HOME/.local/bin"

  if ! curl -fsSL "$url" -o "$archive"; then
    rm -f "$archive"
    return 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$archive" "$HOME/.local/bin/fastfetch" <<'PY'
import os
import stat
import sys
import zipfile

archive, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as zf:
    names = [
        name for name in zf.namelist()
        if name.endswith("/usr/bin/fastfetch") or name.endswith("/bin/fastfetch")
    ]
    if not names:
        raise SystemExit("fastfetch binary not found in archive")
    data = zf.read(names[0])

with open(dest, "wb") as fh:
    fh.write(data)

os.chmod(dest, os.stat(dest).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY
  elif command -v unzip >/dev/null 2>&1; then
    unzip -p "$archive" "*/usr/bin/fastfetch" > "$HOME/.local/bin/fastfetch" \
      || unzip -p "$archive" "*/bin/fastfetch" > "$HOME/.local/bin/fastfetch"
    chmod +x "$HOME/.local/bin/fastfetch"
  else
    echo "Cannot extract fastfetch zip; python3 or unzip is required."
    rm -f "$archive"
    return 1
  fi

  if "$HOME/.local/bin/fastfetch" --version >/dev/null 2>&1; then
    rm -f "$archive"
    return
  fi

  echo "fastfetch binary from $url is not compatible with this system."
  rm -f "$HOME/.local/bin/fastfetch"
  rm -f "$archive"
  return 1
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
  install_user_fzf
  install_user_eza
  install_user_zsh
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
