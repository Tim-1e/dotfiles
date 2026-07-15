# Codex App provider switch implementation plan

## Files

- Modify `test/ai-env-smoke.ps1` with isolated App-switch tests.
- Modify `Documents/PowerShell/Scripts/ai-env.ps1` with the `cx app-default` management path and targeted TOML update helpers.
- Add `dot_codex/private_app-auth/private_codex-app-token.ps1` so chezmoi deploys the command-auth helper directly into protected `~/.codex/app-auth`.
- Update help and the default registry template.

## Steps

1. Add a failing smoke test for API activation, subscription restoration, idempotency, unrelated-config preservation, registry state, `auth.json` preservation, and secret non-disclosure.
2. Add the fixed-output token helper and cover success/failure behavior.
3. Add the App default getter/setter and profile-to-provider projection.
4. Run PowerShell smoke tests and syntax/config checks.
5. Review the diff for security and correctness.
6. Target-apply only the managed `ai-env.ps1` and `~/.codex/app-auth/codex-app-token.ps1` files, repair and verify the control/secret ACLs with a rollback record, then switch the live App config to `surplus`.
7. Verify the effective config and a direct Responses-compatible API probe without exposing the key.
