# OpenClaw Cluster Operations

## 0. CLI Instance Targeting

**Default behavior:** `openclaw` CLI commands (gateway status/start/stop/health/probe) control the **main LaunchAgent** (`ai.openclaw.gateway` = Luca, port 18789). It does NOT auto-detect or switch between instances.

**Target a specific instance** by setting `OPENCLAW_STATE_DIR`:

```bash
# Luca (default, usually not needed)
OPENCLAW_STATE_DIR=~/.openclaw/.openclaw-luca openclaw gateway probe

# Critic
OPENCLAW_STATE_DIR=~/.openclaw/.openclaw-critic openclaw gateway probe
```

**For lifecycle management (start/stop/restart):** use `openclaw-fleet.sh` instead of `openclaw gateway start/stop`:

```bash
# Single instance up/down (disable-safe, KeepAlive won't revive)
openclaw-fleet.sh up critic
openclaw-fleet.sh down critic

# All instances
openclaw-fleet.sh start
openclaw-fleet.sh stop
openclaw-fleet.sh restart
```

**Why not `openclaw gateway stop`?** It only knows about the main service label. Fleet script handles all instances correctly, including disable to prevent KeepAlive auto-restart.

## 1. Install Canonical Tooling

Run once per host:

```bash
~/.codex/skills/openclaw-cluster-manager/scripts/install-openclaw-cluster-tools.sh
```

This installs scripts to `~/.openclaw/` by default.

## 2. Daily Health Check

```bash
~/.openclaw/openclaw-fleet.sh audit
~/.openclaw/openclaw-fleet.sh status
```

Expected:

1. `AUDIT: PASS`
2. Every instance `state = running`
3. Every declared port is listening

## 3. Lifecycle Operations

**Single instance (preferred for targeted control):**

```bash
openclaw-fleet.sh up critic      # enable + bootstrap
openclaw-fleet.sh down critic    # disable + bootout (stays down)
```

**All instances:**

```bash
openclaw-fleet.sh start          # bootstrap all
openclaw-fleet.sh stop           # bootout all
openclaw-fleet.sh restart        # stop + start all
openclaw-fleet.sh enable-boot    # ensure auto-start on login
```

## 4. Add a New Instance

Example: create `reviewer` on port `18791`, clone config from critic, start immediately:

```bash
~/.openclaw/openclaw-add-instance.sh reviewer 18791 --from critic --start
```

Then verify:

```bash
launchctl print gui/$(id -u)/ai.openclaw.reviewer | grep -E "state =|pid =|last exit code"
lsof -nP -iTCP:18791 -sTCP:LISTEN
~/.openclaw/openclaw-fleet.sh audit
```

## 5. Common Recovery

If one instance fails to load:

1. Validate plist:

```bash
plutil -lint ~/Library/LaunchAgents/ai.openclaw.<name>.plist
```

2. Validate state dir + config:

```bash
test -d ~/.openclaw/.openclaw-<name>
test -f ~/.openclaw/.openclaw-<name>/openclaw.json
```

3. Check port conflict:

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN
```

4. Re-bootstrap:

```bash
launchctl bootout gui/$(id -u)/ai.openclaw.<name> || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.<name>.plist
```

## 6. Reporting Format

After any operation, report:

1. Changed files (absolute paths)
2. Instance summary table with label/port/state dir
3. Final audit result
4. Remaining risk list

## 7. Desktop App State Isolation

If you use the OpenClaw desktop app, isolate its global state so it does not pollute the multi-instance root layout:

```bash
~/.openclaw/openclaw-desktop-state.sh setup --relaunch
```

Then validate:

```bash
~/.openclaw/openclaw-desktop-state.sh status
```

Expected:

1. launchd env points to `~/.openclaw/.openclaw-app`
2. `~/.openclaw/exec-approvals.json` is a symlink
3. `~/.openclaw/exec-approvals.sock` is a symlink
4. desktop app process uses `.openclaw-app/exec-approvals.sock`
