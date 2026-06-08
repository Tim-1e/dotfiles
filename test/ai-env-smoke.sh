#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${DOTFILES_SOURCE_DIR:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! command -v node >/dev/null 2>&1; then
  echo "skipped ai-env shell smoke: node is not installed" >&2
  exit 0
fi

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_home/.local/share/ai-env" "$tmp_home/.ai-env" "$tmp_home/.codex"
cp "$SOURCE_DIR/dot_local/share/ai-env/ai-env.sh" "$tmp_home/.local/share/ai-env/ai-env.sh"
cp "$SOURCE_DIR/dot_ai-env/create_profiles.json" "$tmp_home/.ai-env/profiles.json"
cp "$SOURCE_DIR/dot_codex/create_sub.config.toml" "$tmp_home/.codex/sub.config.toml"
cp "$SOURCE_DIR/dot_codex/create_api.config.toml" "$tmp_home/.codex/api.config.toml"

(
  export HOME="$tmp_home"
  # shellcheck source=/dev/null
  . "$HOME/.local/share/ai-env/ai-env.sh"

  cx help >/tmp/cx-help.out
  cx list >/tmp/cx-list.out
  cc help >/tmp/cc-help.out
  cc list >/tmp/cc-list.out

  grep -q "cx - switch Codex state" /tmp/cx-help.out
  grep -q "Codex profiles" /tmp/cx-list.out
  grep -q "cc - switch Claude Code state" /tmp/cc-help.out
  grep -q "Claude Code profiles" /tmp/cc-list.out
  test "${CODEX_HOME}" = "$tmp_home/.codex"
)

echo "AI env shell smoke check passed."
