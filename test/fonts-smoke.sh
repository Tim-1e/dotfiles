#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${DOTFILES_SOURCE_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
FONT_SOURCE_DIR="$SOURCE_DIR/0xProto"

case "${INSTALL_FONTS:-1}" in
  0|false|False|FALSE|no|No|NO)
    echo "Skipping font smoke check because INSTALL_FONTS=${INSTALL_FONTS}."
    exit 0
    ;;
esac

fail() {
  echo "$1" >&2
  exit 1
}

is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
}

to_windows_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  elif command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

find_windows_powershell() {
  command -v pwsh.exe 2>/dev/null \
    || command -v powershell.exe 2>/dev/null \
    || command -v pwsh 2>/dev/null \
    || command -v powershell 2>/dev/null \
    || true
}

test -d "$FONT_SOURCE_DIR" || fail "missing font source dir: $FONT_SOURCE_DIR"
ls "$FONT_SOURCE_DIR"/*.ttf >/dev/null 2>&1 || fail "missing .ttf files in $FONT_SOURCE_DIR"

case "$(uname -s)" in
  Linux*)
    FONT_TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/0xProto"
    test -f "$FONT_TARGET_DIR/0xProtoNerdFontMono-Regular.ttf" \
      || fail "missing installed Linux font: $FONT_TARGET_DIR/0xProtoNerdFontMono-Regular.ttf"

    if command -v fc-list >/dev/null 2>&1; then
      fc-list | grep -qi '0xProto Nerd Font Mono' \
        || fail "fontconfig cannot find 0xProto Nerd Font Mono"
    fi

    if is_wsl; then
      case "${INSTALL_WINDOWS_FONTS_FROM_WSL:-1}" in
        0|false|False|FALSE|no|No|NO) ;;
        *)
          POWERSHELL_BIN="$(find_windows_powershell)"
          if [ -n "$POWERSHELL_BIN" ]; then
            "$POWERSHELL_BIN" -NoProfile -ExecutionPolicy Bypass \
              -File "$(to_windows_path "$SOURCE_DIR/test/fonts-smoke.ps1")" \
              -SourceDir "$(to_windows_path "$FONT_SOURCE_DIR")"
          fi
          ;;
      esac
    fi
    ;;
  Darwin*)
    test -f "$HOME/Library/Fonts/0xProtoNerdFontMono-Regular.ttf" \
      || fail "missing installed macOS font: $HOME/Library/Fonts/0xProtoNerdFontMono-Regular.ttf"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    POWERSHELL_BIN="$(find_windows_powershell)"
    test -n "$POWERSHELL_BIN" || fail "PowerShell was not found"
    "$POWERSHELL_BIN" -NoProfile -ExecutionPolicy Bypass \
      -File "$(to_windows_path "$SOURCE_DIR/test/fonts-smoke.ps1")" \
      -SourceDir "$(to_windows_path "$FONT_SOURCE_DIR")"
    ;;
  *)
    fail "unsupported platform: $(uname -s)"
    ;;
esac

echo "Font smoke check passed."
