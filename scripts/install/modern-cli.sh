#!/usr/bin/env bash

# Modern, lightweight CLI tools — installed USER-LEVEL into ~/.local/bin (no
# root/sudo). Mirrors the install_user_fzf / install_user_eza pattern: download
# a prebuilt release binary from GitHub and drop it in ~/.local/bin.
#
# Every tool is best-effort: a download/extract failure prints a "Skipping …"
# and never aborts the install (so a flaky network or rate-limit can't break a
# whole `chezmoi apply`). Already-present commands are left untouched.
#
# Set INSTALL_MODERN_CLI=0 to skip this layer entirely.

# Resolve architecture tokens for the various release naming schemes.
# Returns non-zero on an unsupported architecture.
_mcli_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      _MA_MUSL="x86_64-unknown-linux-musl"  # rust tools (rg/fd/delta/dust/sd/xh/btop)
      _MA_RAW="amd64"                        # jq/yq single binary
      _MA_X="x86_64"                         # bare x86_64 (tealdeer/duf)
      _MA_LINUXX="x86_64-linux"              # procs zip
      _MA_GPING="x86_64"                     # gping
      ;;
    aarch64|arm64)
      _MA_MUSL="aarch64-unknown-linux-musl"
      _MA_RAW="arm64"
      _MA_X="aarch64"
      _MA_LINUXX="aarch64-linux"
      _MA_GPING="arm64"
      ;;
    *)
      return 1
      ;;
  esac
}

# Echo the latest release tag (e.g. v1.2.3 or 14.1.1) for OWNER/REPO using the
# /releases/latest redirect — this hits github.com (not api.github.com), so it
# avoids the 60/hour anonymous API rate limit. Returns non-zero if unresolved.
_mcli_tag() {
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null || true)"
  case "$url" in
    */tag/*) printf '%s' "${url##*/tag/}" ;;
    *) return 1 ;;
  esac
}

# Write a tiny pure-Node single-entry zip extractor to a temp file and echo its
# path. Used as a fallback when `unzip` is absent (common in minimal/no-root
# images) — node is always available in this stack. Reads the central
# directory, finds the entry whose basename matches, inflates it (method 0/8).
_mcli_make_unzip_helper() {
  local f
  f="$(mktemp --suffix=.mjs)" || return 1
  cat > "$f" <<'EOF'
import fs from 'fs';
import zlib from 'zlib';
const [zip, want, dest] = process.argv.slice(2);
const buf = fs.readFileSync(zip);
let i = buf.length - 22;
for (; i >= 0; i--) if (buf.readUInt32LE(i) === 0x06054b50) break;
if (i < 0) { console.error('no EOCD'); process.exit(1); }
const cdOffset = buf.readUInt32LE(i + 16), cdCount = buf.readUInt16LE(i + 10);
let p = cdOffset;
for (let n = 0; n < cdCount && p + 46 <= buf.length; n++) {
  if (buf.readUInt32LE(p) !== 0x02014b50) break;
  const method = buf.readUInt16LE(p + 10);
  const compSize = buf.readUInt32LE(p + 20);
  const nameLen = buf.readUInt16LE(p + 28);
  const extraLen = buf.readUInt16LE(p + 30);
  const commLen = buf.readUInt16LE(p + 32);
  const lho = buf.readUInt32LE(p + 42);
  const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
  if (name.split('/').pop() === want) {
    const dataStart = lho + 30 + buf.readUInt16LE(lho + 26) + buf.readUInt16LE(lho + 28);
    const comp = buf.subarray(dataStart, dataStart + compSize);
    fs.writeFileSync(dest, method === 0 ? comp : zlib.inflateRawSync(comp));
    fs.chmodSync(dest, 0o755);
    process.exit(0);
  }
  p += 46 + nameLen + extraLen + commLen;
}
console.error('entry not found: ' + want);
process.exit(1);
EOF
  printf '%s' "$f"
}

# _mcli_install <cmd> <url> <type> [bin_regex]
#   type      : tar (.tar.gz) | zip | raw (single binary)
#   bin_regex : ERE locating the binary member inside the archive (tar only)
# Always returns 0 — failures are reported and skipped.
_mcli_install() {
  local cmd="$1" url="$2" type="$3" rx="${4:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  local dest="$HOME/.local/bin" tmp member ok=0
  mkdir -p "$dest"
  tmp="$(mktemp)"
  if ! curl -fsSL "$url" -o "$tmp"; then
    rm -f "$tmp"
    echo "Skipping $cmd; download failed ($url)"
    return 0
  fi

  case "$type" in
    raw)
      if cp "$tmp" "$dest/$cmd"; then
        chmod +x "$dest/$cmd"
        ok=1
      fi
      ;;
    tar)
      member="$(tar -tzf "$tmp" 2>/dev/null | grep -E "$rx" | head -n 1 || true)"
      if [ -n "$member" ] && tar -xzf "$tmp" -O "$member" > "$dest/$cmd" 2>/dev/null; then
        chmod +x "$dest/$cmd"
        ok=1
      fi
      ;;
    zip)
      if command -v unzip >/dev/null 2>&1; then
        local zdir
        zdir="$(mktemp -d)"
        if unzip -q -o "$tmp" -d "$zdir" 2>/dev/null; then
          member="$(find "$zdir" -type f -name "$cmd" | head -n 1 || true)"
          if [ -n "$member" ]; then
            cp "$member" "$dest/$cmd"
            chmod +x "$dest/$cmd"
            ok=1
          fi
        fi
        rm -rf "$zdir"
      elif [ -n "${_MCLI_UNZIP:-}" ] && command -v node >/dev/null 2>&1; then
        if node "$_MCLI_UNZIP" "$tmp" "$cmd" "$dest/$cmd" 2>/dev/null; then
          ok=1
        fi
      else
        echo "Skipping $cmd; no unzip and no node to extract the zip."
        rm -f "$tmp"
        return 0
      fi
      ;;
  esac

  rm -f "$tmp"
  if [ "$ok" != "1" ]; then
    echo "Skipping $cmd; could not extract binary from release."
  fi
  return 0
}

# Versioned asset: resolve the latest tag, substitute {tag} (as-is, e.g. v10.4.2
# or 15.1.0) and {ver} (tag without a leading v) into the URL template, install.
_mcli_install_versioned() {
  local cmd="$1" repo="$2" url_tmpl="$3" type="$4" rx="${5:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  local tag ver url
  if ! tag="$(_mcli_tag "$repo")"; then
    echo "Skipping $cmd; could not resolve latest release of $repo."
    return 0
  fi
  ver="${tag#v}"
  url="${url_tmpl//\{tag\}/$tag}"
  url="${url//\{ver\}/$ver}"
  _mcli_install "$cmd" "$url" "$type" "$rx"
}

install_modern_cli() {
  if [ "${INSTALL_MODERN_CLI:-1}" = "0" ]; then
    return
  fi

  if is_termux; then
    echo "Modern CLI tools: on Termux install via pkg (e.g. pkg install ripgrep fd jq)."
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "Skipping modern CLI tools; curl is not available."
    return
  fi

  if ! _mcli_arch; then
    echo "Skipping modern CLI tools; unsupported architecture: $(uname -m)."
    return
  fi

  mkdir -p "$HOME/.local/bin"

  # Node-based zip fallback (for procs) when `unzip` is unavailable.
  _MCLI_UNZIP=""
  if ! command -v unzip >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    _MCLI_UNZIP="$(_mcli_make_unzip_helper || true)"
  fi

  # --- single-binary assets (no version in the filename) ---
  _mcli_install jq    "https://github.com/jqlang/jq/releases/latest/download/jq-linux-${_MA_RAW}" raw
  _mcli_install yq    "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${_MA_RAW}" raw
  _mcli_install tldr  "https://github.com/tealdeer-rs/tealdeer/releases/latest/download/tealdeer-linux-${_MA_X}-musl" raw

  # --- tarball assets (no version in the filename) ---
  _mcli_install gping "https://github.com/orf/gping/releases/latest/download/gping-Linux-musl-${_MA_GPING}.tar.gz" tar '(^|/)gping$'
  _mcli_install btop  "https://github.com/aristocratos/btop/releases/latest/download/btop-${_MA_MUSL}.tar.gz" tar '(^|/)btop$'

  # --- versioned tarball assets (tag embedded in the filename) ---
  _mcli_install_versioned rg    BurntSushi/ripgrep "https://github.com/BurntSushi/ripgrep/releases/download/{tag}/ripgrep-{tag}-${_MA_MUSL}.tar.gz" tar '(^|/)rg$'
  _mcli_install_versioned fd    sharkdp/fd         "https://github.com/sharkdp/fd/releases/download/{tag}/fd-{tag}-${_MA_MUSL}.tar.gz" tar '(^|/)fd$'
  _mcli_install_versioned delta dandavison/delta   "https://github.com/dandavison/delta/releases/download/{tag}/delta-{tag}-${_MA_MUSL}.tar.gz" tar '(^|/)delta$'
  _mcli_install_versioned dust  bootandy/dust      "https://github.com/bootandy/dust/releases/download/{tag}/dust-{tag}-${_MA_MUSL}.tar.gz" tar '(^|/)dust$'
  _mcli_install_versioned sd    chmln/sd           "https://github.com/chmln/sd/releases/download/{tag}/sd-{tag}-${_MA_MUSL}.tar.gz" tar '(^|/)sd$'
  _mcli_install_versioned duf   muesli/duf         "https://github.com/muesli/duf/releases/download/{tag}/duf_{ver}_linux_${_MA_X}.tar.gz" tar '(^|/)duf$'
  _mcli_install_versioned xh    ducaale/xh         "https://github.com/ducaale/xh/releases/download/{tag}/xh-{tag}-${_MA_MUSL}.tar.gz" tar '(^|/)xh$'

  # --- versioned zip asset ---
  _mcli_install_versioned procs dalance/procs      "https://github.com/dalance/procs/releases/download/{tag}/procs-{tag}-${_MA_LINUXX}.zip" zip

  if [ -n "${_MCLI_UNZIP:-}" ]; then
    rm -f "$_MCLI_UNZIP"
  fi
  return 0
}
