# Dotfiles

[![CI](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Tim-1e/dotfiles/actions/workflows/ci.yml)

Language: [English](README.md) | [🇨🇳 中文](README.zh-CN.md) | [🇰🇷 한국어](README.ko.md) | [🇯🇵 日本語](README.ja.md)

Linux, WSL, Termux, Windows PowerShell 환경을 chezmoi로 관리하는 dotfiles
저장소입니다. 핵심은 세 계층입니다.

- **기본 환경**: shell, tmux, font, runtime 설치 스크립트, 안전한 크로스 플랫폼 bootstrap.
- **현대적인 CLI 도구**: `rg`, `fd`, `jq`, `yq`, `delta`, `dust`, `duf`,
  `xh`, `btop` 등을 사용자 디렉터리에 설치.
- **AI 작업 도구**: `cx`, `cc`, `mcp`로 Codex / Claude Code 프로필, API
  router, health check, MCP sync, secret-safe switching을 관리.

기존 로컬 설정은 되도록 덮어쓰지 않고, 누락된 기본값만 생성합니다. 실제 secret은
이 저장소에 저장하지 않습니다.

## 동기화 범위

| 영역 | 관리 내용 | 주요 파일 |
|------|-----------|-----------|
| 기본 shell | zsh, Oh My Zsh plugins, tmux, fzf, zoxide, uv, rustup, locale guard | `dot_zshrc`, `dot_tmux.conf`, `scripts/install.sh` |
| Modern CLI | prebuilt release binary를 `~/.local/bin`에 설치, root 불필요 | `scripts/install/modern-cli.sh` |
| Fonts | Linux, macOS, Windows, WSL host용 0xProto Nerd Font | `0xProto/`, font run-on-change scripts |
| Windows | PowerShell profile hook 및 `cx`/`cc` helper | `Documents/PowerShell/Scripts/ai-env.ps1` |
| AI profiles | Codex/Claude registry, health cache, state, default seed config | `dot_ai-env/`, `dot_codex/`, `dot_claude/` |
| MCP | Claude Code와 Codex에 동기화되는 로컬 MCP registry | `~/.ai-env/mcp.toml`, `mcp` helper |
| Secrets | 안전한 예시만 제공, 실제 key는 repo 밖에 저장 | `secret_examples/`, `~/.ai-secrets/secrets.toml` |

## 빠른 배포

새 Linux 또는 WSL:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

로컬 checkout:

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

Termux에서는 첫 apply 전에 `termux-exec`가 필요합니다. `/usr/bin/env` 같은
표준 경로를 제공하기 때문입니다.

## 설치 옵션

```sh
INSTALL_CLAUDE=1 bash ./bootstrap.sh
INSTALL_NODE=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FASTFETCH=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_MODERN_CLI=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
INSTALL_FONTS=0 bash ./bootstrap.sh
INSTALL_WINDOWS_FONTS_FROM_WSL=0 bash ./bootstrap.sh
DOTFILES_USE_SUDO=0 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
DOTFILES_USE_SUDO=1 sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Tim-1e/dotfiles
```

시스템 패키지는 root이거나 sudo를 사용할 수 있을 때만 설치합니다. sudo에 비밀번호가
필요하면 물어보고 기본값은 사용하지 않는 것입니다. sudo가 없어도 사용자 레벨 도구는
가능한 범위에서 설치합니다.

## 기본 환경

기본 계층은 다음을 설치하거나 설정합니다.

- zsh, tmux, git, curl, wget, nano, fzf, build tools, locale
- Oh My Zsh, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- zoxide, TPM, rustup, uv
- cargo tools: `eza`, `bat`, `lolcrab`
- 호환 가능한 fastfetch를 `~/.local/bin`에 설치
- 시스템 패키지 설치가 켜져 있으면 Node.js와 npm 설치
- 현재 사용자 font 디렉터리에 0xProto Nerd Font 설치
- Windows PowerShell용 `cx` / `cc` profile hook

zsh가 없고 build tool이 있으면 zsh를 `~/.local`에 빌드합니다. 오래된 Linux에서는
fastfetch polyfilled binary를 우선 사용하고, 맞는 binary가 없으면 전체 apply를
실패시키지 않고 건너뜁니다.

## Modern CLI 도구

`scripts/install/modern-cli.sh`는 자주 쓰는 현대적 CLI를 prebuilt binary로
`~/.local/bin`에 설치합니다. 각 도구는 best-effort이며, 실패해도 전체 배포를
중단하지 않습니다.

| 도구 | 용도 | 도구 | 용도 |
|------|------|------|------|
| `rg` | 빠른 recursive grep | `procs` | 읽기 쉬운 `ps` |
| `fd` | 친숙한 `find` | `btop` | `top`/`htop` monitor |
| `jq` | JSON 처리 | `xh` | HTTP client |
| `yq` | YAML/TOML 처리 | `gping` | ping graph |
| `delta` | syntax-highlighted git diff | `dust` | tree-style `du` |
| `sd` | 쉬운 find/replace | `duf` | 보기 좋은 `df` |
| `tldr` | 예제 중심 man page | | |

interactive alias는 보수적으로만 켭니다. `du` -> `dust`, `df` -> `duf`,
`ps` -> `procs`, `ping` -> `gping`, `top`/`htop` -> `btop`입니다. flag가
호환되지 않는 `rg`, `fd`, `sd`, `jq`, `yq`, `xh`, `delta`는 표준 명령을
덮어쓰지 않습니다.

## CX/CC AI Profile 도구

Codex와 Claude Code의 로컬 상태를 전환하는 가벼운 shell function을 제공합니다.
CLI를 직접 실행하지는 않습니다.

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

설치 위치:

```text
Windows: ~/Documents/PowerShell/Scripts/ai-env.ps1
Linux:   ~/.local/share/ai-env/ai-env.sh
```

상태 파일:

```text
~/.ai-env/profiles.json       profile registry
~/.ai-env/state.json          selected profile state
~/.ai-env/health.json         health probe cache
~/.ai-secrets/secrets.toml    real local secrets
```

`cx` / `cc`는 현재 shell 환경만 바꿉니다. 전환 후 `codex` 또는 `claude`를 따로
실행합니다.

### Profile 동작

- subscription profile은 API 환경 변수를 정리하고 로컬 CLI login cache를 사용합니다.
- API profile은 `~/.ai-secrets/secrets.toml`에서 key와 router URL을 읽습니다.
- Codex API profile은 `~/.codex`를 공유할 수 있어 sessions/history가 유지됩니다.
- 여러 Codex subscription 계정은 별도 `CODEX_HOME`을 사용하는 것이 좋습니다.
- `cx add-api`는 `~/.codex/<profile>.config.toml`을 생성합니다.
- `cx edit` / `cc edit`은 helper로 처리하기 어려운 registry 수정을 위해
  `~/.ai-env/profiles.json`을 엽니다.

### Health, Status, Probe Model

`cx health`와 `cc health`는 실제 최소 생성 요청을 보냅니다.

- Claude: `/v1/messages`
- Codex: `/responses`, fallback `/chat/completions`

HTTP 도달성만 보지 않고, 실제 생성 결과가 있는지 확인합니다. 결과는 약 5분간
캐시됩니다.

- `cx list` / `cc list`는 캐시만 읽고 네트워크 요청을 하지 않습니다.
- `cx status` / `cc status`는 현재 상태, probe model, cached health를 표시합니다.
- `status --fresh` 또는 `status --refresh`는 선택된 profile을 live probe합니다.
- 인자 없는 `cx` / `cc`는 캐시에서 healthy/degraded profile을 자동 선택합니다.
  `next`는 수동 순환입니다.
- router가 기본 모델을 제공하지 않으면 profile별 `probe_model`을 설정할 수 있습니다.
- `probe_model`이 없으면 Claude는 `ANTHROPIC_MODEL`,
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`, cheap Haiku fallback 순서로 probe합니다. Codex는
  runtime TOML model, global `~/.codex/config.toml` model, cheap GPT fallback을
  사용합니다.

health table의 Note는 TTY 줄바꿈을 피하기 위해 짧게 표시합니다. `status`와 switch
출력은 디버깅을 위해 더 자세한 오류를 유지합니다.

## MCP Server Sync

`mcp`는 하나의 로컬 파일에서 Claude Code와 Codex의 MCP server를 관리합니다.

```sh
mcp edit
mcp list
mcp get context7
mcp sync
mcp pull
mcp pull context7
```

단일 source of truth:

```text
~/.ai-env/mcp.toml
```

예시:

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

`mcp sync`는 Claude `~/.claude.json`과 Codex `~/.codex/config.toml`에 쓰며,
관련 없는 설정은 보존합니다. Codex 공식 `@openai-curated` connector는 Codex가
직접 관리하므로 이 helper의 범위 밖입니다.

## Secrets

실제 secret은 여기에 둡니다.

```text
~/.ai-secrets/secrets.toml
```

profile의 `secret_id`를 TOML section으로 사용합니다.

```toml
[codex.api]
OPENAI_API_KEY = "sk-..."

[claude.api]
ANTHROPIC_BASE_URL = "https://router.example"
ANTHROPIC_AUTH_TOKEN = "sk-..."
```

`secret_examples/`에는 안전한 template만 있습니다. 실제 token, OAuth file, auth
state, 로컬 MCP secret은 commit하지 않습니다.

## Chezmoi Map

| Source | Target |
|--------|--------|
| `dot_zshrc` | `~/.zshrc` |
| `dot_tmux.conf` | `~/.tmux.conf` |
| `dot_config/fastfetch/*` | `~/.config/fastfetch/*` |
| `dot_local/share/ai-env/ai-env.sh` | `~/.local/share/ai-env/ai-env.sh` |
| `dot_ai-env/create_profiles.json` | `~/.ai-env/profiles.json` if missing |
| `dot_codex/create_*.toml` | `~/.codex/*.toml` if missing |
| `dot_claude/create_settings.json` | `~/.claude/settings.json` if missing |
| `Documents/PowerShell/Scripts/ai-env.ps1` | Windows PowerShell helper |
| `run_onchange_before_00-install-env.sh.tmpl` | installer hook |
| `run_after_99-smoke-test.sh.tmpl` | post-apply smoke hook |

`create_` 파일은 누락된 설정만 seed하며 기존 머신 설정을 덮어쓰지 않습니다.

## 검증

```powershell
pwsh -NoProfile -File test/ai-env-smoke.ps1 -SourceDir .
pwsh -NoProfile -File test/ai-env-health.ps1 -SourceDir .
```

```sh
bash -n dot_local/share/ai-env/ai-env.sh
node --check dot_local/share/ai-env/ai-health.mjs
bash test/ai-env-smoke.sh
```

로컬 Claude Docker 컨테이너에서 Linux 검증:

```sh
docker compose exec -T claude bash -lc 'cd /workspace/CodeX_desk/dotfiles && chezmoi apply --force -- "$HOME/.local" && source "$HOME/.local/share/ai-env/ai-env.sh" && bash test/ai-env-smoke.sh'
```

## AI-assisted Maintenance

이 저장소는 Tim-1e가 유지보수하며, 검토된 AI assistance를 사용합니다. Claude,
Cursor Agent, Codex는 환경 도구의 설계, 테스트, 문서화, 안정화에 기여했습니다.
AI 기여는 commit message의 `Co-authored-by` trailer로 기록되며, 최종 상태는
저장소 maintainer가 검토하고 배포합니다.
