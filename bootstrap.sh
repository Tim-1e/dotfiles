#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

is_termux() {
  [ -n "${TERMUX_VERSION:-}" ] \
    || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]
}

install_chezmoi() {
  if command -v chezmoi >/dev/null 2>&1; then
    return
  fi

  if is_termux && command -v pkg >/dev/null 2>&1; then
    pkg update -y
    pkg install -y chezmoi git curl
    return
  fi

  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
}

main() {
  install_chezmoi

  if [ "$#" -gt 0 ]; then
    chezmoi init --apply "$1"
  else
    repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    chezmoi apply --source "$repo_dir"
  fi
}

main "$@"
