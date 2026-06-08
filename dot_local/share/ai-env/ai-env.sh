# AI environment profile functions. Source this file from an interactive shell.

AI_HOME="${AI_ENV_HOME:-$HOME}"
AI_CONFIG_DIR="${AI_HOME}/.ai-env"
AI_REGISTRY_PATH="${AI_CONFIG_DIR}/profiles.json"
AI_STATE_PATH="${AI_CONFIG_DIR}/state.json"
AI_SECRETS_PATH="${AI_HOME}/.ai-secrets/secrets.toml"
LEGACY_AI_STATE_DIR="${AI_HOME}/.ai-state"
CLAUDE_ROUTER_BASE_URL="https://anyrouter.top"

_ai_expand_path() {
  local input_path="${1:-}"
  case "$input_path" in
    "") return 0 ;;
    "~") printf '%s\n' "$AI_HOME" ;;
    "~/"*) printf '%s/%s\n' "$AI_HOME" "${input_path#\~/}" ;;
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
    { name: "api", aliases: ["router"], mode: "api", home: "~/.codex", codex_profile: "api", secret_id: "codex.api", linux_secret: "~/.ai-secrets/codex-api.env" }
  ],
  claude: [
    { name: "sub", aliases: ["subscription", "claude-sub"], mode: "sub" },
    { name: "api", aliases: ["router", "claude-api"], mode: "api", base_url: "https://anyrouter.top", secret_id: "claude.api", linux_secret: "~/.ai-secrets/claude-api.env" }
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

_ai_name_slug() {
  local slug
  slug="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^[-_]+//; s/[-_]+$//')"
  if [ -z "$slug" ]; then
    echo "profile name '$1' does not contain any usable letters or numbers" >&2
    return 1
  fi
  printf '%s\n' "$slug"
}

_ai_validate_name() {
  case "$1" in
    ""|[^A-Za-z0-9]*|*[!A-Za-z0-9:_-]*)
      echo "profile name '$1' is not supported. Use letters, numbers, ':', '_' or '-'." >&2
      return 1
      ;;
  esac
}

_ai_registry_add_profile() {
  local tool="$1" profile_json="$2"
  mkdir -p "$AI_CONFIG_DIR"
  _ai_require_node || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const profile = JSON.parse(process.argv[3]);
const fallback = { schema: 1, defaults: { codex: "sub", claude: "sub" }, codex: [], claude: [] };
let registry = fallback;
try {
  if (fs.existsSync(path)) registry = JSON.parse(fs.readFileSync(path, "utf8"));
} catch {}
registry.schema = registry.schema || 1;
registry.defaults = registry.defaults || { codex: "sub", claude: "sub" };
registry.codex = Array.isArray(registry.codex) ? registry.codex : [];
registry.claude = Array.isArray(registry.claude) ? registry.claude : [];
const query = String(profile.name || "").toLowerCase();
for (const p of registry[tool] || []) {
  const names = [p.name, ...(p.aliases || [])].filter(Boolean).map((x) => String(x).toLowerCase());
  if (names.includes(query)) {
    console.error(`${tool} profile ${JSON.stringify(profile.name)} already exists. Remove it first, or choose another name.`);
    process.exit(4);
  }
}
registry[tool].push(profile);
fs.writeFileSync(path, JSON.stringify(registry, null, 2) + "\n");
' "$AI_REGISTRY_PATH" "$tool" "$profile_json"
}

_ai_registry_remove_profile() {
  local tool="$1" name="$2"
  _ai_require_node || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const query = String(process.argv[3] || "").toLowerCase();
if (!fs.existsSync(path)) {
  console.error(`${tool} profile ${JSON.stringify(process.argv[3])} does not exist.`);
  process.exit(4);
}
const registry = JSON.parse(fs.readFileSync(path, "utf8"));
const profiles = Array.isArray(registry[tool]) ? registry[tool] : [];
let removed = "";
registry[tool] = profiles.filter((p) => {
  const names = [p.name, ...(p.aliases || [])].filter(Boolean).map((x) => String(x).toLowerCase());
  if (names.includes(query)) {
    removed = String(p.name || process.argv[3]);
    return false;
  }
  return true;
});
if (!removed) {
  console.error(`${tool} profile ${JSON.stringify(process.argv[3])} does not exist.`);
  process.exit(4);
}
fs.writeFileSync(path, JSON.stringify(registry, null, 2) + "\n");
process.stdout.write(removed);
' "$AI_REGISTRY_PATH" "$tool" "$name"
}

_ai_parse_management_args() {
  _ai_require_node || return 1
  node -e '
const out = { positionals: [], options: {} };
const args = process.argv.slice(1);
for (let i = 0; i < args.length; i++) {
  const arg = String(args[i]);
  if (arg.startsWith("--")) {
    const key = arg.slice(2);
    if (!key) continue;
    if (i + 1 < args.length && !String(args[i + 1]).startsWith("--")) {
      out.options[key] = String(args[++i]);
    } else {
      out.options[key] = "true";
    }
  } else {
    out.positionals.push(arg);
  }
}
process.stdout.write(JSON.stringify(out));
' -- "$@"
}

_ai_mgmt_value() {
  local parsed="$1" key="$2" default_value="${3:-}"
  node -e '
const parsed = JSON.parse(process.argv[1]);
const key = process.argv[2];
const fallback = process.argv[3] || "";
process.stdout.write(parsed.options && parsed.options[key] ? String(parsed.options[key]) : fallback);
' "$parsed" "$key" "$default_value"
}

_ai_mgmt_positional() {
  local parsed="$1" index="$2"
  node -e '
const parsed = JSON.parse(process.argv[1]);
const index = Number(process.argv[2]);
process.stdout.write(parsed.positionals && parsed.positionals[index] ? String(parsed.positionals[index]) : "");
' "$parsed" "$index"
}

_ai_json_profile() {
  _ai_require_node || return 1
  node -e '
const profile = {};
for (let i = 1; i < process.argv.length; i += 2) {
  const key = process.argv[i];
  const raw = process.argv[i + 1] || "";
  if (key === "aliases") profile[key] = raw ? raw.split(",").filter(Boolean) : [];
  else profile[key] = raw;
}
process.stdout.write(JSON.stringify(profile));
' "$@"
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

_ai_secret_id() {
  local tool="$1" profile_json="$2" secret_id name
  secret_id="$(_ai_profile_value "$profile_json" secret_id "")"
  if [ -n "$secret_id" ]; then
    printf '%s\n' "$secret_id"
  else
    name="$(_ai_profile_value "$profile_json" name "")"
    printf '%s.%s\n' "$tool" "$name"
  fi
}

_ai_toml_secret_exports() {
  local secret_id="$1"
  shift
  _ai_require_node || return 1
  [ -f "$AI_SECRETS_PATH" ] || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
const target = process.argv[2];
const allowed = new Set(process.argv.slice(3));
const quote = (value) => {
  const text = String(value);
  return "'"'"'" + text.replace(/'"'"'/g, "'"'"'\\'"'"''"'"'") + "'"'"'";
};
const parseValue = (raw) => {
  const value = String(raw || "").trim();
  if (value.startsWith("\"")) {
    const match = value.match(/^"((?:\\.|[^"])*)"/);
    if (match) {
      try { return JSON.parse(match[0]); } catch { return match[1]; }
    }
  }
  if (value.startsWith("'"'"'")) {
    const match = value.match(/^'"'"'([^'"'"']*)'"'"'/);
    if (match) return match[1];
  }
  const bare = value.replace(/\s+#.*$/, "").trim();
  if (bare === "true" || bare === "false") return bare;
  return bare;
};
let current = "";
const values = {};
for (const line of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) continue;
  const section = trimmed.match(/^\[([^\]]+)\]\s*$/);
  if (section) {
    current = section[1].trim();
    continue;
  }
  if (current !== target) continue;
  const item = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$/);
  if (!item || !allowed.has(item[1])) continue;
  const parsed = parseValue(item[2]);
  if (parsed !== "") values[item[1]] = parsed;
}
const entries = Object.entries(values);
if (!entries.length) process.exit(3);
for (const [key, value] of entries) console.log(`export ${key}=${quote(value)}`);
' "$AI_SECRETS_PATH" "$secret_id" "$@"
}

_ai_apply_toml_secret() {
  local secret_id="$1" exports
  shift
  exports="$(_ai_toml_secret_exports "$secret_id" "$@" 2>/dev/null)" || return 1
  [ -n "$exports" ] || return 1
  eval "$exports"
  AI_SECRET_SOURCE="${AI_SECRETS_PATH}#${secret_id}"
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
  sed -n \
    -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
    -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" \
    "$file" | head -n 1
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
  local profile_json="$1" profile_file provider model base_url wire_api env_key requires_openai_auth provider_name json
  local -a args
  command -v codex >/dev/null 2>&1 || return
  command -v node >/dev/null 2>&1 || {
    echo "  Doctor: unavailable (node not found for JSON parsing)"
    return
  }

  profile_file="$(_codex_profile_path "$profile_json")"
  provider="$(_ai_toml_value "$profile_file" model_provider)"
  model="$(_ai_toml_value "$profile_file" model)"
  base_url="$(_ai_toml_value "$profile_file" base_url)"
  wire_api="$(_ai_toml_value "$profile_file" wire_api)"
  env_key="$(_ai_toml_value "$profile_file" env_key)"
  requires_openai_auth="$(_ai_toml_value "$profile_file" requires_openai_auth)"
  provider_name="$(_ai_toml_value "$profile_file" name)"

  args=(doctor --json)
  [ -n "$model" ] && args+=(-c "model=\"$model\"")
  [ -n "$provider" ] && args+=(-c "model_provider=\"$provider\"")

  if [ -n "$provider" ]; then
    case "$provider" in
      openai|ollama|lmstudio|amazon-bedrock)
        [ -z "${base_url}${wire_api}${env_key}${requires_openai_auth}${provider_name}" ] && provider=""
        ;;
    esac

    if [ -n "$provider" ]; then
      [ -n "$provider_name" ] || provider_name="$provider"
      [ -n "$wire_api" ] || wire_api="responses"
      args+=(-c "model_providers.$provider.name=\"$provider_name\"")
      [ -n "$base_url" ] && args+=(-c "model_providers.$provider.base_url=\"$base_url\"")
      [ -n "$wire_api" ] && args+=(-c "model_providers.$provider.wire_api=\"$wire_api\"")
      [ -n "$env_key" ] && args+=(-c "model_providers.$provider.env_key=\"$env_key\"")
      [ -n "$requires_openai_auth" ] && args+=(-c "model_providers.$provider.requires_openai_auth=$requires_openai_auth")
    fi
  fi

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
  local profile_json="$1" mode name secret secret_id legacy legacy_key
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
    secret_id="$(_ai_secret_id codex "$profile_json")"
    if _ai_apply_toml_secret "$secret_id" OPENAI_API_KEY CODEX_API_KEY; then
      :
    elif [ -f "$secret" ]; then
      # shellcheck source=/dev/null
      . "$secret"
      AI_SECRET_SOURCE="$secret"
    fi

    if [ -z "${OPENAI_API_KEY:-}" ] && [ -n "${CODEX_API_KEY:-}" ]; then
      export OPENAI_API_KEY="$CODEX_API_KEY"
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
      echo "cx $name needs OPENAI_API_KEY. Put it in ${AI_SECRETS_PATH} [${secret_id}] or $secret." >&2
      return 1
    fi
  fi
}

_set_claude_env() {
  local profile_json="$1" mode name secret secret_id base_url
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
    secret_id="$(_ai_secret_id claude "$profile_json")"
    if _ai_apply_toml_secret "$secret_id" ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL; then
      :
    elif [ -f "$secret" ]; then
      # shellcheck source=/dev/null
      . "$secret"
      AI_SECRET_SOURCE="$secret"
    fi

    base_url="$(_ai_profile_value "$profile_json" base_url "$CLAUDE_ROUTER_BASE_URL")"
    [ -n "${ANTHROPIC_BASE_URL:-}" ] || export ANTHROPIC_BASE_URL="$base_url"

    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
      echo "cc $name needs ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN in ${AI_SECRETS_PATH} [${secret_id}] or $secret." >&2
      return 1
    fi
  fi
}

_cx_write_config_if_missing() {
  local profile_json="$1" base_url="${2:-}" model="${3:-gpt-5.5}" mode name profile_file provider display_name
  mode="$(_ai_profile_value "$profile_json" mode sub)"
  name="$(_ai_profile_value "$profile_json" name "")"
  profile_file="$(_codex_profile_path "$profile_json")"
  [ -f "$profile_file" ] && { printf '%s\n' "$profile_file"; return 0; }
  mkdir -p "$(dirname "$profile_file")"
  provider="$(_codex_profile_name "$profile_json")"
  display_name="${name//:/ }"

  if [ "$mode" = "api" ]; then
    [ -n "$base_url" ] || base_url="https://your-router.example/v1"
    cat >"$profile_file" <<EOF
model_provider = "$provider"
model = "$model"
disable_response_storage = true

[model_providers.$provider]
name = "$display_name"
base_url = "$base_url"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
EOF
  else
    cat >"$profile_file" <<EOF
model_provider = "openai"
model = "$model"
EOF
  fi

  printf '%s\n' "$profile_file"
}

_cx_add_api() {
  local parsed name slug home runtime_profile secret_id base_url model profile_json profile_file
  parsed="$(_ai_parse_management_args "$@")" || return
  name="$(_ai_mgmt_positional "$parsed" 0)"
  [ -n "$name" ] || { echo "Usage: cx add-api <name> [--base-url URL] [--model MODEL] [--home PATH]" >&2; return 1; }
  _ai_validate_name "$name" || return
  slug="$(_ai_name_slug "$name")" || return
  home="$(_ai_mgmt_value "$parsed" home "~/.codex")"
  runtime_profile="$(_ai_mgmt_value "$parsed" profile "api-${slug//:/-}")"
  secret_id="$(_ai_mgmt_value "$parsed" secret-id "codex.$name")"
  base_url="$(_ai_mgmt_value "$parsed" base-url "https://your-router.example/v1")"
  model="$(_ai_mgmt_value "$parsed" model "gpt-5.5")"
  profile_json="$(_ai_json_profile \
    name "$name" aliases "" mode api home "$home" codex_profile "$runtime_profile" \
    secret_id "$secret_id" linux_secret "~/.ai-secrets/codex-$slug.env" windows_secret "~/.ai-secrets/codex-$slug.ps1" \
    description "Codex API profile")"
  _ai_registry_add_profile codex "$profile_json" || return
  profile_file="$(_cx_write_config_if_missing "$profile_json" "$base_url" "$model")"
  echo "Added Codex API profile '$name'."
  echo "  Registry: $AI_REGISTRY_PATH"
  echo "  CODEX_HOME: $(_ai_expand_path "$home")"
  echo "  Config: $profile_file"
  echo "  Secret: $AI_SECRETS_PATH [$secret_id] with OPENAI_API_KEY"
}

_cx_add_sub() {
  local parsed name slug home runtime_profile model profile_json profile_file
  parsed="$(_ai_parse_management_args "$@")" || return
  name="$(_ai_mgmt_positional "$parsed" 0)"
  [ -n "$name" ] || { echo "Usage: cx add-sub <name> [--home PATH] [--model MODEL]" >&2; return 1; }
  _ai_validate_name "$name" || return
  slug="$(_ai_name_slug "$name")" || return
  home="$(_ai_mgmt_value "$parsed" home "~/.codex-$slug")"
  runtime_profile="$(_ai_mgmt_value "$parsed" profile "sub")"
  model="$(_ai_mgmt_value "$parsed" model "gpt-5.5")"
  profile_json="$(_ai_json_profile \
    name "$name" aliases "" mode sub home "$home" codex_profile "$runtime_profile" \
    description "Codex subscription profile")"
  _ai_registry_add_profile codex "$profile_json" || return
  profile_file="$(_cx_write_config_if_missing "$profile_json" "" "$model")"
  echo "Added Codex subscription profile '$name'."
  echo "  Registry: $AI_REGISTRY_PATH"
  echo "  CODEX_HOME: $(_ai_expand_path "$home")"
  echo "  Config: $profile_file"
  echo "  Login: CODEX_HOME=\"$(_ai_expand_path "$home")\" codex login"
}

_cx_remove_profile() {
  local parsed name removed existing_json profile_file delete_config
  parsed="$(_ai_parse_management_args "$@")" || return
  name="$(_ai_mgmt_positional "$parsed" 0)"
  [ -n "$name" ] || { echo "Usage: cx remove <name> [--delete-config]" >&2; return 1; }
  existing_json="$(_ai_profile_json codex "$name")" || { echo "codex profile '$name' does not exist." >&2; return 1; }
  profile_file="$(_codex_profile_path "$existing_json")"
  removed="$(_ai_registry_remove_profile codex "$name")" || return
  if [ "$(_ai_saved_profile codex)" = "$removed" ]; then
    _ai_save_profile codex "$(_ai_default_profile codex)" || return
  fi
  delete_config="$(_ai_mgmt_value "$parsed" delete-config "")"
  [ "$delete_config" = "true" ] && rm -f "$profile_file"
  echo "Removed Codex profile '$removed'."
  echo "  Registry: $AI_REGISTRY_PATH"
  if [ -f "$profile_file" ]; then
    echo "  Config: $profile_file"
  else
    echo "  Config: <removed or absent>"
  fi
}

_cc_add_api() {
  local parsed name slug secret_id base_url profile_json
  parsed="$(_ai_parse_management_args "$@")" || return
  name="$(_ai_mgmt_positional "$parsed" 0)"
  [ -n "$name" ] || { echo "Usage: cc add-api <name> [--base-url URL]" >&2; return 1; }
  _ai_validate_name "$name" || return
  slug="$(_ai_name_slug "$name")" || return
  secret_id="$(_ai_mgmt_value "$parsed" secret-id "claude.$name")"
  base_url="$(_ai_mgmt_value "$parsed" base-url "$CLAUDE_ROUTER_BASE_URL")"
  profile_json="$(_ai_json_profile \
    name "$name" aliases "" mode api base_url "$base_url" secret_id "$secret_id" \
    linux_secret "~/.ai-secrets/claude-$slug.env" windows_secret "~/.ai-secrets/claude-$slug.ps1" \
    description "Claude Code API profile")"
  _ai_registry_add_profile claude "$profile_json" || return
  echo "Added Claude Code API profile '$name'."
  echo "  Registry: $AI_REGISTRY_PATH"
  echo "  Base URL: $base_url"
  echo "  Secret: $AI_SECRETS_PATH [$secret_id] with ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN"
}

_cc_add_sub() {
  local parsed name profile_json
  parsed="$(_ai_parse_management_args "$@")" || return
  name="$(_ai_mgmt_positional "$parsed" 0)"
  [ -n "$name" ] || { echo "Usage: cc add-sub <name>" >&2; return 1; }
  _ai_validate_name "$name" || return
  profile_json="$(_ai_json_profile name "$name" aliases "" mode sub description "Claude Code subscription profile")"
  _ai_registry_add_profile claude "$profile_json" || return
  echo "Added Claude Code subscription profile '$name'."
  echo "  Registry: $AI_REGISTRY_PATH"
  echo "  Login: claude /login"
}

_cc_remove_profile() {
  local parsed name removed
  parsed="$(_ai_parse_management_args "$@")" || return
  name="$(_ai_mgmt_positional "$parsed" 0)"
  [ -n "$name" ] || { echo "Usage: cc remove <name>" >&2; return 1; }
  removed="$(_ai_registry_remove_profile claude "$name")" || return
  if [ "$(_ai_saved_profile claude)" = "$removed" ]; then
    _ai_save_profile claude "$(_ai_default_profile claude)" || return
  fi
  echo "Removed Claude Code profile '$removed'."
  echo "  Registry: $AI_REGISTRY_PATH"
}

_ai_token_format() {
  node -e '
const value = Number(process.argv[1] || 0);
if (value >= 1000000) process.stdout.write(`${(value / 1000000).toFixed(2)}M`);
else if (value >= 1000) process.stdout.write(`${(value / 1000).toFixed(1)}K`);
else process.stdout.write(String(value));
' "$1"
}

_ai_token_bar() {
  node -e '
const value = Number(process.argv[1] || 0);
const total = Number(process.argv[2] || 0);
if (value <= 0 || total <= 0) process.exit(0);
const width = Math.max(1, Math.round((value / total) * 24));
process.stdout.write("#".repeat(width));
' "$1" "$2"
}

_cx_rollout_stats_json() {
  local codex_home="$1" days="$2"
  _ai_require_node || return 1
  node -e '
const fs = require("fs");
const path = require("path");
const root = process.argv[1];
const days = Number(process.argv[2] || 30);
const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
const stats = { sessions: 0, samples: 0, input: 0, cachedInput: 0, output: 0, reasoningOutput: 0, total: 0 };
const sessions = path.join(root, "sessions");
const walk = (dir) => {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.isFile() && entry.name.endsWith(".jsonl")) out.push(full);
  }
  return out;
};
for (const file of walk(sessions)) {
  let st;
  try { st = fs.statSync(file); } catch { continue; }
  if (st.mtimeMs < cutoff) continue;
  let latest = null;
  let samples = 0;
  let text = "";
  try { text = fs.readFileSync(file, "utf8"); } catch { continue; }
  for (const line of text.split(/\r?\n/)) {
    if (!line.includes("\"token_count\"")) continue;
    try {
      const j = JSON.parse(line);
      if (j.type !== "event_msg" || !j.payload || j.payload.type !== "token_count") continue;
      const usage = j.payload.info && j.payload.info.total_token_usage;
      if (!usage) continue;
      latest = usage;
      samples += 1;
    } catch {}
  }
  if (!latest) continue;
  const input = Number(latest.input_tokens || 0);
  const cached = Number(latest.cached_input_tokens || latest.cache_read_input_tokens || 0);
  const output = Number(latest.output_tokens || 0);
  const reasoning = Number(latest.reasoning_output_tokens || 0);
  const total = Number(latest.total_tokens || input + output);
  stats.sessions += 1;
  stats.samples += samples;
  stats.input += input;
  stats.cachedInput += cached;
  stats.output += output;
  stats.reasoningOutput += reasoning;
  stats.total += total;
}
process.stdout.write(JSON.stringify(stats));
' "$codex_home" "$days"
}

_cx_stats() {
  local parsed days saved profile_json codex_home json sessions samples total input cached output reasoning
  parsed="$(_ai_parse_management_args "$@")" || return
  days="$(_ai_mgmt_value "$parsed" days 30)"
  case "$days" in
    ''|*[!0-9]*)
      echo "cx stats --days must be a positive integer." >&2
      return 1
      ;;
  esac
  [ "$days" -ge 1 ] || { echo "cx stats --days must be a positive integer." >&2; return 1; }
  saved="$(_ai_saved_profile codex)"
  profile_json="$(_ai_profile_json codex "${AI_CODEX_LABEL:-$saved}")" || profile_json="$(_ai_profile_json codex "$(_ai_default_profile codex)")" || return 1
  codex_home="${CODEX_HOME:-$(_codex_home "$profile_json")}"
  json="$(_cx_rollout_stats_json "$codex_home" "$days")" || return
  sessions="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.sessions));' "$json")"
  samples="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.samples));' "$json")"
  total="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.total));' "$json")"
  input="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.input));' "$json")"
  cached="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.cachedInput));' "$json")"
  output="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.output));' "$json")"
  reasoning="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.reasoningOutput));' "$json")"
  echo "Codex local token stats:"
  echo "  CODEX_HOME: $codex_home"
  echo "  Window: last $days days"
  echo "  Sessions with usage: $sessions"
  echo "  Token samples: $samples"
  echo "  Total: $(_ai_token_format "$total") ($total)"
  printf '  %-9s %10s  %s\n' input "$(_ai_token_format "$input")" "$(_ai_token_bar "$input" "$total")"
  printf '  %-9s %10s  %s\n' cached "$(_ai_token_format "$cached")" "$(_ai_token_bar "$cached" "$total")"
  printf '  %-9s %10s  %s\n' output "$(_ai_token_format "$output")" "$(_ai_token_bar "$output" "$total")"
  printf '  %-9s %10s  %s\n' reasoning "$(_ai_token_format "$reasoning")" "$(_ai_token_bar "$reasoning" "$total")"
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
  local tool="$1" output
  _ai_require_node || return 1
  output="$(node -e '
const fs = require("fs");
const path = process.argv[1];
const tool = process.argv[2];
const saved = process.argv[3];
const secretsPath = process.argv[4];
const home = process.env.HOME;
const exists = (p) => p && fs.existsSync(p);
const expand = (p) => !p ? "" : p.replace(/^~(?=\/|$)/, home);
const parseValue = (raw) => {
  const value = String(raw || "").trim();
  if (value.startsWith("\"")) {
    const match = value.match(/^"((?:\\.|[^"])*)"/);
    if (match) {
      try { return JSON.parse(match[0]); } catch { return match[1]; }
    }
  }
  if (value.startsWith("'"'"'")) {
    const match = value.match(/^'"'"'([^'"'"']*)'"'"'/);
    if (match) return match[1];
  }
  return value.replace(/\s+#.*$/, "").trim();
};
const parseSecrets = (file) => {
  const sections = {};
  if (!fs.existsSync(file)) return sections;
  let current = "";
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const section = trimmed.match(/^\[([^\]]+)\]\s*$/);
    if (section) {
      current = section[1].trim();
      sections[current] = sections[current] || {};
      continue;
    }
    if (!current) continue;
    const item = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$/);
    if (item) sections[current][item[1]] = parseValue(item[2]);
  }
  return sections;
};
let registry = JSON.parse(fs.readFileSync(path, "utf8"));
const secrets = parseSecrets(secretsPath);
const secretVars = tool === "codex" ? ["OPENAI_API_KEY", "CODEX_API_KEY"] : ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"];
console.log(["Sel", "Name", "Mode", "Ready", "Runtime", "Secret", "Description"].join("\t"));
for (const p of registry[tool] || []) {
  const mode = p.mode || "sub";
  const runtime = tool === "codex" ? `${expand(p.home || "~/.codex")}/${p.codex_profile || p.profile || String(p.name || "").replace(":", "-")}.config.toml` : (p.base_url || "local subscription");
  const secretId = p.secret_id || `${tool}.${p.name || ""}`;
  const tomlReady = mode !== "api" || secretVars.some((name) => secrets[secretId] && secrets[secretId][name]);
  const legacy = expand(p.linux_secret || p.secret || "");
  const legacyReady = mode !== "api" || exists(legacy);
  const secret = mode === "api"
    ? (tomlReady ? `${secretsPath}#${secretId}` : (legacy ? (legacyReady ? legacy : `<missing> ${legacy}`) : `<missing> ${secretsPath}#${secretId}`))
    : "<none>";
  const configOk = tool !== "codex" || exists(runtime);
  const secretOk = mode !== "api" || tomlReady || legacyReady;
  const ready = tool === "codex" && mode === "sub" && !configOk ? "ok-default" : (configOk && secretOk ? "ok" : (!configOk ? "missing-config" : "missing-secret"));
  const selected = String(p.name || "") === saved ? "*" : " ";
  console.log([selected, p.name || "", mode, ready, runtime, secret || "<missing>", p.description || ""].join("\t"));
}
' "$AI_REGISTRY_PATH" "$tool" "$(_ai_saved_profile "$tool")" "$AI_SECRETS_PATH")" || return 1

  if command -v column >/dev/null 2>&1; then
    printf '%s\n' "$output" | column -t -s "$(printf '\t')"
  else
    printf '%s\n' "$output"
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
  cx stats           Summarize local rollout token usage
  cx add-api NAME    Register a Codex API profile that shares ~/.codex by default
  cx add-sub NAME    Register an isolated Codex subscription CODEX_HOME
  cx remove NAME     Remove a Codex profile registration
  cx help            Show this help

Config:
  Registry: ~/.ai-env/profiles.json
  State:    ~/.ai-env/state.json
  Secrets:  ~/.ai-secrets/secrets.toml

After switching, run Codex separately: codex
Add commands only write profile metadata and Codex config. Put real tokens in secrets.toml.
Legacy ~/.ai-secrets/*.env files are still accepted as a fallback.
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
    stats)
      shift
      _cx_stats "$@"
      return
      ;;
    add-api)
      shift
      _cx_add_api "$@"
      return
      ;;
    add-sub)
      shift
      _cx_add_sub "$@"
      return
      ;;
    remove)
      shift
      _cx_remove_profile "$@"
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
  cc add-api NAME    Register a Claude Code API profile
  cc add-sub NAME    Register a Claude Code subscription label
  cc remove NAME     Remove a Claude Code profile registration
  cc help            Show this help

Config:
  Registry: ~/.ai-env/profiles.json
  State:    ~/.ai-env/state.json
  Secrets:  ~/.ai-secrets/secrets.toml

After switching, run Claude Code separately: claude
Add commands only write profile metadata. Put real tokens in secrets.toml.
Legacy ~/.ai-secrets/*.env files are still accepted as a fallback.
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
    add-api)
      shift
      _cc_add_api "$@"
      return
      ;;
    add-sub)
      shift
      _cc_add_sub "$@"
      return
      ;;
    remove)
      shift
      _cc_remove_profile "$@"
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
