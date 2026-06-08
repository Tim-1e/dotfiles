#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="${DOTFILES_SOURCE_DIR:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! command -v node >/dev/null 2>&1; then
  echo "skipped ai-env shell smoke: node is not installed" >&2
  exit 0
fi

tmp_root="$(mktemp -d)"
tmp_home="$tmp_root/home"
debug_dir="$tmp_root/output"
trap 'status=$?; if [ "$status" -ne 0 ]; then echo "AI env shell smoke failed with exit $status." >&2; for file in "$debug_dir"/*; do [ -e "$file" ] || continue; echo "--- ${file##*/} ---" >&2; cat "$file" >&2; done; fi; rm -rf "$tmp_root"' EXIT

mkdir -p "$tmp_home/.local/share/ai-env" "$tmp_home/.ai-env" "$tmp_home/.ai-secrets" "$tmp_home/.codex" "$debug_dir"
cp "$SOURCE_DIR/dot_local/share/ai-env/ai-env.sh" "$tmp_home/.local/share/ai-env/ai-env.sh"
cp "$SOURCE_DIR/dot_ai-env/create_profiles.json" "$tmp_home/.ai-env/profiles.json"
cp "$SOURCE_DIR/dot_codex/create_sub.config.toml" "$tmp_home/.codex/sub.config.toml"
cp "$SOURCE_DIR/dot_codex/create_api.config.toml" "$tmp_home/.codex/api.config.toml"
printf '%s\n' \
  '{' \
  '  "codex": "sub",' \
  '  "claude": "api:docker"' \
  '}' >"$tmp_home/.ai-env/state.json"
cat >"$tmp_home/.ai-secrets/secrets.toml" <<'EOF'
[codex.api]
OPENAI_API_KEY = "sk-test-codex"

[claude.api-docker]
ANTHROPIC_BASE_URL = "https://anyrouter.top"
ANTHROPIC_AUTH_TOKEN = "sk-test-token"
EOF

run_step() {
  local name="$1"
  shift
  "$@" >"$debug_dir/$name.out" 2>"$debug_dir/$name.err" || {
    echo "command failed: $*" >&2
    return 1
  }
}

assert_contains() {
  local needle="$1" file="$2"
  grep -q "$needle" "$file" || {
    echo "missing expected text '$needle' in $file" >&2
    return 1
  }
}

(
  export HOME="$tmp_home"
  # shellcheck source=/dev/null
  if ! . "$HOME/.local/share/ai-env/ai-env.sh"; then
    echo "failed to source ai-env.sh" >&2
    exit 1
  fi

  run_step cx-help cx help
  run_step cx-list cx list
  run_step cc-help cc help
  run_step cc-list cc list
  run_step cx-add-api cx add-api api:test --base-url https://router.test/v1 --model gpt-test
  run_step cx-add-sub cx add-sub sub:test
  run_step cc-add-api cc add-api api:test --base-url https://claude.test
  run_step cc-add-sub cc add-sub sub:test
  [ -f "$tmp_home/.codex/api-api-test.config.toml" ] || {
    echo "cx add-api did not write Codex config" >&2
    exit 1
  }
  run_step cx-managed-list cx list
  run_step cc-managed-list cc list
  run_step cx-remove-api cx remove api:test --delete-config
  run_step cx-remove-sub cx remove sub:test --delete-config
  run_step cc-remove-api cc remove api:test
  run_step cc-remove-sub cc remove sub:test

  assert_contains "cx - switch Codex state" "$debug_dir/cx-help.out"
  assert_contains "cx add-api NAME" "$debug_dir/cx-help.out"
  assert_contains "Codex profiles" "$debug_dir/cx-list.out"
  assert_contains "secrets.toml#codex.api" "$debug_dir/cx-list.out"
  assert_contains "cc - switch Claude Code state" "$debug_dir/cc-help.out"
  assert_contains "cc add-api NAME" "$debug_dir/cc-help.out"
  assert_contains "Claude Code profiles" "$debug_dir/cc-list.out"
  assert_contains "secrets.toml#claude.api-docker" "$debug_dir/cc-list.out"
  assert_contains "Added Codex API profile 'api:test'" "$debug_dir/cx-add-api.out"
  assert_contains "Added Codex subscription profile 'sub:test'" "$debug_dir/cx-add-sub.out"
  assert_contains "Added Claude Code API profile 'api:test'" "$debug_dir/cc-add-api.out"
  assert_contains "Added Claude Code subscription profile 'sub:test'" "$debug_dir/cc-add-sub.out"
  assert_contains "api:test" "$debug_dir/cx-managed-list.out"
  assert_contains "sub:test" "$debug_dir/cx-managed-list.out"
  assert_contains "api:test" "$debug_dir/cc-managed-list.out"
  assert_contains "sub:test" "$debug_dir/cc-managed-list.out"
  assert_contains "Removed Codex profile 'api:test'" "$debug_dir/cx-remove-api.out"
  assert_contains "Removed Codex profile 'sub:test'" "$debug_dir/cx-remove-sub.out"
  assert_contains "Removed Claude Code profile 'api:test'" "$debug_dir/cc-remove-api.out"
  assert_contains "Removed Claude Code profile 'sub:test'" "$debug_dir/cc-remove-sub.out"
  [ ! -f "$tmp_home/.codex/api-api-test.config.toml" ] || {
    echo "cx remove --delete-config did not remove Codex config" >&2
    exit 1
  }
  if [ "${CODEX_HOME}" != "$tmp_home/.codex" ]; then
    echo "unexpected CODEX_HOME: got '${CODEX_HOME}', expected '$tmp_home/.codex'" >&2
    exit 1
  fi
)

if command -v zsh >/dev/null 2>&1; then
  run_step zsh-ai-env env HOME="$tmp_home" zsh -f -ic '
    source "$HOME/.local/share/ai-env/ai-env.sh"
    command -v node >/dev/null
    toml_base_url="$(_ai_toml_value "$HOME/.codex/api.config.toml" base_url)"
    [ "$toml_base_url" = "https://api.aixhan.com/v1" ]
    cx list
    cc status
  '
  assert_contains "Codex profiles" "$debug_dir/zsh-ai-env.out"
  assert_contains "Saved: api:docker" "$debug_dir/zsh-ai-env.out"
  assert_contains "ANTHROPIC_AUTH_TOKEN: sk-test-...oken" "$debug_dir/zsh-ai-env.out"
  if [ -s "$debug_dir/zsh-ai-env.err" ]; then
    echo "unexpected zsh stderr:" >&2
    cat "$debug_dir/zsh-ai-env.err" >&2
    exit 1
  fi
fi

echo "AI env shell smoke check passed."
