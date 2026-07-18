#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_VERSION="v0.1.0"
EXPECTED_COMMIT="dfc0bd6ef4b6aafdafff5f6d732e28cc52cfcfc0"
EXPECTED_INSTALLER_SHA256="ce6e0712c6a2c0439c334bf849b71fe618a6c296477bc25a447ede47f07e4eb7"
EXPECTED_ARTIFACT_SHA256="6ac428ce3002d6e7be8f92b26b69c172380363cdfeb8f588278f7577d06958bd"
INSTALLER="$REPO_ROOT/scripts/install/cxcc.sh"
HOOK="$REPO_ROOT/run_before_10-install-cxcc.sh.tmpl"
DATA_FILE="$REPO_ROOT/.chezmoidata.toml"
ZSHRC="$REPO_ROOT/dot_zshrc"
FULL_SMOKE="$REPO_ROOT/test/smoke.sh"

fail() {
  echo "$*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail "A SHA-256 tool is required for the cxcc consumer smoke."
  fi
}

for required in "$INSTALLER" "$HOOK" "$DATA_FILE" "$ZSHRC"; do
  [ -f "$required" ] || fail "Missing cxcc consumer file: $required"
done

grep -Eq '^version = "v0\.1\.0"$' "$DATA_FILE" || fail "dotfiles does not pin cxcc v0.1.0."
grep -Fq "$EXPECTED_COMMIT" "$DATA_FILE" || fail "dotfiles does not pin an immutable cxcc commit."
grep -Fq "$EXPECTED_INSTALLER_SHA256" "$DATA_FILE" || fail "dotfiles does not pin the Shell installer digest."
grep -Fq "$EXPECTED_ARTIFACT_SHA256" "$DATA_FILE" || fail "dotfiles does not pin the POSIX artifact digest."
grep -Fq 'scripts/install/cxcc.sh' "$HOOK" || fail "Shell hook does not invoke the cxcc consumer installer."
grep -Fq '.cxcc.version' "$HOOK" || fail "Shell hook does not use the shared cxcc version pin."
grep -Fq '.cxcc.commit' "$HOOK" || fail "Shell hook does not use the immutable cxcc commit pin."
grep -Fq '.cxcc.installerShellSha256' "$HOOK" || fail "Shell hook does not use the installer digest pin."
grep -Fq '.cxcc.posixArtifactSha256' "$HOOK" || fail "Shell hook does not use the artifact digest pin."
grep -Fq -- '--connect-timeout' "$INSTALLER" || fail "Shell consumer download has no connection timeout."
grep -Fq -- '--max-time' "$INSTALLER" || fail "Shell consumer download has no total timeout."
grep -Fq -- '--ipv4' "$INSTALLER" || fail "Shell consumer download has no IPv4 fallback."
grep -Fq 'INSTALL_CXCC' "$FULL_SMOKE" || fail "Full smoke does not honor INSTALL_CXCC=0."
grep -Fq 'CXCC_HOME' "$ZSHRC" || fail "Zsh profile does not honor CXCC_HOME."
grep -Fq '/load.sh' "$ZSHRC" || fail "Zsh profile does not load the stable cxcc loader."
! grep -Fq '.local/share/ai-env/ai-env.sh' "$ZSHRC" || fail "Zsh profile still loads the legacy ai-env implementation."

legacy_paths=(
  'Documents/PowerShell/Scripts/ai-env.ps1'
  'dot_local/share/ai-env/ai-env.sh'
  'dot_local/share/ai-env/ai-health.mjs'
  'tools/codex-provider-bridge/ChildProcessJob.cs'
  'tools/codex-provider-bridge/CodexProviderBridge.csproj'
  'tools/codex-provider-bridge/Program.cs'
)
for legacy_path in "${legacy_paths[@]}"; do
  if [ -e "$REPO_ROOT/$legacy_path" ] && git -C "$REPO_ROOT" ls-files --error-unmatch -- "$legacy_path" >/dev/null 2>&1; then
    fail "Legacy cxcc implementation is still tracked: $legacy_path"
  fi
done

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
test_home="$tmp_root/home"
install_root="$test_home/.local/share/cxcc"
fake_bin="$tmp_root/bin"
curl_log="$tmp_root/curl.log"
install_log="$tmp_root/install.log"
fake_installer_source="$tmp_root/fake-install.sh"
mkdir -p "$fake_bin" "$test_home/.ai-env" "$test_home/.ai-secrets" "$test_home/.codex" "$test_home/.claude"

printf '{"sentinel":"profiles"}\n' >"$test_home/.ai-env/profiles.json"
printf '{"sentinel":"state"}\n' >"$test_home/.ai-env/state.json"
printf '[mcp.sentinel]\nenabled = false\n' >"$test_home/.ai-env/mcp.toml"
printf '[codex.sentinel]\nOPENAI_API_KEY = "keep"\n' >"$test_home/.ai-secrets/secrets.toml"
printf '{"sentinel":"auth"}\n' >"$test_home/.codex/auth.json"
printf '{"sentinel":"credentials"}\n' >"$test_home/.claude/.credentials.json"

state_paths=(
  "$test_home/.ai-env/profiles.json"
  "$test_home/.ai-env/state.json"
  "$test_home/.ai-env/mcp.toml"
  "$test_home/.ai-secrets/secrets.toml"
  "$test_home/.codex/auth.json"
  "$test_home/.claude/.credentials.json"
)
state_hashes=()
for state_path in "${state_paths[@]}"; do
  state_hashes+=("$(sha256_file "$state_path")")
done

cat >"$fake_installer_source" <<'FAKE_INSTALLER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$CXCC_TEST_INSTALL_LOG"
version=""
artifact=""
sha256=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --artifact) artifact="$2"; shift 2 ;;
    --sha256) sha256="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$version" = "v0.1.0" ]
[ -f "$artifact" ]
root="$CXCC_HOME"
mkdir -p \
  "$root/versions/$version/src/powershell/CxCc" \
  "$root/versions/$version/src/shell" \
  "$root/versions/$version/src/bridge/CodexProviderBridge" \
  "$root/versions/$version/templates"
printf 'cxcc-install-root-v1\n' >"$root/.cxcc-root"
printf '%s' "$version" >"$root/versions/$version/VERSION"
printf '%s\n' "$sha256" >"$root/versions/$version/.artifact-sha256"
for relative_path in \
  load.ps1 load.sh \
  src/powershell/CxCc/CxCc.ps1 \
  src/shell/cxcc.sh src/shell/ai-health.mjs \
  src/bridge/CodexProviderBridge/CodexProviderBridge.csproj \
  templates/profiles.json; do
  printf '# fake payload\n' >"$root/versions/$version/$relative_path"
done
printf '{"schema":1,"version":"%s","previous":null}\n' "$version" >"$root/current.json"
cat >"$root/load.sh" <<'FAKE_LOADER'
CXCC_CONSUMER_TEST_LOADER_COUNT=$((${CXCC_CONSUMER_TEST_LOADER_COUNT:-0} + 1))
cx() { :; }
cc() { :; }
mcp() { :; }
FAKE_LOADER
printf '# fake PowerShell loader\n' >"$root/load.ps1"
FAKE_INSTALLER
chmod 755 "$fake_installer_source"
test_commit="1111111111111111111111111111111111111111"
test_installer_sha256="$(sha256_file "$fake_installer_source")"
test_artifact_sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

cat >"$fake_bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[ -n "$output" ] && [ -n "$url" ]
printf '%s\n' "$url" >>"$CXCC_TEST_CURL_LOG"
case "$url" in
  */install.sh) cp "$CXCC_TEST_INSTALLER_SOURCE" "$output" ;;
  *) printf 'fake artifact\n' >"$output" ;;
esac
FAKE_CURL
chmod 755 "$fake_bin/curl"

assert_state_preserved() {
  local index actual
  for index in "${!state_paths[@]}"; do
    actual="$(sha256_file "${state_paths[$index]}")"
    [ "$actual" = "${state_hashes[$index]}" ] || fail "cxcc consumer changed user state: ${state_paths[$index]}"
  done
}

run_installer() {
  HOME="$test_home" \
  CXCC_HOME="$install_root" \
  CXCC_TEST_CURL_LOG="$curl_log" \
  CXCC_TEST_INSTALL_LOG="$install_log" \
  CXCC_TEST_INSTALLER_SOURCE="$fake_installer_source" \
  PATH="$fake_bin:$PATH" \
  bash "$INSTALLER" "$EXPECTED_VERSION" "$test_commit" "$test_installer_sha256" "$test_artifact_sha256"
}

run_installer
[ "$(sed -n '1p' "$curl_log")" = "https://raw.githubusercontent.com/Tim-1e/cxcc/$test_commit/install.sh" ] || fail "Shell consumer used a mutable installer URL."
[ "$(sed -n '2p' "$curl_log")" = "https://github.com/Tim-1e/cxcc/releases/download/$EXPECTED_VERSION/cxcc-$EXPECTED_VERSION-posix.tar.gz" ] || fail "Shell consumer used an unexpected artifact URL."
grep -Eq "^--version $EXPECTED_VERSION --artifact .*/cxcc-$EXPECTED_VERSION-posix\.tar\.gz --sha256 $test_artifact_sha256$" "$install_log" || fail "Shell consumer passed unexpected installer arguments."
grep -Fq '"schema":1' "$install_root/current.json" || fail "Shell consumer current.json schema is invalid."
grep -Fq '"version":"v0.1.0"' "$install_root/current.json" || fail "Shell consumer installed the wrong version."
[ "$(cat "$install_root/versions/$EXPECTED_VERSION/VERSION")" = "$EXPECTED_VERSION" ] || fail "Shell consumer payload VERSION is invalid."
assert_state_preserved

run_installer
[ "$(wc -l <"$curl_log" | tr -d ' ')" = "2" ] || fail "Repeated Shell apply downloaded cxcc again."
assert_state_preserved

rm "$install_root/versions/$EXPECTED_VERSION/src/shell/cxcc.sh"
run_installer
[ "$(wc -l <"$curl_log" | tr -d ' ')" = "4" ] || fail "Shell consumer ignored a damaged cxcc payload."
assert_state_preserved

rm -rf "$install_root"
INSTALL_CXCC=0 run_installer
[ ! -e "$install_root" ] || fail "INSTALL_CXCC=0 created an install root."
[ "$(wc -l <"$curl_log" | tr -d ' ')" = "4" ] || fail "INSTALL_CXCC=0 accessed the network."
assert_state_preserved

if HOME="$test_home" CXCC_HOME="$install_root" PATH="$fake_bin:$PATH" bash "$INSTALLER" main "$test_commit" "$test_installer_sha256" "$test_artifact_sha256" >/dev/null 2>&1; then
  fail "Shell consumer accepted an unpinned version."
fi

if HOME="$test_home" \
  CXCC_HOME="$test_home/bad/cxcc" \
  CXCC_TEST_CURL_LOG="$curl_log" \
  CXCC_TEST_INSTALL_LOG="$install_log" \
  CXCC_TEST_INSTALLER_SOURCE="$fake_installer_source" \
  PATH="$fake_bin:$PATH" \
  bash "$INSTALLER" "$EXPECTED_VERSION" "$test_commit" "$(printf '%064d' 0)" "$test_artifact_sha256" >/dev/null 2>&1; then
  fail "Shell consumer executed an installer with the wrong checksum."
fi
[ "$(wc -l <"$curl_log" | tr -d ' ')" = "5" ] || fail "Shell checksum failure downloaded an artifact or retried unexpectedly."
[ "$(wc -l <"$install_log" | tr -d ' ')" = "2" ] || fail "Shell checksum failure executed the installer."

if command -v zsh >/dev/null 2>&1; then
  mkdir -p "$install_root"
  cat >"$install_root/load.sh" <<'FAKE_ZSH_LOADER'
CXCC_CONSUMER_TEST_LOADER_COUNT=$((${CXCC_CONSUMER_TEST_LOADER_COUNT:-0} + 1))
cx() { :; }
cc() { :; }
mcp() { :; }
FAKE_ZSH_LOADER
  HOME="$test_home" CXCC_HOME="$install_root" zsh -f -c '
    source "$1" >/dev/null 2>&1
    [ "$CXCC_CONSUMER_TEST_LOADER_COUNT" = "1" ]
    whence -w cx | grep -q function
    whence -w cc | grep -q function
    whence -w mcp | grep -q function
  ' _ "$ZSHRC"
fi

echo "cxcc Shell consumer smoke passed."
