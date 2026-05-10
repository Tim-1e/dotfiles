#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/cargo/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

check_file() {
  test -f "$1" || {
    echo "missing file: $1" >&2
    exit 1
  }
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

echo "Running dotfiles smoke check..."

check_file "$HOME/.zshrc"
check_file "$HOME/.tmux.conf"
check_file "$HOME/.config/fastfetch/config.jsonc"
check_file "$HOME/.config/fastfetch/logo.ansi"

check_command zsh
check_command tmux
check_command zoxide
check_command fastfetch
check_command uv
check_command rustc
check_command eza
check_command bat
check_command lolcrab

zsh -ic 'echo zsh-ok'
tmux -f "$HOME/.tmux.conf" start-server
fastfetch --config "$HOME/.config/fastfetch/config.jsonc" --pipe false >/tmp/fastfetch.out

echo "Dotfiles smoke check passed."
