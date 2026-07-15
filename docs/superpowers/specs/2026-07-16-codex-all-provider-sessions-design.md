# Codex all-provider session routing design

## Goal

Let both the `cx` CLI workflow and Codex Desktop enumerate sessions created by any model provider, then resume the selected session with the provider selected by the current CLI or App profile.

The design keeps two decisions independent:

1. session discovery uses no provider filter;
2. session resume uses the current profile's explicit provider override.

## Verified behavior

- App-server `thread/list` treats `modelProviders: []` as all providers.
- Local Codex CLI 0.144.x still sends the current provider from its resume picker even with `--all`; that flag only disables cwd filtering.
- A CLI `--profile` layer containing `model_provider` makes resume use the current config rather than persisted model settings.
- Codex Desktop's normal UI resume path already sends the provider returned by its current new-thread configuration. Only its recent-thread list sends `modelProviders: null`.

## CLI interface

- `cx sessions` prints sessions from every provider without launching Codex.
- `cx resume` opens an all-provider selector and resumes the selected ID with the currently selected cx profile.
- `cx resume SESSION_ID` skips the selector and resumes that ID with the current profile.

The selector queries a short-lived local app-server with `thread/list.modelProviders = []`. It does not query or rewrite SQLite directly. On Windows it prefers `Out-GridView`; non-GUI and non-Windows sessions use a numbered console selector.

## Desktop bridge

Codex Desktop supports a process-level `CODEX_CLI_PATH` override. A small user-owned executable is installed as that path and launches a secured copy of the App's exact bundled Codex executable set.

The bridge is a line-oriented JSON-RPC proxy:

- requests whose method is `thread/list` receive `params.modelProviders = []`;
- every other request, including `thread/resume`, is forwarded unchanged;
- stdout and stderr are streamed unchanged from the real Codex process;
- malformed input is forwarded unchanged;
- recursive or missing downstream executable paths fail closed;
- `codex.exe`, command runner, code-mode host, and sandbox setup are copied together from the protected WindowsApps bundle and individually hash-pinned.

This avoids modifying the signed MSIX, `app.asar`, Appx block hashes, ACLs, databases, rollouts, authentication, and Remote Control enrollment.

## Activation and updates

- `cx app-bridge install` builds or locates the bridge, records the current same-hash user copy of the App's Codex executable, and sets the per-user `CODEX_CLI_PATH`.
- `cx app-bridge status` reports configured, active-process, bridge, and protected bundle hash-match state.
- `cx app-bridge remove` restores the previous per-user `CODEX_CLI_PATH` value.
- A running App must be closed and reopened. The installer never terminates the App.
- On App updates, `cx app-bridge install` is rerun to refresh the downstream path. Unknown or mismatched layouts are rejected.

## Security and state boundaries

- The bridge settings contain paths and hashes only, never API keys or login tokens.
- Source and destination directories/files must have an approved owner, no untrusted write ACE, and no reparse points before user-level activation is changed.
- Provider credentials continue to come from the existing subscription login or command-backed App auth.
- Existing session metadata remains historical. A resumed turn records the effective current thread settings without rewriting the session's original creation metadata.
- Remote Control login and enrollment are not changed. Mobile Remote history requests handled inside the downstream app-server do not pass back through the Desktop stdio request transformer; the upstream custom-provider refresh bug therefore remains a separate boundary that requires an upstream fix or a version-matched custom app-server.
