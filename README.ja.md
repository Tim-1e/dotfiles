# Dotfiles

[![CI](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml)

Language: [English](README.md) | [🇨🇳 中文](README.zh-CN.md) | [🇰🇷 한국어](README.ko.md) | [🇯🇵 日本語](README.ja.md)

Linux、WSL、Termux、Windows PowerShell 向けの chezmoi 管理 dotfiles です。
主に三つのレイヤーを同期します。

- **基本環境**: shell、tmux、font、runtime installer、安全な cross-platform bootstrap。
- **モダン CLI ツール**: `rg`、`fd`、`jq`、`yq`、`delta`、`dust`、`duf`、
  `xh`、`btop` などをユーザー領域へインストール。
- **AI ワークスペースツール**: 固定バージョンの
  [cxcc](https://github.com/Tim-1e/cxcc) が `cx`、`cc`、`mcp` を提供し、
  Codex / Claude Code profile、API router、health check、MCP sync を管理します。

既存のローカル設定はできるだけ上書きせず、足りないデフォルトだけを作成します。
実際の secret はこのリポジトリに保存しません。

## 同期される内容

| 領域 | 管理内容 | 主なファイル |
|------|----------|--------------|
| 基本 shell | zsh, Oh My Zsh plugins, tmux, fzf, zoxide, uv, rustup, locale guard | `dot_zshrc`, `dot_tmux.conf`, `scripts/install.sh` |
| Modern CLI | prebuilt release binary を `~/.local/bin` へインストール、root 不要 | `scripts/install/modern-cli.sh` |
| Fonts | Linux, macOS, Windows, WSL host 用 0xProto Nerd Font | `0xProto/`, font run-on-change scripts |
| cxcc | 固定バージョンの cross-platform installer と安定した shell loader | `.chezmoidata.toml`, `scripts/install/cxcc.*`, `run_before_10-install-cxcc.*.tmpl` |
| Windows | cxcc を読み込む PowerShell profile と互換 hook | `Documents/PowerShell/create_Microsoft.PowerShell_profile.ps1`, `run_onchange_after_10-powershell-ai-env-hook.ps1.tmpl` |
| AI profiles | Codex/Claude registry, health cache, state, default seed config | `dot_ai-env/`, `dot_codex/`, `dot_claude/` |
| MCP | Claude Code と Codex に同期するローカル MCP registry | `~/.ai-env/mcp.toml`, `mcp` helper |
| Secrets | 安全なテンプレートのみ、実際の key は repo 外 | `secret_examples/`, `~/.ai-secrets/secrets.toml` |

## クイックデプロイ

新しい Linux または WSL:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

ローカル checkout:

```sh
git clone https://github.com/Tim-1e/dotfiles.git
cd dotfiles
bash ./bootstrap.sh
```

Windows PowerShell:

```powershell
.\bootstrap.ps1
```

Termux:

```sh
pkg update
pkg install -y bash termux-exec git chezmoi
chezmoi init --apply Tim-1e/dotfiles
```

Termux では初回 apply 前に `termux-exec` が必要です。`/usr/bin/env` などの
標準パスを提供します。

## インストールオプション

```sh
INSTALL_CLAUDE=1 bash ./bootstrap.sh
INSTALL_NODE=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FASTFETCH=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_MODERN_CLI=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_CXCC=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FONTS=0 bash ./bootstrap.sh
INSTALL_WINDOWS_FONTS_FROM_WSL=0 bash ./bootstrap.sh
DOTFILES_USE_SUDO=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
DOTFILES_USE_SUDO=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

システムパッケージは root または sudo が使える場合のみインストールします。
sudo にパスワードが必要な場合は確認し、デフォルトでは使いません。sudo がなくても、
ユーザーレベルのツールは可能な範囲でインストールします。

## 基本環境

基本レイヤーは次をインストールまたは設定します。

- zsh, tmux, git, curl, wget, nano, fzf, build tools, locale
- Oh My Zsh, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- zoxide, TPM, rustup, uv
- cargo tools: `eza`, `bat`, `lolcrab`
- 互換性のある fastfetch を `~/.local/bin` へ
- システムパッケージが有効な場合は Node.js と npm
- 現在ユーザーの font directory へ 0xProto Nerd Font
- 固定バージョンの cxcc と、`cx`、`cc`、`mcp` を読み込む PowerShell/Zsh hook

zsh がなく build tools がある場合は、zsh を `~/.local` にビルドします。
古い Linux では fastfetch の polyfilled binary を優先し、適合するものがなければ
全体の apply を失敗させずにスキップします。

## Modern CLI ツール

`scripts/install/modern-cli.sh` は日常利用の CLI を prebuilt binary として
`~/.local/bin` に入れます。各ツールは best-effort で、失敗しても全体の
deploy は中断しません。

| ツール | 用途 | ツール | 用途 |
|--------|------|--------|------|
| `rg` | 高速 recursive grep | `procs` | 読みやすい `ps` |
| `fd` | 使いやすい `find` | `btop` | `top`/`htop` monitor |
| `jq` | JSON processor | `xh` | HTTP client |
| `yq` | YAML/TOML processor | `gping` | ping graph |
| `delta` | syntax-highlighted git diff | `dust` | tree-style `du` |
| `sd` | 簡単な find/replace | `duf` | 見やすい `df` |
| `tldr` | examples-based man pages | | |

interactive alias は慎重に設定しています。`du` -> `dust`、`df` -> `duf`、
`ps` -> `procs`、`ping` -> `gping`、`top`/`htop` -> `btop` のみです。
flag が互換ではない `rg`、`fd`、`sd`、`jq`、`yq`、`xh`、`delta` は標準コマンドを
上書きしません。

## CX/CC AI Profile ツール

dotfiles は固定バージョンの cxcc をインストールし、その軽量 shell function で
Codex と Claude Code のローカル状態を切り替えます。CLI 自体は起動しません。
コマンド実装と cross-platform test は cxcc が、version pin、install hook、loader
接続、default user config はこの repo が管理します。

```sh
cx list
cx status
cx status --fresh
cx sub
cx api
cx next
cx stats
cx add-api api:work --base-url https://router.example/v1
cx add-sub sub:work
cx probe-model api:work gpt-example
cx edit

cc list
cc status
cc status --fresh
cc sub
cc api
cc next
cc add-api api:work --base-url https://router.example
cc add-sub sub:work
cc probe-model api:work claude-example
cc edit
```

インストール先:

```text
PowerShell: ~/.local/share/cxcc/load.ps1
Bash/Zsh:  ~/.local/share/cxcc/load.sh
Payload:   ~/.local/share/cxcc/versions/v0.1.0/
```

release tag、immutable commit、installer digest、platform artifact digest は
`.chezmoidata.toml` にまとめてあります。対応する pin をすべて更新して
`chezmoi apply` を実行すると upgrade できます。`INSTALL_CXCC=0` で install を
skip でき、変数を外した次回 apply で通常動作に戻ります。

状態ファイル:

```text
~/.ai-env/profiles.json       profile registry
~/.ai-env/state.json          selected profile state
~/.ai-env/health.json         health probe cache
~/.ai-secrets/secrets.toml    real local secrets
```

`cx` / `cc` は現在の shell 環境だけを切り替えます。切り替え後に `codex` または
`claude` を別途実行します。

### Profile の動作

- subscription profile は API 用環境変数を消し、ローカル CLI login cache を使います。
- API profile は `~/.ai-secrets/secrets.toml` から key と router URL を読みます。
- Codex API profile は `~/.codex` を共有でき、sessions/history を維持できます。
- 複数の Codex subscription account は別々の `CODEX_HOME` を使うべきです。
- `cx add-api` は `~/.codex/<profile>.config.toml` を作成します。
- `cx edit` / `cc edit` は helper で扱えない registry 変更のため
  `~/.ai-env/profiles.json` を開きます。

### Health、Status、Probe Model

`cx health` と `cc health` は実際の最小生成リクエストを送ります。

- Claude: `/v1/messages`
- Codex: `/responses`、fallback は `/chat/completions`

HTTP 到達性だけではなく、実際に生成内容が返ったかを検証します。結果は約 5 分
キャッシュされます。

- `cx list` / `cc list` はキャッシュだけを読み、ネットワークを使いません。
- `cx status` / `cc status` は現在の状態、probe model、cached health を表示します。
- `status --fresh` または `status --refresh` は選択中 profile を live probe します。
- 引数なしの `cx` / `cc` はキャッシュ上 healthy/degraded な profile を自動選択します。
  `next` は手動 cycle です。
- router がデフォルト model を提供しない場合、profile ごとに `probe_model` を設定できます。
- `probe_model` がない場合、Claude は `ANTHROPIC_MODEL`、
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`、cheap Haiku fallback の順で probe します。Codex は
  runtime TOML model、global `~/.codex/config.toml` model、cheap GPT fallback を使います。

health table の Note は TTY で折り返さないよう短く表示します。`status` と switch
出力は debugging のためより詳しい error を保持します。

## MCP Server Sync

`mcp` は一つのローカルファイルから Claude Code と Codex の MCP server を管理します。

```sh
mcp edit
mcp list
mcp get context7
mcp sync
mcp pull
mcp pull context7
```

single source of truth:

```text
~/.ai-env/mcp.toml
```

例:

```toml
[mcp.context7]
command = ["npx", "-y", "@upstash/context7-mcp"]
sync = ["claude", "codex"]
enabled = true

[mcp.figma]
url = "https://mcp.figma.com/mcp"
sync = ["codex"]
enabled = false
```

`mcp sync` は Claude `~/.claude.json` と Codex `~/.codex/config.toml` に書き込み、
関係ない設定は保持します。Codex 公式 `@openai-curated` connectors は Codex 自身が
管理するため、この helper の対象外です。

## Secrets

実際の secret はここに置きます。

```text
~/.ai-secrets/secrets.toml
```

profile の `secret_id` を TOML section として使います。

```toml
[codex.api]
OPENAI_API_KEY = "sk-..."

[claude.api]
ANTHROPIC_BASE_URL = "https://router.example"
ANTHROPIC_AUTH_TOKEN = "sk-..."
```

`secret_examples/` は安全な template のみです。実 token、OAuth file、auth state、
local MCP secret は commit しないでください。

## Chezmoi Map

| Source | Target |
|--------|--------|
| `dot_zshrc` | `~/.zshrc` |
| `dot_tmux.conf` | `~/.tmux.conf` |
| `dot_config/fastfetch/*` | `~/.config/fastfetch/*` |
| `.chezmoidata.toml`, `scripts/install/cxcc.*` | 固定 cxcc release を `~/.local/share/cxcc` に install |
| `dot_ai-env/create_profiles.json` | `~/.ai-env/profiles.json` if missing |
| `dot_codex/create_*.toml` | `~/.codex/*.toml` if missing |
| `dot_claude/create_settings.json` | `~/.claude/settings.json` if missing |
| `Documents/PowerShell/create_Microsoft.PowerShell_profile.ps1` | `~/.local/share/cxcc/load.ps1` を読む Windows profile |
| `run_onchange_before_00-install-env.sh.tmpl` | installer hook |
| `run_before_10-install-cxcc.*.tmpl` | 固定 cxcc install hook |
| `run_after_99-smoke-test.sh.tmpl` | post-apply smoke hook |

`create_` files は不足している設定だけを seed し、既存の machine settings は
上書きしません。

## 検証

```powershell
pwsh -NoProfile -File test/cxcc-consumer-smoke.ps1
pwsh -NoProfile -File test/powershell-profile-smoke.ps1 -SourceDir .
```

```sh
bash -n scripts/install/cxcc.sh test/cxcc-consumer-smoke.sh
bash test/cxcc-consumer-smoke.sh
```

## AI-assisted Maintenance

このリポジトリは Tim-1e が管理し、レビュー済みの AI assistance を利用しています。
Claude、Cursor Agent、Codex は環境ツールの設計、テスト、ドキュメント、堅牢化に
協力しています。AI contributions は commit message の `Co-authored-by` trailer
で記録され、最終状態は maintainer がレビューして公開します。
