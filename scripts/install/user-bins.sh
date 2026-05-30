#!/usr/bin/env bash

install_user_fzf() {
  if command -v fzf >/dev/null 2>&1; then
    return
  fi

  if is_termux; then
    echo "Skipping fzf binary install on Termux; use pkg install fzf."
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

  if is_termux; then
    echo "Skipping eza binary install on Termux; use pkg install eza."
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

install_zoxide() {
  if ! command -v zoxide >/dev/null 2>&1; then
    if is_termux; then
      if [ "$HAS_SYSTEM_INSTALL" = "1" ]; then
        termux_pkg_install_optional zoxide
      else
        echo "Skipping zoxide; Termux pkg was not available."
      fi
      return
    fi

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

install_uv() {
  if ! command -v uv >/dev/null 2>&1; then
    if is_termux; then
      if [ "$HAS_SYSTEM_INSTALL" = "1" ]; then
        termux_pkg_install_optional uv
      else
        echo "Skipping uv; Termux pkg was not available."
      fi
      return
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
}

install_claude() {
  if [ "${INSTALL_CLAUDE:-0}" != "1" ] || command -v claude >/dev/null 2>&1; then
    return
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}
