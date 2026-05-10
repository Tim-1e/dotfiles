#!/usr/bin/env bash

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
