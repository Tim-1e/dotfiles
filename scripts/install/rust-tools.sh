#!/usr/bin/env bash

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
