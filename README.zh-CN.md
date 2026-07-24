# Dotfiles

[![CI](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml)

语言：[English](README.md) | [🇨🇳 中文](README.zh-CN.md) | [🇰🇷 한국어](README.ko.md) | [🇯🇵 日本語](README.ja.md)

这是一个基于 chezmoi 管理的开发环境仓库，覆盖 Linux、WSL、Termux 和
Windows PowerShell。它主要同步三层内容：

- **基础环境**：shell、tmux、字体、运行时安装脚本，以及跨平台 bootstrap。
- **现代命令行工具**：把 `rg`、`fd`、`jq`、`yq`、`delta`、`dust`、`duf`、
  `xh`、`btop` 等日常工具安装到用户目录。
- **AI 工作区工具**：固定版本的 [cxcc](https://github.com/Tim-1e/cxcc)
  提供 `cx`、`cc`、`mcp`，用于切换 Codex / Claude Code 配置、API router、
  健康检查、MCP 同步和密钥隔离。

仓库只创建缺失的默认配置，尽量不覆盖机器上的已有设置。真实密钥不进 git。

## 同步内容

| 分类 | 管理内容 | 主要文件 |
|------|----------|----------|
| 基础 shell | zsh、Oh My Zsh 插件、tmux、fzf、zoxide、uv、rustup、locale 保护 | `dot_zshrc`, `dot_tmux.conf`, `scripts/install.sh` |
| 现代 CLI | 预编译 release binary 安装到 `~/.local/bin`，无需 root | `scripts/install/modern-cli.sh` |
| 字体 | 0xProto Nerd Font，覆盖 Linux、macOS、Windows、WSL host | `0xProto/`, font run-on-change 脚本 |
| cxcc | 固定版本的跨平台安装器和稳定 shell loader | `.chezmoidata.toml`, `scripts/install/cxcc.*`, `run_before_10-install-cxcc.*.tmpl` |
| Windows | 加载 cxcc 的 PowerShell profile 与兼容 hook | `Documents/PowerShell/create_Microsoft.PowerShell_profile.ps1`, `run_onchange_after_10-powershell-ai-env-hook.ps1.tmpl` |
| AI profiles | Codex/Claude profile registry、health cache、本地状态、默认种子配置 | `dot_ai-env/`, `dot_codex/`, `dot_claude/` |
| MCP | 本机 MCP registry，并同步到 Claude Code / Codex | `~/.ai-env/mcp.toml`, `mcp` helper |
| Secrets | 只提供安全模板，真实 key 放在仓库外 | `secret_examples/`, `~/.ai-secrets/secrets.toml` |

## 快速部署

全新 Linux 或 WSL：

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

本地 clone 后部署：

```sh
git clone https://github.com/Tim-1e/dotfiles.git
cd dotfiles
bash ./bootstrap.sh
```

Windows PowerShell：

```powershell
.\bootstrap.ps1
```

Termux：

```sh
pkg update
pkg install -y bash termux-exec git chezmoi
chezmoi init --apply Tim-1e/dotfiles
```

Termux 首次 apply 前需要 `termux-exec`，它提供 `/usr/bin/env` 等标准路径。

## 安装开关

```sh
INSTALL_CLAUDE=1 bash ./bootstrap.sh
INSTALL_NODE=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FASTFETCH=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_MODERN_CLI=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_CXCC=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FONTS=0 bash ./bootstrap.sh
INSTALL_WINDOWS_FONTS_FROM_WSL=0 bash ./bootstrap.sh
DOTFILES_USE_SUDO=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
DOTFILES_USE_SUDO=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

系统包只在 root 或可用 sudo 时安装。如果 sudo 需要密码，脚本会询问，默认不使用。
没有 sudo 时，用户目录级别的工具仍会尽量安装。

## 基础环境

基础层会安装或配置：

- zsh、tmux、git、curl、wget、nano、fzf、构建工具、locale
- Oh My Zsh、`zsh-autosuggestions`、`zsh-syntax-highlighting`
- zoxide、TPM、rustup、uv
- cargo 工具：`eza`、`bat`、`lolcrab`
- 兼容的 fastfetch 到 `~/.local/bin`
- Node.js 和 npm，默认随系统包安装
- 0xProto Nerd Font 到当前用户字体目录
- 选择安装时提供固定版本的 cxcc，以及加载 `cx`、`cc`、`mcp` 的 PowerShell/Zsh hook

如果系统没有 zsh，但有编译工具，脚本会把 zsh 编译到 `~/.local`。老 Linux
系统上，fastfetch 会优先尝试 polyfilled binary；没有合适版本时跳过，不让整个
apply 失败。

## 现代 CLI 工具

`scripts/install/modern-cli.sh` 把常用现代命令行工具以预编译二进制形式安装到
`~/.local/bin`。每个工具都是 best-effort，失败只打印 skip，不中断部署。

| 工具 | 用途 | 工具 | 用途 |
|------|------|------|------|
| `rg` | 快速递归 grep | `procs` | 更易读的 `ps` |
| `fd` | 更友好的 `find` | `btop` | `top`/`htop` 监控 |
| `jq` | JSON 处理 | `xh` | HTTP client |
| `yq` | YAML/TOML 处理 | `gping` | 带图形的 ping |
| `delta` | 高亮 git diff | `dust` | 树状 `du` |
| `sd` | 简化 find/replace | `duf` | 更好看的 `df` |
| `tldr` | 示例化 man page | | |

交互 alias 保守启用：`du` -> `dust`、`df` -> `duf`、`ps` -> `procs`、
`ping` -> `gping`、`top`/`htop` -> `btop`。`rg`、`fd`、`sd`、`jq`、
`yq`、`xh`、`delta` 这类 flag 不完全兼容的工具不会覆盖标准命令。

## CX/CC AI Profile 工具

dotfiles 可安装固定版本的 cxcc，再加载其轻量 shell function，用于切换 Codex 和
Claude Code 的本地状态，但不会直接启动 CLI。命令实现和跨平台测试归 cxcc 仓库
维护；本仓库只负责版本钉住、安装 hook、loader 接线和默认用户配置：

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

安装位置：

```text
PowerShell: ~/.local/share/cxcc/load.ps1
Bash/Zsh:  ~/.local/share/cxcc/load.sh
Payload:   ~/.local/share/cxcc/versions/v0.1.0/
```

release tag、不可变 commit、installer digest 和平台 artifact digest 统一位于
`.chezmoidata.toml`。cxcc 默认不安装；交互 apply 会询问
`Install the cx/cc environment? [y/N]`，直接回车即跳过。非交互安装设置
`INSTALL_CXCC=1`，需要无提示跳过时设置 `INSTALL_CXCC=0`。

运行状态：

```text
~/.ai-env/profiles.json       profile registry
~/.ai-env/state.json          当前选择
~/.ai-env/health.json         health probe cache
~/.ai-secrets/secrets.toml    真实本地密钥
```

`cx` / `cc` 只切换当前 shell 环境。切换后需要单独运行 `codex` 或 `claude`。

### Profile 行为

- subscription profile 清理 API 环境变量，使用本地 CLI login cache。
- API profile 从 `~/.ai-secrets/secrets.toml` 读取 key 和 router URL。
- Codex API profile 可以共享 `~/.codex`，保留同一套 sessions/history。
- 多个 Codex subscription 账号应使用不同 `CODEX_HOME`。
- `cx add-api` 会生成对应的 `~/.codex/<profile>.config.toml`。
- `cx edit` / `cc edit` 打开 `~/.ai-env/profiles.json`，用于 helper 没覆盖的 registry 修改。

### Health、Status 和 Probe Model

`cx health` / `cc health` 会发起真实但极小的生成请求：

- Claude：`/v1/messages`
- Codex：`/responses`，并 fallback 到 `/chat/completions`

probe 会验证是否真的返回生成内容，而不是只看 HTTP 是否可达。结果缓存约 5 分钟。

- `cx list` / `cc list` 只读缓存，不发网络请求。
- `cx status` / `cc status` 显示当前状态、probe model 和缓存 health。
- `status --fresh` 或 `status --refresh` 对当前 profile 现场 probe。
- 裸 `cx` / `cc` 会自动选择缓存中 healthy/degraded 的 profile，优先默认 profile；
  `next` 才是手动轮转。
- router 不支持默认模型时，可以给 profile 设置 `probe_model`。
- 没有 `probe_model` 时，Claude probe 会依次用 `ANTHROPIC_MODEL`、
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`、便宜 Haiku fallback；Codex probe 会用 runtime
  TOML model、全局 `~/.codex/config.toml` model、便宜 GPT fallback。

health 表格里的 Note 会刻意缩短，避免 TTY 换行；`status` 和切换输出保留更完整的错误细节。

## MCP Server 同步

`mcp` 从一个本地文件管理 Claude Code 和 Codex 的 MCP server：

```sh
mcp edit
mcp list
mcp get context7
mcp sync
mcp pull
mcp pull context7
```

单一来源：

```text
~/.ai-env/mcp.toml
```

示例：

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

`mcp sync` 会写入 Claude `~/.claude.json` 和 Codex `~/.codex/config.toml`，
并保留无关设置。Codex 官方 `@openai-curated` connectors 由 Codex 自己管理，
不属于这个 helper 的范围。

## 密钥

真实密钥放在：

```text
~/.ai-secrets/secrets.toml
```

使用 profile 的 `secret_id` 作为 TOML section：

```toml
[codex.api]
OPENAI_API_KEY = "sk-..."

[claude.api]
ANTHROPIC_BASE_URL = "https://router.example"
ANTHROPIC_AUTH_TOKEN = "sk-..."
```

`secret_examples/` 只包含安全模板。不要提交真实 token、OAuth 文件、auth 状态或本机 MCP secret。

## Chezmoi 映射

| Source | Target |
|--------|--------|
| `dot_zshrc` | `~/.zshrc` |
| `dot_tmux.conf` | `~/.tmux.conf` |
| `dot_config/fastfetch/*` | `~/.config/fastfetch/*` |
| `.chezmoidata.toml`, `scripts/install/cxcc.*` | 安装固定版本 cxcc 到 `~/.local/share/cxcc` |
| `dot_ai-env/create_profiles.json` | `~/.ai-env/profiles.json`，仅缺失时创建 |
| `dot_codex/create_*.toml` | `~/.codex/*.toml`，仅缺失时创建 |
| `dot_claude/create_settings.json` | `~/.claude/settings.json`，仅缺失时创建 |
| `Documents/PowerShell/create_Microsoft.PowerShell_profile.ps1` | 加载 `~/.local/share/cxcc/load.ps1` 的 Windows profile |
| `run_onchange_before_00-install-env.sh.tmpl` | 安装 hook |
| `run_before_10-install-cxcc.*.tmpl` | 固定版本 cxcc 安装 hook |
| `run_after_99-smoke-test.sh.tmpl` | apply 后 smoke hook |

`create_` 前缀文件只 seed 缺失配置，不覆盖已有机器设置。

## 验证

```powershell
pwsh -NoProfile -File test/cxcc-consumer-smoke.ps1
pwsh -NoProfile -File test/powershell-profile-smoke.ps1 -SourceDir .
```

```sh
bash -n scripts/install/cxcc.sh test/cxcc-consumer-smoke.sh
bash test/cxcc-consumer-smoke.sh
```

## AI 协作维护

这个仓库由 Tim-1e 维护，并在审查后接收 AI 辅助贡献。Claude、Cursor Agent
和 Codex 都参与过环境工具的设计、测试、文档和加固。AI 贡献通过 commit
message 里的 `Co-authored-by` trailer 记录，最终状态由仓库维护者审查并发布。
