# OpenClaw Desktop App State Isolation

This document covers the desktop app process (menu bar/macOS app) and how to keep it isolated from gateway instances.

## Why This Exists

In a multi-instance setup, gateway services should use per-instance state dirs:

- `~/.openclaw/.openclaw-luca`
- `~/.openclaw/.openclaw-critic`
- `~/.openclaw/.openclaw-<future>`

The desktop app process is separate and may still write global files under `~/.openclaw` unless explicitly redirected. This commonly causes:

1. `~/.openclaw/agents` reappearing.
2. `exec-approvals` files being written in root.
3. Confusion about which process owns which state.

## Constraints (Current OpenClaw Behavior)

1. `OPENCLAW_STATE_DIR` is supported by runtime/config paths.
2. Exec approvals defaults are still fixed at:
   - `~/.openclaw/exec-approvals.json`
   - `~/.openclaw/exec-approvals.sock`
3. Therefore, the safest approach is:
   - Keep real desktop app data in `~/.openclaw/.openclaw-app`
   - Keep root compatibility symlinks for fixed approvals paths

## Target Layout

```text
~/.openclaw/
├── .openclaw-app/
│   ├── agents/
│   ├── exec-approvals.json
│   └── exec-approvals.sock
├── exec-approvals.json -> .openclaw-app/exec-approvals.json
├── exec-approvals.sock -> .openclaw-app/exec-approvals.sock
└── agents -> .openclaw-app/agents
```

Gateway instances remain fully independent in `.openclaw-luca`, `.openclaw-critic`, etc.

## Standard Command

Run:

```bash
~/.openclaw/openclaw-desktop-state.sh setup --relaunch
```

Then verify:

```bash
~/.openclaw/openclaw-desktop-state.sh status
```

Expected:

1. launchd env `OPENCLAW_STATE_DIR` and `CLAWDBOT_STATE_DIR` point to `.openclaw-app`.
2. root `exec-approvals.*` are symlinks.
3. desktop app process holds `.openclaw-app/exec-approvals.sock`.

## Upgrade Safety

This method is upgrade-safe in practice because:

1. Env injection is in user LaunchAgents (`~/Library/LaunchAgents`), not inside app bundle files.
2. Root compatibility symlinks preserve behavior for components that still use fixed default paths.

Residual risk:

1. A future app version may remove/change fixed-path behavior or env handling.
2. If that happens, rerun `setup` and re-check `status`.

## Rollback

If needed:

1. Stop desktop app.
2. Remove symlinks in root (`exec-approvals.json`, `exec-approvals.sock`, `agents`).
3. Restore copied files from `.openclaw-app` backup or previous root backup.
4. Remove desktop-env LaunchAgent and relaunch app.

