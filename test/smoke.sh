#!/usr/bin/env bash
set -euo pipefail

test -f "$HOME/.zshrc"
test -f "$HOME/.tmux.conf"
test -f "$HOME/.config/fastfetch/config.jsonc"
test -f "$HOME/.config/fastfetch/logo.ansi"

command -v zsh
command -v tmux
command -v zoxide
command -v fastfetch
command -v uv
command -v rustc
command -v eza
command -v bat
command -v lolcrab

zsh -ic 'echo zsh-ok'
tmux -f "$HOME/.tmux.conf" start-server
fastfetch --config "$HOME/.config/fastfetch/config.jsonc" --pipe false >/tmp/fastfetch.out
