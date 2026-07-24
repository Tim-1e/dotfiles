#!/usr/bin/env bash

set -Eeuo pipefail

repository="Tim-1e/cxcc"
version_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
version="${1:-}"
commit="${2:-}"
installer_sha256="${3:-}"
artifact_sha256="${4:-}"

fail() {
  echo "$*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print tolower($1)}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print tolower($1)}'
  else
    fail "A SHA-256 tool is required to install cxcc."
  fi
}

[[ "$version" =~ $version_pattern ]] || fail "cxcc version must be an exact release tag such as v0.1.0."
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail "cxcc commit must be a full lowercase Git SHA."
[[ "$installer_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "cxcc installer SHA-256 pin must contain 64 lowercase hexadecimal characters."
[[ "$artifact_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "cxcc artifact SHA-256 pin must contain 64 lowercase hexadecimal characters."

case "${INSTALL_CXCC-}" in
  1)
    should_install=1
    ;;
  0)
    should_install=0
    ;;
  "")
    should_install=0
    if [ -t 0 ] && [ -t 1 ]; then
      printf 'Install the cx/cc environment? [y/N] '
      IFS= read -r answer || answer=""
      case "$answer" in
        [Yy] | [Yy][Ee][Ss]) should_install=1 ;;
      esac
    fi
    ;;
  *)
    fail "INSTALL_CXCC must be 0 or 1."
    ;;
esac

if [ "$should_install" != "1" ]; then
  echo "Skipping cxcc installation. Set INSTALL_CXCC=1 to install it."
  exit 0
fi

install_root="${CXCC_HOME:-$HOME/.local/share/cxcc}"

is_current() {
  local relative_path version_root="$install_root/versions/$version"
  for relative_path in \
    .cxcc-root current.json load.sh load.ps1 \
    "versions/$version/VERSION" "versions/$version/.artifact-sha256" \
    "versions/$version/load.ps1" "versions/$version/load.sh" \
    "versions/$version/src/powershell/CxCc/CxCc.ps1" \
    "versions/$version/src/shell/cxcc.sh" \
    "versions/$version/src/shell/ai-health.mjs" \
    "versions/$version/src/bridge/CodexProviderBridge/CodexProviderBridge.csproj" \
    "versions/$version/templates/profiles.json"; do
    [ -f "$install_root/$relative_path" ] || return 1
  done
  [ "$(cat "$install_root/.cxcc-root")" = "cxcc-install-root-v1" ] &&
    grep -Fq '"schema":1' "$install_root/current.json" &&
    grep -Fq "\"version\":\"$version\"" "$install_root/current.json" &&
    [ "$(cat "$version_root/VERSION")" = "$version" ] &&
    [ "$(tr -d '\r\n' <"$version_root/.artifact-sha256")" = "$artifact_sha256" ]
}

if is_current; then
  echo "cxcc $version is already installed."
  exit 0
fi

download_root="$(mktemp -d)"
installer="$download_root/install.sh"
artifact_name="cxcc-$version-posix.tar.gz"
artifact="$download_root/$artifact_name"
cleanup() {
  rm -rf "$download_root"
}
trap cleanup EXIT

download_file() {
  local url="$1" destination="$2"
  if command -v curl >/dev/null 2>&1; then
    local curl_args=(--fail --silent --show-error --location --connect-timeout 15 --max-time 120 --retry 2)
    if ! curl "${curl_args[@]}" --output "$destination" "$url"; then
      echo "Retrying the cxcc download over IPv4." >&2
      curl --ipv4 "${curl_args[@]}" --output "$destination" "$url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q -T 30 -t 2 -O "$destination" "$url"; then
      echo "Retrying the cxcc download over IPv4." >&2
      wget -4 -q -T 30 -t 2 -O "$destination" "$url"
    fi
  else
    fail "curl or wget is required to install cxcc."
  fi
}

download_file "https://raw.githubusercontent.com/$repository/$commit/install.sh" "$installer"
actual_installer_sha256="$(sha256_file "$installer")"
[ "$actual_installer_sha256" = "$installer_sha256" ] || fail "cxcc installer checksum mismatch. Expected $installer_sha256, got $actual_installer_sha256."
download_file "https://github.com/$repository/releases/download/$version/$artifact_name" "$artifact"
bash "$installer" --version "$version" --artifact "$artifact" --sha256 "$artifact_sha256"
