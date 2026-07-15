# Codex all-provider sessions implementation plan

## Files

- Add `tools/codex-provider-bridge/CodexProviderBridge.csproj`.
- Add `tools/codex-provider-bridge/Program.cs`.
- Add `test/codex-provider-bridge.ps1`.
- Modify `Documents/PowerShell/Scripts/ai-env.ps1`.
- Modify `test/ai-env-smoke.ps1`.
- Update `README.md` only if the existing command reference documents cx subcommands.

## Steps

1. Add a failing bridge contract test for `thread/list` transformation, byte-preserving pass-through, argument/stderr forwarding, missing settings, and recursion rejection.
2. Implement the minimal .NET stdio bridge and make the contract test pass.
3. Add failing isolated smoke tests for `cx sessions`, selector-independent `cx resume SESSION_ID`, and App bridge install/status/remove state.
4. Implement the all-provider app-server query, session formatting/selection, and current-profile resume command.
5. Implement App bridge discovery and reversible per-user environment activation without stopping Codex Desktop.
6. Run bridge, ai-env, Windows, syntax, and secret-disclosure tests.
7. Review the diff for code quality and security, then deploy only the tested bridge and PowerShell script to the live user paths.
8. Restart Codex Desktop manually and verify that unpinned sessions from at least two providers are visible while session metadata, auth, and Remote Control enrollment remain unchanged.
