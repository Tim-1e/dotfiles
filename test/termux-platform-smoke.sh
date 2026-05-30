#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
PKG_LOG="$TMP_DIR/pkg.log"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/pkg" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$TERMUX_PKG_LOG"
SH
chmod +x "$FAKE_BIN/pkg"

export PATH="$FAKE_BIN:/bin"
export PREFIX="/data/data/com.termux/files/usr"
export TERMUX_VERSION="test"
export TERMUX_PKG_LOG="$PKG_LOG"
export INSTALL_NODE=1

# shellcheck source=../scripts/lib/common.sh
. "$SOURCE_DIR/scripts/lib/common.sh"
# shellcheck source=../scripts/install/system-packages.sh
. "$SOURCE_DIR/scripts/install/system-packages.sh"

setup_system_install
test "$HAS_SYSTEM_INSTALL" = "1"

install_base_packages
install_node

grep -q 'update -y' "$PKG_LOG"
grep -q 'install -y bash termux-exec zsh tmux curl wget git nano procps build-essential ca-certificates openssh fzf python unzip xz-utils' "$PKG_LOG"
grep -q 'install -y nodejs' "$PKG_LOG"

echo "Termux platform smoke check passed."
