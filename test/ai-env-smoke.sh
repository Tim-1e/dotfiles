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
mkdir -p "$tmp_home/.codex/sessions/2026/06/09"
cat >"$tmp_home/.codex/sessions/2026/06/09/rollout-2026-06-09T00-00-00-stats-smoke.jsonl" <<'EOF'
{"timestamp":"2026-06-09T00:00:00.000Z","type":"session_meta","payload":{"id":"stats-smoke","cwd":"/workspace"}}
{"timestamp":"2026-06-09T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":700,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}
EOF
printf '%s\n' \
  '{' \
  '  "codex": "sub",' \
  '  "claude": "api:docker"' \
  '}' >"$tmp_home/.ai-env/state.json"
cat >"$tmp_home/.ai-secrets/secrets.toml" <<'EOF'
[codex.api]
OPENAI_API_KEY = "sk-test-codex"

[codex.cxenvtest]
OPENAI_API_KEY = "sk-test-cxenv"

[claude.api-docker]
ANTHROPIC_BASE_URL = "https://anyrouter.top"
ANTHROPIC_AUTH_TOKEN = "sk-test-token"

[claude.envtest]
ANTHROPIC_AUTH_TOKEN = "sk-test-envtoken"
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
  run_step cx-stats cx stats --days 365
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
  assert_contains "Codex local token stats" "$debug_dir/cx-stats.out"
  assert_contains "Total: 1.2K (1200)" "$debug_dir/cx-stats.out"
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

  # per-profile env (--env): persisted in registry, exported on switch, cleared on switch-away
  export AI_ENV_NONINTERACTIVE=1
  run_step cc-add-env cc add-api envtest --base-url https://claude.test --env ANTHROPIC_DEFAULT_SONNET_MODEL=glm-test-sonnet --env CLAUDE_CODE_AUTO_COMPACT_WINDOW=987654
  run_step cx-add-env cx add-api cxenvtest --base-url https://router.test/v1 --env CODEX_EXTRA_FLAG=on
  assert_contains "ANTHROPIC_DEFAULT_SONNET_MODEL" "$tmp_home/.ai-env/profiles.json"
  assert_contains "Env: ANTHROPIC_DEFAULT_SONNET_MODEL" "$debug_dir/cc-add-env.out"

  cc envtest >"$debug_dir/cc-envtest.out" 2>&1
  [ "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" = "glm-test-sonnet" ] || { echo "cc switch did not export profile env" >&2; exit 1; }
  [ "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" = "987654" ] || { echo "cc switch did not export compact window" >&2; exit 1; }
  cc api:docker >"$debug_dir/cc-env-away.out" 2>&1
  [ -z "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" ] || { echo "cc switch-away did not clear profile env (leak)" >&2; exit 1; }
  cx cxenvtest >"$debug_dir/cx-envtest.out" 2>&1
  [ "${CODEX_EXTRA_FLAG:-}" = "on" ] || { echo "cx switch did not export profile env" >&2; exit 1; }
  cx api >"$debug_dir/cx-env-away.out" 2>&1
  [ -z "${CODEX_EXTRA_FLAG:-}" ] || { echo "cx switch-away did not clear profile env (leak)" >&2; exit 1; }

  # --- health: mock the network probe, test cache/cell/select/probe-model/default ---
  _ai_probe_health() {
    case "$(_ai_profile_value "$2" name "")" in
      hgood) printf '{"status":"healthy","latencyMs":120,"method":"generation","error":null}';;
      hbad)  printf '{"status":"down","latencyMs":0,"method":"none","error":"HTTP 401"}';;
      hslow) printf '{"status":"degraded","latencyMs":9999,"method":"generation","error":"HTTP 429 (transient)"}';;
      *)     printf '{"status":"down","latencyMs":0,"method":"none","error":"HTTP 404"}';;
    esac
  }
  cc add-api hgood --base-url https://h.test >/dev/null 2>&1
  cc add-api hbad  --base-url https://h.test >/dev/null 2>&1
  cc add-api hslow --base-url https://h.test >/dev/null 2>&1
  cc probe-model hgood my-sonnet >/dev/null 2>&1
  [ "$(_ai_profile_value "$(_ai_profile_json claude hgood)" probe_model "")" = "my-sonnet" ] || { echo "probe-model set failed" >&2; exit 1; }
  cc probe-model hgood >/dev/null 2>&1
  [ -z "$(_ai_profile_value "$(_ai_profile_json claude hgood)" probe_model "")" ] || { echo "probe-model clear failed" >&2; exit 1; }
  cc default hbad >/dev/null 2>&1
  [ "$(_ai_default_profile claude)" = "hbad" ] || { echo "default set failed" >&2; exit 1; }
  rm -f "$AI_HEALTH_PATH"
  pj="$(_ai_profile_json claude hgood)"
  r1="$(_ai_health_cached claude "$pj" 0)"
  [ -f "$AI_HEALTH_PATH" ] || { echo "health.json not written" >&2; exit 1; }
  case "$(_ai_health_cell "$r1")" in 🟢120ms) :;; *) echo "health cell wrong: $(_ai_health_cell "$r1")" >&2; exit 1;; esac
  [ "$(_ai_healthy_profile claude)" = "hgood" ] || { echo "auto-select did not skip down -> hgood" >&2; exit 1; }
  cc status >/dev/null 2>&1
  grep -q "Health:" < <(cc status 2>/dev/null) || { echo "cc status missing Health line" >&2; exit 1; }
  cc health-clear; [ ! -f "$AI_HEALTH_PATH" ] || { echo "health-clear failed" >&2; exit 1; }
  mcp list >/dev/null 2>&1 || { echo "mcp command failed" >&2; exit 1; }

  # --- mcp: offline (file-only, no network) ---
  export AI_CLAUDE_JSON_PATH="$tmp_home/.claude.json"
  export AI_CODEX_CONFIG_PATH="$tmp_home/.codex/config.toml"
  cat >"$AI_MCP_PATH" <<'TOML'
[mcp.context7]
command = ["npx", "-y", "@upstash/context7-mcp"]
sync = ["claude", "codex"]
enabled = true

[mcp.figma]
url = "https://mcp.figma.com/mcp"
sync = ["codex"]
enabled = false
TOML
  echo '{"mcpServers":{}}' >"$AI_CLAUDE_JSON_PATH"
  : >"$AI_CODEX_CONFIG_PATH"
  mcp sync >/dev/null 2>&1
  grep -q '"context7"' "$AI_CLAUDE_JSON_PATH" || { echo "mcp sync: claude missing context7" >&2; exit 1; }
  ! grep -q '"figma"' "$AI_CLAUDE_JSON_PATH" || { echo "mcp sync: claude should not have disabled figma" >&2; exit 1; }
  grep -q '\[mcp_servers.context7\]' "$AI_CODEX_CONFIG_PATH" || { echo "mcp sync: codex missing context7" >&2; exit 1; }
  ! grep -q '\[mcp_servers.figma\]' "$AI_CODEX_CONFIG_PATH" || { echo "mcp sync: codex should not have disabled figma" >&2; exit 1; }
  grep -q context7 < <(mcp list) || { echo "mcp list missing context7" >&2; exit 1; }
  rm -f "$AI_MCP_PATH"
  echo '{"mcpServers":{"newone":{"command":"echo"}}}' >"$AI_CLAUDE_JSON_PATH"
  : >"$AI_CODEX_CONFIG_PATH"
  grep -q '+1 added' < <(mcp pull 2>&1) || { echo "mcp pull did not add newone" >&2; exit 1; }
  grep -q '\[mcp.newone\]' "$AI_MCP_PATH" || { echo "mcp pull did not write newone" >&2; exit 1; }
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
