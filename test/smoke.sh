#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/cargo/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${DOTFILES_SOURCE_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/install.env"
SYSTEM_INSTALL=0
TERMUX=0

if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
fi

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

warn_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "skipped command check: $1 is not installed" >&2
    return
  }
}

echo "Running dotfiles smoke check..."

check_file "$HOME/.zshrc"
check_file "$HOME/.tmux.conf"
check_file "$HOME/.config/fastfetch/config.jsonc"
check_file "$HOME/.config/fastfetch/logo.ansi"

check_command zoxide
check_command fzf
check_command eza
check_command rustc

if [ "${TERMUX:-0}" = "1" ]; then
  warn_command uv
else
  check_command uv
fi

bash "$SOURCE_DIR/test/fonts-smoke.sh"
if [ "${INSTALL_CXCC:-0}" = "0" ]; then
  echo "skipped cxcc smoke: INSTALL_CXCC is not enabled" >&2
elif [ "$INSTALL_CXCC" = "1" ]; then
  bash "$SOURCE_DIR/test/cxcc-consumer-smoke.sh"

  cxcc_root="${CXCC_HOME:-$HOME/.local/share/cxcc}"
  check_file "$cxcc_root/.cxcc-root"
  check_file "$cxcc_root/current.json"
  check_file "$cxcc_root/load.sh"
  check_file "$cxcc_root/load.ps1"
  cxcc_version="$(sed -n 's/^.*"version":"\([^"]*\)".*$/\1/p' "$cxcc_root/current.json")"
  check_file "$cxcc_root/versions/$cxcc_version/VERSION"
  [ "$(cat "$cxcc_root/versions/$cxcc_version/VERSION")" = "$cxcc_version" ] || {
    echo "cxcc installed version metadata is invalid" >&2
    exit 1
  }
  # shellcheck source=/dev/null
  source "$cxcc_root/load.sh"
  cx help >/dev/null
  cc help >/dev/null
  mcp help >/dev/null
else
  echo "INSTALL_CXCC must be 0 or 1." >&2
  exit 1
fi

FASTFETCH_OK=0
if command -v fastfetch >/dev/null 2>&1 && fastfetch --version >/dev/null 2>&1; then
  FASTFETCH_OK=1
else
  echo "skipped command check: fastfetch is not installed or not compatible" >&2
fi

if [ "${TERMUX:-0}" = "1" ]; then
  check_command zsh
  check_command tmux
  check_command bat
  warn_command lolcrab
elif [ "${SYSTEM_INSTALL:-0}" = "1" ]; then
  check_command zsh
  check_command tmux
  check_command bat
  check_command lolcrab
else
  warn_command zsh
  warn_command tmux
  warn_command bat
  warn_command lolcrab
fi

# Modern CLI tools (scripts/install/modern-cli.sh) are best-effort user-level
# downloads — warn (don't fail) so a transient network/rate-limit blip can't
# break the smoke check.
for _mcli in rg fd jq yq delta dust duf sd tldr procs xh gping btop; do
  warn_command "$_mcli"
done

if command -v zsh >/dev/null 2>&1; then
  zsh -ic 'echo zsh-ok'
fi

if command -v tmux >/dev/null 2>&1; then
  tmux -f "$HOME/.tmux.conf" start-server
fi

if [ "$FASTFETCH_OK" = "1" ]; then
  fastfetch --config "$HOME/.config/fastfetch/config.jsonc" --pipe false >/tmp/fastfetch.out
fi

echo "Dotfiles smoke check passed."
