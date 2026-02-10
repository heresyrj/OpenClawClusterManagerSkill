# Root-State Refactor Playbook

Goal: migrate from a flat legacy `~/.openclaw` state into `~/.openclaw/.openclaw-<instance>` while preserving the full original state.

## Preconditions

1. You know which legacy root state belongs to which instance (for example Luca).
2. Existing LaunchAgents are present in `~/Library/LaunchAgents`.
3. You can stop all OpenClaw services safely.

## Safe Migration Steps

### Step 1: Stop all OpenClaw launchd services

```bash
~/.openclaw/openclaw-fleet.sh stop
```

If fleet script is unavailable:

```bash
for p in ~/Library/LaunchAgents/ai.openclaw.*.plist; do
  [ -f "$p" ] || continue
  label=$(plutil -extract Label raw -o - "$p" 2>/dev/null || true)
  [ -n "$label" ] && launchctl bootout gui/$(id -u)/$label || true
done
```

### Step 2: Run migration script

Example: move legacy root state into `.openclaw-luca`:

```bash
~/.codex/skills/openclaw-cluster-manager/scripts/openclaw-migrate-root-state.sh --instance luca
```

What it does:

1. Creates `~/.openclaw/.openclaw-luca` if needed.
2. Moves legacy runtime files from root to that target.
3. Leaves container-level script/doc files at root.
4. Creates missing `logs/` and `workspace/` folders in target if absent.

### Step 3: Update/verify plist state path

Verify:

```bash
plutil -extract EnvironmentVariables.OPENCLAW_STATE_DIR raw -o - ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```

Expected example:

```text
/Users/<user>/.openclaw/.openclaw-luca
```

### Step 4: Restart services and audit

```bash
~/.openclaw/openclaw-fleet.sh start
~/.openclaw/openclaw-fleet.sh audit
~/.openclaw/openclaw-fleet.sh status
```

## Rollback Strategy

If migration result is wrong:

1. Stop services.
2. Move files back from target instance dir to root (reverse move).
3. Restore previous plist files if they were edited.
4. Start services and re-check status.

## Guardrails

1. Never delete source state before validating boot and port listeners.
2. Never run migration while instances are actively writing state.
3. Keep `.env` and secret files in instance dir; do not commit them.
