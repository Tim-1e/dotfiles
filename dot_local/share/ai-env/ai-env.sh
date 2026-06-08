# AI environment profile functions. Source this file from an interactive shell.

AI_CONFIG_DIR="${HOME}/.ai-env"
AI_REGISTRY_PATH="${AI_CONFIG_DIR}/profiles.json"
AI_STATE_PATH="${AI_CONFIG_DIR}/state.json"
LEGACY_AI_STATE_DIR="${HOME}/.ai-state"
CLAUDE_ROUTER_BASE_URL="https://anyrouter.top"

_ai_expand_path() {
  local input_path="${1:-}"
  case "$input_path" in
    "") return 0 ;;
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${input_path#\~/}" ;;
    *) printf '%s\n' "$input_path" ;;
  esac
}

_ai_require_node() {
  command -v node >/dev/null 2>&1 || {
    echo "ai-env needs node to read $AI_REGISTRY_PATH" >&2
    return 1
  }
}

_ai_profile_json() {
  local tool="$1" name="$2"
  _ai_require_node || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const query = String(process.argv[3] || "").toLowerCase();
const fallback = {
  defaults: { codex: "sub", claude: "sub" },
  codex: [
    { name: "sub", aliases: ["subscription", "chatgpt"], mode: "sub", home: "~/.codex", codex_profile: "sub" },
    { name: "api", aliases: ["router"], mode: "api", home: "~/.codex", codex_profile: "api", linux_secret: "~/.ai-secrets/codex-api.env" }
  ],
  claude: [
    { name: "sub", aliases: ["subscription", "claude-sub"], mode: "sub" },
    { name: "api", aliases: ["router", "claude-api"], mode: "api", base_url: "https://anyrouter.top", linux_secret: "~/.ai-secrets/claude-api.env" }
  ]
};
let registry = fallback;
if (fs.existsSync(path)) registry = JSON.parse(fs.readFileSync(path, "utf8"));
for (const p of registry[tool] || []) {
  if (p.enabled === false) continue;
  const names = [p.name, ...(p.aliases || [])].filter(Boolean).map((x) => String(x).toLowerCase());
  if (names.includes(query)) {
    process.stdout.write(JSON.stringify(p));
    process.exit(0);
  }
}
process.exit(2);
' "$AI_REGISTRY_PATH" "$tool" "$name"
}

_ai_profile_value() {
  local profile_json="$1" key="$2" default_value="${3:-}"
  _ai_require_node || return 1
  node -e '
const p = JSON.parse(process.argv[1]);
const key = process.argv[2];
const fallback = process.argv[3] || "";
const value = Object.prototype.hasOwnProperty.call(p, key) ? p[key] : fallback;
if (Array.isArray(value)) process.stdout.write(value.join(","));
else if (value === undefined || value === null) process.stdout.write(fallback);
else process.stdout.write(String(value));
' "$profile_json" "$key" "$default_value"
}

_ai_default_profile() {
  local tool="$1"
  _ai_require_node || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
let registry = { defaults: { codex: "sub", claude: "sub" } };
if (fs.existsSync(path)) registry = JSON.parse(fs.readFileSync(path, "utf8"));
process.stdout.write(String((registry.defaults && registry.defaults[tool]) || "sub"));
' "$AI_REGISTRY_PATH" "$tool"
}

_ai_legacy_saved_profile() {
  local tool="$1" file
  if [ "$tool" = "codex" ]; then
    file="${LEGACY_AI_STATE_DIR}/cx.profile"
  else
    file="${LEGACY_AI_STATE_DIR}/cc.profile"
  fi
  [ -f "$file" ] && head -n 1 "$file"
}

_ai_saved_profile() {
  local tool="$1" default_profile value
  default_profile="$(_ai_default_profile "$tool" 2>/dev/null || printf 'sub')"
  if _ai_require_node >/dev/null 2>&1 && [ -f "$AI_STATE_PATH" ]; then
    value="$(node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
try {
  const state = JSON.parse(fs.readFileSync(path, "utf8"));
  process.stdout.write(String(state[tool] || ""));
} catch {}
' "$AI_STATE_PATH" "$tool")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
  fi
  value="$(_ai_legacy_saved_profile "$tool" || true)"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_profile"
  fi
}

_ai_save_profile() {
  local tool="$1" name="$2"
  mkdir -p "$AI_CONFIG_DIR"
  _ai_require_node || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const name = process.argv[3];
let state = {};
try {
  if (fs.existsSync(path)) state = JSON.parse(fs.readFileSync(path, "utf8"));
} catch {}
state[tool] = name;
state.updated_at = new Date().toISOString();
fs.writeFileSync(path, JSON.stringify(state, null, 2) + "\n");
' "$AI_STATE_PATH" "$tool" "$name"
}

_ai_next_profile() {
  local tool="$1" saved
  saved="$(_ai_saved_profile "$tool")"
  _ai_require_node || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const saved = String(process.argv[3] || "").toLowerCase();
let registry = { defaults: { codex: "sub", claude: "sub" }, codex: [], claude: [] };
if (fs.existsSync(path)) registry = JSON.parse(fs.readFileSync(path, "utf8"));
const profiles = (registry[tool] || []).filter((p) => p.enabled !== false);
if (!profiles.length) {
  process.stdout.write("sub");
  process.exit(0);
}
const index = profiles.findIndex((p) => String(p.name || "").toLowerCase() === saved);
if (index >= 0) process.stdout.write(String(profiles[(index + 1) % profiles.length].name));
else process.stdout.write(String((registry.defaults && registry.defaults[tool]) || profiles[0].name || "sub"));
' "$AI_REGISTRY_PATH" "$tool" "$saved"
}

_ai_secret_path() {
  local profile_json="$1" secret_path
  secret_path="$(_ai_profile_value "$profile_json" linux_secret "")"
  [ -n "$secret_path" ] || secret_path="$(_ai_profile_value "$profile_json" secret "")"
  _ai_expand_path "$secret_path"
}

_ai_secret_preview() {
  local value="${1:-}" len
  if [ -z "$value" ]; then
    printf '<unset>\n'
    return
  fi
  len=${#value}
  if [ "$len" -le 12 ]; then
    printf '%s...\n' "${value:0:4}"
  else
    printf '%s...%s\n' "${value:0:8}" "${value: -4}"
  fi
}

_ai_toml_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
}

_codex_profile_name() {
  local profile_json="$1" value name
  value="$(_ai_profile_value "$profile_json" codex_profile "")"
  [ -n "$value" ] || value="$(_ai_profile_value "$profile_json" profile "")"
  if [ -z "$value" ]; then
    name="$(_ai_profile_value "$profile_json" name "")"
    value="${name/:/-}"
  fi
  printf '%s\n' "$value"
}

_codex_home() {
  local profile_json="$1"
  _ai_expand_path "$(_ai_profile_value "$profile_json" home "~/.codex")"
}

_codex_profile_path() {
  local profile_json="$1" home profile
  home="$(_codex_home "$profile_json")"
  profile="$(_codex_profile_name "$profile_json")"
  printf '%s/%s.config.toml\n' "$home" "$profile"
}

_read_json_openai_key() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.OPENAI_API_KEY // empty' "$file"
  else
    node -e 'const fs=require("fs"); const p=process.argv[1]; const j=JSON.parse(fs.readFileSync(p,"utf8")); process.stdout.write(j.OPENAI_API_KEY || "");' "$file"
  fi
}

_codex_login_status() {
  command codex login status 2>&1 | tr '\n' ' '
}

_cx_doctor_summary() {
  local profile_json="$1" profile_file provider model base_url wire_api env_key provider_name json
  local -a args
  command -v codex >/dev/null 2>&1 || return
  command -v node >/dev/null 2>&1 || {
    echo "  Doctor: unavailable (node not found for JSON parsing)"
    return
  }

  profile_file="$(_codex_profile_path "$profile_json")"
  provider="$(_ai_toml_value "$profile_file" model_provider)"
  model="$(_ai_toml_value "$profile_file" model)"

  args=(doctor --json)
  [ -n "$model" ] && args+=(-c "model=\"$model\"")
  [ -n "$provider" ] && args+=(-c "model_provider=\"$provider\"")

  case "$provider" in
    ""|openai|ollama|lmstudio|amazon-bedrock) ;;
    *)
      base_url="$(_ai_toml_value "$profile_file" base_url)"
      wire_api="$(_ai_toml_value "$profile_file" wire_api)"
      env_key="$(_ai_toml_value "$profile_file" env_key)"
      provider_name="$(_ai_toml_value "$profile_file" name)"
      [ -n "$provider_name" ] || provider_name="$provider"
      [ -n "$wire_api" ] || wire_api="responses"
      args+=(-c "model_providers.$provider.name=\"$provider_name\"")
      [ -n "$base_url" ] && args+=(-c "model_providers.$provider.base_url=\"$base_url\"")
      [ -n "$wire_api" ] && args+=(-c "model_providers.$provider.wire_api=\"$wire_api\"")
      [ -n "$env_key" ] && args+=(-c "model_providers.$provider.env_key=\"$env_key\"")
      ;;
  esac

  json="$(command codex "${args[@]}" 2>/dev/null)" || {
    echo "  Doctor: unavailable"
    return
  }

  printf '%s' "$json" | node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(0, "utf8"));
const check = (name) => j.checks && j.checks[name];
const detail = (c, key) => c && c.details ? c.details[key] : undefined;
const auth = check("auth.credentials");
const config = check("config.load");
const reach = check("network.provider_reachability");
const ws = check("network.websocket_reachability");
const sandbox = check("sandbox.helpers");
const threads = check("state.rollout_db_parity");
const updates = check("updates.status");
console.log(`  Doctor: ${j.overallStatus}, Codex ${j.codexVersion}`);
if (config) console.log(`  Runtime: model=${detail(config, "model")}; provider=${detail(config, "model provider")}; mcp=${detail(config, "mcp servers")}`);
if (auth) {
  console.log(`  Auth: ${auth.status} - ${auth.summary}`);
  if (detail(auth, "stored auth mode")) {
    console.log(`  Auth cache: ${detail(auth, "stored auth mode")}; api_key=${detail(auth, "stored API key")}; chatgpt_tokens=${detail(auth, "stored ChatGPT tokens")}`);
  }
}
if (reach) console.log(`  Network: ${reach.status} - ${reach.summary}`);
if (ws) console.log(`  WebSocket: ${ws.status} - ${ws.summary}`);
if (sandbox) console.log(`  Sandbox: approval=${detail(sandbox, "approval policy")}; fs=${detail(sandbox, "filesystem sandbox")}; net=${detail(sandbox, "network sandbox")}`);
if (threads) console.log(`  Threads: active=${detail(threads, "rollout DB active rows")}; archived=${detail(threads, "rollout DB archived rows")}; providers=${detail(threads, "rollout DB model providers")}`);
if (updates) console.log(`  Updates: ${detail(updates, "latest version status")}`);
'
}

_cc_external_status() {
  local json stats_path
  if command -v claude >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    json="$(command claude auth status --json 2>/dev/null || true)"
    if [ -n "$json" ]; then
      printf '%s' "$json" | node -e '
const fs = require("fs");
const a = JSON.parse(fs.readFileSync(0, "utf8"));
console.log(`  Auth status: loggedIn=${a.loggedIn}; method=${a.authMethod}; provider=${a.apiProvider}; source=${a.apiKeySource || "<none>"}`);
'
    else
      echo "  Auth status: unavailable"
    fi
  fi

  stats_path="$HOME/.claude/stats-cache.json"
  if [ -f "$stats_path" ] && command -v node >/dev/null 2>&1; then
    node -e '
const fs = require("fs");
const p = process.argv[1];
try {
  const s = JSON.parse(fs.readFileSync(p, "utf8"));
  console.log(`  Local usage cache: sessions=${s.totalSessions}; messages=${s.totalMessages}; lastComputed=${s.lastComputedDate}`);
} catch {}
' "$stats_path"
  fi
}

_set_codex_env() {
  local profile_json="$1" mode name secret legacy legacy_key
  mode="$(_ai_profile_value "$profile_json" mode sub)"
  name="$(_ai_profile_value "$profile_json" name "")"
  export CODEX_HOME="$(_codex_home "$profile_json")"
  export AI_CODEX_LABEL="$name"
  export AI_CODEX_PROFILE="$(_codex_profile_name "$profile_json")"
  mkdir -p "$CODEX_HOME"
  unset CODEX_API_KEY
  unset OPENAI_API_KEY

  AI_SECRET_SOURCE="<none>"
  if [ "$mode" = "api" ]; then
    secret="$(_ai_secret_path "$profile_json")"
    if [ -f "$secret" ]; then
      # shellcheck source=/dev/null
      . "$secret"
      AI_SECRET_SOURCE="$secret"
    fi

    if [ -z "${OPENAI_API_KEY:-}" ] && [ "$name" = "api" ]; then
      for legacy in "$HOME/.codex.API/auth.json" "$HOME/.codex-api/auth.json"; do
        if [ -f "$legacy" ]; then
          legacy_key="$(_read_json_openai_key "$legacy")"
          if [ -n "$legacy_key" ]; then
            export OPENAI_API_KEY="$legacy_key"
            AI_SECRET_SOURCE="legacy .codex.API auth.json"
            break
          fi
        fi
      done
    fi

    if [ -z "${OPENAI_API_KEY:-}" ]; then
      echo "cx $name needs OPENAI_API_KEY. Put it in $secret." >&2
      return 1
    fi
  fi
}

_set_claude_env() {
  local profile_json="$1" mode name secret base_url
  mode="$(_ai_profile_value "$profile_json" mode sub)"
  name="$(_ai_profile_value "$profile_json" name "")"
  export AI_CLAUDE_LABEL="$name"
  unset ANTHROPIC_API_KEY
  unset ANTHROPIC_AUTH_TOKEN
  unset ANTHROPIC_BASE_URL
  unset ANTHROPIC_MODEL

  AI_SECRET_SOURCE="<none>"
  if [ "$mode" = "api" ]; then
    secret="$(_ai_secret_path "$profile_json")"
    if [ -f "$secret" ]; then
      # shellcheck source=/dev/null
      . "$secret"
      AI_SECRET_SOURCE="$secret"
    fi

    base_url="$(_ai_profile_value "$profile_json" base_url "$CLAUDE_ROUTER_BASE_URL")"
    [ -n "${ANTHROPIC_BASE_URL:-}" ] || export ANTHROPIC_BASE_URL="$base_url"

    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
      echo "cc $name needs ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN in $secret." >&2
      return 1
    fi
  fi
}

_cx_print_status() {
  local profile_json="$1" mode name profile_file base_url
  mode="$(_ai_profile_value "$profile_json" mode sub)"
  name="$(_ai_profile_value "$profile_json" name "")"
  profile_file="$(_codex_profile_path "$profile_json")"
  base_url="$(_ai_toml_value "$profile_file" base_url)"
  [ -n "$base_url" ] || base_url="built-in OpenAI/ChatGPT endpoint"
  echo "Codex state switched: $name"
  echo "  Run next: codex"
  echo "  Registry: $AI_REGISTRY_PATH"
  echo "  CODEX_HOME: $CODEX_HOME"
  echo "  Profile: $AI_CODEX_PROFILE ($profile_file)"
  echo "  Base URL: $base_url"
  echo "  Cached login: $(_codex_login_status)"
  if [ "$mode" = "api" ]; then
    echo "  OPENAI_API_KEY: $(_ai_secret_preview "${OPENAI_API_KEY:-}")"
    echo "  Secret source: $AI_SECRET_SOURCE"
    echo "  API local check: profile file=$([ -f "$profile_file" ] && echo true || echo false); key=$([ -n "${OPENAI_API_KEY:-}" ] && echo true || echo false)"
  else
    echo "  OPENAI_API_KEY: <cleared>"
    echo "  Subscription quota: not exposed by Codex CLI"
  fi
  _cx_doctor_summary "$profile_json"
}

_cc_print_status() {
  local profile_json="$1" mode name
  mode="$(_ai_profile_value "$profile_json" mode sub)"
  name="$(_ai_profile_value "$profile_json" name "")"
  echo "Claude Code state switched: $name"
  echo "  Run next: claude"
  echo "  Registry: $AI_REGISTRY_PATH"
  if [ "$mode" = "api" ]; then
    echo "  ANTHROPIC_BASE_URL: ${ANTHROPIC_BASE_URL:-<unset>}"
    echo "  ANTHROPIC_API_KEY: $(_ai_secret_preview "${ANTHROPIC_API_KEY:-}")"
    echo "  ANTHROPIC_AUTH_TOKEN: $(_ai_secret_preview "${ANTHROPIC_AUTH_TOKEN:-}")"
    echo "  Secret source: $AI_SECRET_SOURCE"
  else
    echo "  Anthropic API env: <cleared>"
    echo "  Subscription status: local Claude login is used if present"
  fi
  _cc_external_status
}

_ai_list_profiles() {
  local tool="$1"
  _ai_require_node || return 1
  if command -v column >/dev/null 2>&1; then
    node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const saved = process.argv[3];
const home = process.env.HOME;
const exists = (p) => p && fs.existsSync(p);
const expand = (p) => !p ? "" : p.replace(/^~(?=\/|$)/, home);
let registry = JSON.parse(fs.readFileSync(path, "utf8"));
console.log(["Sel", "Name", "Mode", "Ready", "Runtime", "Secret", "Description"].join("\t"));
for (const p of registry[tool] || []) {
  const mode = p.mode || "sub";
  const runtime = tool === "codex" ? `${expand(p.home || "~/.codex")}/${p.codex_profile || p.profile || String(p.name || "").replace(":", "-")}.config.toml` : (p.base_url || "local subscription");
  const secret = mode === "api" ? expand(p.linux_secret || p.secret || "") : "<none>";
  const configOk = tool !== "codex" || exists(runtime);
  const secretOk = mode !== "api" || exists(secret);
  const ready = tool === "codex" && mode === "sub" && !configOk ? "ok-default" : (configOk && secretOk ? "ok" : (!configOk ? "missing-config" : "missing-secret"));
  const selected = String(p.name || "") === saved ? "*" : " ";
  console.log([selected, p.name || "", mode, ready, runtime, secret || "<missing>", p.description || ""].join("\t"));
}
' "$AI_REGISTRY_PATH" "$tool" "$(_ai_saved_profile "$tool")" | column -t -s "$(printf '\t')"
  else
    node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const saved = process.argv[3];
const home = process.env.HOME;
const exists = (p) => p && fs.existsSync(p);
const expand = (p) => !p ? "" : p.replace(/^~(?=\/|$)/, home);
let registry = JSON.parse(fs.readFileSync(path, "utf8"));
console.log(["Sel", "Name", "Mode", "Ready", "Runtime", "Secret", "Description"].join("\t"));
for (const p of registry[tool] || []) {
  const mode = p.mode || "sub";
  const runtime = tool === "codex" ? `${expand(p.home || "~/.codex")}/${p.codex_profile || p.profile || String(p.name || "").replace(":", "-")}.config.toml` : (p.base_url || "local subscription");
  const secret = mode === "api" ? expand(p.linux_secret || p.secret || "") : "<none>";
  const configOk = tool !== "codex" || exists(runtime);
  const secretOk = mode !== "api" || exists(secret);
  const ready = tool === "codex" && mode === "sub" && !configOk ? "ok-default" : (configOk && secretOk ? "ok" : (!configOk ? "missing-config" : "missing-secret"));
  const selected = String(p.name || "") === saved ? "*" : " ";
  console.log([selected, p.name || "", mode, ready, runtime, secret || "<missing>", p.description || ""].join("\t"));
}
' "$AI_REGISTRY_PATH" "$tool" "$(_ai_saved_profile "$tool")"
  fi
}

cx() {
  local arg="${1:-}" profile_json name
  case "$arg" in
    help|-h|--help)
      cat <<'EOF'
cx - switch Codex state for this shell

Usage:
  cx                 Cycle through enabled Codex profiles
  cx sub             Use a named subscription profile
  cx sub:work        Use another subscription profile, if registered
  cx api             Use the default API profile
  cx api:docker      Use a named API profile
  cx list            List registry profiles
  cx status          Print current state
  cx help            Show this help

Config:
  Registry: ~/.ai-env/profiles.json
  State:    ~/.ai-env/state.json
  Secrets:  ~/.ai-secrets/*.env

After switching, run Codex separately: codex
EOF
      return
      ;;
    list)
      echo "Codex profiles ($AI_REGISTRY_PATH):"
      _ai_list_profiles codex
      return
      ;;
    status)
      echo "Codex state:"
      echo "  Registry: $AI_REGISTRY_PATH"
      echo "  State: $AI_STATE_PATH"
      echo "  Saved: $(_ai_saved_profile codex)"
      echo "  Process label: ${AI_CODEX_LABEL:-<unset>}"
      echo "  Process profile: ${AI_CODEX_PROFILE:-<unset>}"
      echo "  CODEX_HOME: ${CODEX_HOME:-$HOME/.codex}"
      echo "  OPENAI_API_KEY: $(_ai_secret_preview "${OPENAI_API_KEY:-}")"
      echo "  Cached login: $(_codex_login_status)"
      profile_json="$(_ai_profile_json codex "${AI_CODEX_LABEL:-$(_ai_saved_profile codex)}")" && _cx_doctor_summary "$profile_json"
      return
      ;;
  esac

  if [ -n "$arg" ]; then
    profile_json="$(_ai_profile_json codex "$arg")" || { echo "Unknown cx profile '$arg'. Add it to $AI_REGISTRY_PATH or run 'cx help'." >&2; return 1; }
  else
    profile_json="$(_ai_profile_json codex "$(_ai_next_profile codex)")" || return 1
  fi
  name="$(_ai_profile_value "$profile_json" name "")"
  _ai_save_profile codex "$name" || return
  _set_codex_env "$profile_json" || return
  _cx_print_status "$profile_json"
}

cc() {
  local arg="${1:-}" profile_json name
  case "$arg" in
    help|-h|--help)
      cat <<'EOF'
cc - switch Claude Code state for this shell

Usage:
  cc                 Cycle through enabled Claude Code profiles
  cc sub             Clear Anthropic API env and use local Claude subscription login
  cc sub:work        Use another subscription profile, if registered
  cc api             Use the default API profile
  cc api:docker      Use a named API profile
  cc list            List registry profiles
  cc status          Print current state
  cc help            Show this help

Config:
  Registry: ~/.ai-env/profiles.json
  State:    ~/.ai-env/state.json
  Secrets:  ~/.ai-secrets/*.env

After switching, run Claude Code separately: claude
EOF
      return
      ;;
    list)
      echo "Claude Code profiles ($AI_REGISTRY_PATH):"
      _ai_list_profiles claude
      return
      ;;
    status)
      echo "Claude Code state:"
      echo "  Registry: $AI_REGISTRY_PATH"
      echo "  State: $AI_STATE_PATH"
      echo "  Saved: $(_ai_saved_profile claude)"
      echo "  Process label: ${AI_CLAUDE_LABEL:-<unset>}"
      echo "  ANTHROPIC_BASE_URL: ${ANTHROPIC_BASE_URL:-<unset>}"
      echo "  ANTHROPIC_API_KEY: $(_ai_secret_preview "${ANTHROPIC_API_KEY:-}")"
      echo "  ANTHROPIC_AUTH_TOKEN: $(_ai_secret_preview "${ANTHROPIC_AUTH_TOKEN:-}")"
      _cc_external_status
      return
      ;;
  esac

  if [ -n "$arg" ]; then
    profile_json="$(_ai_profile_json claude "$arg")" || { echo "Unknown cc profile '$arg'. Add it to $AI_REGISTRY_PATH or run 'cc help'." >&2; return 1; }
  else
    profile_json="$(_ai_profile_json claude "$(_ai_next_profile claude)")" || return 1
  fi
  name="$(_ai_profile_value "$profile_json" name "")"
  _ai_save_profile claude "$name" || return
  _set_claude_env "$profile_json" || return
  _cc_print_status "$profile_json"
}

_codex_has_explicit_profile() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --profile|-p|--profile=*) return 0 ;;
    esac
  done
  return 1
}

_codex_first_token() {
  local skip_next=false arg
  for arg in "$@"; do
    if [ "$skip_next" = true ]; then
      skip_next=false
      continue
    fi
    case "$arg" in
      --) return 1 ;;
      -c|--config|-i|--image|-m|--model|-p|--profile|-s|--sandbox|-C|--cd|--add-dir|-a|--ask-for-approval|--remote|--remote-auth-token-env|--local-provider)
        skip_next=true
        continue
        ;;
      -*) continue ;;
      *) printf '%s\n' "$arg"; return 0 ;;
    esac
  done
  return 1
}

_codex_should_inject_profile() {
  local first
  _codex_has_explicit_profile "$@" && return 1
  first="$(_codex_first_token "$@")" || return 0
  case "$first" in
    login|logout|doctor|app|completion|update|features|help|cloud|app-server|remote-control|mcp-server|exec-server|mcp|plugin|sandbox|debug|apply|archive|unarchive)
      return 1
      ;;
  esac
  return 0
}

codex() {
  local saved profile_json profile_name
  saved="$(_ai_saved_profile codex)"
  profile_json="$(_ai_profile_json codex "${AI_CODEX_LABEL:-$saved}")" || profile_json="$(_ai_profile_json codex "$(_ai_default_profile codex)")" || return 1
  _set_codex_env "$profile_json" || return
  profile_name="$(_codex_profile_name "$profile_json")"
  if _codex_should_inject_profile "$@"; then
    if [ -f "$(_codex_profile_path "$profile_json")" ]; then
      command codex --profile "$profile_name" "$@"
    else
      command codex "$@"
    fi
  else
    command codex "$@"
  fi
}

_ai_init_saved_profiles() {
  local profile_json
  profile_json="$(_ai_profile_json codex "$(_ai_saved_profile codex)" 2>/dev/null)" && \
    _set_codex_env "$profile_json" >/dev/null 2>&1 || \
    echo "warning: could not initialize saved Codex profile" >&2

  profile_json="$(_ai_profile_json claude "$(_ai_saved_profile claude)" 2>/dev/null)" && \
    _set_claude_env "$profile_json" >/dev/null 2>&1 || \
    echo "warning: could not initialize saved Claude Code profile" >&2
}

_ai_init_saved_profiles
