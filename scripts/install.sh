#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=install/system-packages.sh
. "$SCRIPT_DIR/install/system-packages.sh"
# shellcheck source=install/user-bins.sh
. "$SCRIPT_DIR/install/user-bins.sh"
# shellcheck source=install/zsh.sh
. "$SCRIPT_DIR/install/zsh.sh"
# shellcheck source=install/rust-tools.sh
. "$SCRIPT_DIR/install/rust-tools.sh"
# shellcheck source=install/fastfetch.sh
. "$SCRIPT_DIR/install/fastfetch.sh"

main() {
  setup_system_install
  write_state
  install_base_packages
  install_node
  install_user_fzf
  install_user_eza
  install_user_zsh
  install_oh_my_zsh
  install_zoxide
  install_tpm
  install_rust
  install_cargo_tools
  install_fastfetch
  install_uv
  install_claude
}

main "$@"
