#!/usr/bin/env bash

font_repo_dir() {
  if [ -n "${DOTFILES_SOURCE_DIR:-}" ]; then
    printf '%s\n' "$DOTFILES_SOURCE_DIR"
    return
  fi

  local repo_dir
  repo_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s\n' "$repo_dir"
}

font_source_dir() {
  printf '%s/0xProto\n' "$(font_repo_dir)"
}

install_unix_fonts() {
  local source_dir="$1"
  local target_dir="$2"
  local font target

  mkdir -p "$target_dir"
  for font in "$source_dir"/*.ttf; do
    [ -f "$font" ] || continue
    target="$target_dir/$(basename "$font")"
    if [ ! -f "$target" ] || ! cmp -s "$font" "$target"; then
      cp "$font" "$target"
    fi
  done

  echo "Installed 0xProto Nerd Font files to $target_dir."
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

install_windows_fonts() {
  local source_dir="$1"
  local script_path powershell_bin windows_source windows_script

  script_path="$(font_repo_dir)/scripts/install/fonts-windows.ps1"
  if [ ! -f "$script_path" ]; then
    echo "Skipping Windows font install; missing $script_path."
    return
  fi

  powershell_bin="$(find_windows_powershell)"
  if [ -z "$powershell_bin" ]; then
    echo "Skipping Windows font install; PowerShell was not found."
    return
  fi

  windows_source="$(to_windows_path "$source_dir")"
  windows_script="$(to_windows_path "$script_path")"
  "$powershell_bin" -NoProfile -ExecutionPolicy Bypass -File "$windows_script" -SourceDir "$windows_source"
}

install_linux_fonts() {
  local source_dir="$1"
  local font_root="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
  local target_dir="$font_root/0xProto"

  install_unix_fonts "$source_dir" "$target_dir"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$font_root" >/dev/null 2>&1 || true
  fi

  if is_wsl; then
    case "${INSTALL_WINDOWS_FONTS_FROM_WSL:-1}" in
      0|false|False|FALSE|no|No|NO) ;;
      *) install_windows_fonts "$source_dir" ;;
    esac
  fi
}

install_macos_fonts() {
  install_unix_fonts "$1" "$HOME/Library/Fonts"
}

install_fonts() {
  case "${INSTALL_FONTS:-1}" in
    0|false|False|FALSE|no|No|NO)
      echo "Skipping 0xProto Nerd Fonts because INSTALL_FONTS=${INSTALL_FONTS}."
      return
      ;;
  esac

  local source_dir
  source_dir="$(font_source_dir)"
  if ! ls "$source_dir"/*.ttf >/dev/null 2>&1; then
    echo "Skipping 0xProto Nerd Fonts; no .ttf files found in $source_dir."
    return
  fi

  case "$(uname -s)" in
    Linux*) install_linux_fonts "$source_dir" ;;
    Darwin*) install_macos_fonts "$source_dir" ;;
    MINGW*|MSYS*|CYGWIN*) install_windows_fonts "$source_dir" ;;
    *) echo "Skipping 0xProto Nerd Fonts; unsupported platform: $(uname -s)." ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  install_fonts "$@"
fi
