# OpenClaw Cluster Operations

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

Start all discovered instances:

```bash
~/.openclaw/openclaw-fleet.sh start
```

Stop all:

```bash
~/.openclaw/openclaw-fleet.sh stop
```

Restart all:

```bash
~/.openclaw/openclaw-fleet.sh restart
```

Ensure auto-start is enabled:

```bash
~/.openclaw/openclaw-fleet.sh enable-boot
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
