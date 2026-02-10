# OpenClaw Cluster Architecture (macOS)

## Baseline

- Host: macOS user session managed by `launchd`
- Root container: `~/.openclaw`
- Instance state pattern: `~/.openclaw/.openclaw-<name>`
- LaunchAgents path: `~/Library/LaunchAgents/ai.openclaw.<name>.plist`

Reference migration date for this design: February 10, 2026.

## Why Previous Setups Failed

1. Lock/state collision
   - Two gateways shared one state dir or lock detection scope.
   - Result: one instance was interpreted as "already running" by another.

2. Token configuration mismatch
   - Gateway auth mode expected token but config/token was missing.
   - Result: service started and exited immediately.

3. Lifecycle attached to transient shell/exec process
   - Gateway launched under short-lived execution session.
   - Result: parent timeout killed child gateway unexpectedly.

4. Mixed directory semantics during path refactor
   - Root `~/.openclaw` was partially both container and live state.
   - Result: missing runtime folders, confusing state identity.

## Stable Design

Each instance is defined by one unique tuple:

1. LaunchAgent `Label`
2. Gateway `port`
3. `OPENCLAW_STATE_DIR`
4. Gateway auth `token`

All four values must be unique per instance.

## Required Directory Layout

```text
~/.openclaw/
├── .openclaw-luca/
│   ├── openclaw.json
│   ├── workspace/
│   ├── logs/
│   └── ...
├── .openclaw-critic/
│   ├── openclaw.json
│   ├── workspace/
│   ├── logs/
│   └── ...
├── openclaw-fleet.sh
├── openclaw-add-instance.sh
└── docs...
```

Rules:

1. `~/.openclaw` is a container layer only.
2. Runtime state must live inside `~/.openclaw/.openclaw-*` only.
3. Keep scripts/docs at container root; keep instance state inside instance dirs.

## LaunchAgent Contract

Every instance plist must contain:

1. `RunAtLoad = true`
2. `KeepAlive = true`
3. `ProgramArguments = [node, openclaw-entry, gateway, --port, <port>]`
4. `EnvironmentVariables.OPENCLAW_STATE_DIR = <instance-state-dir>`
5. `StandardOutPath` and `StandardErrorPath` inside the same instance state dir

## Validation Signals

Healthy instance:

1. `launchctl print gui/<uid>/<label>` shows `state = running`
2. `last exit code = (never exited)` or no crash loop indicators
3. `lsof -nP -iTCP:<port> -sTCP:LISTEN` shows listener
4. `openclaw.json` exists in state dir

Cluster-level health:

1. No duplicate labels
2. No duplicate ports
3. No duplicate state dirs
4. Each discovered plist passes launch options checks

## Scale Model

To add instances beyond Luca/Critic:

1. Create `~/.openclaw/.openclaw-<name>`
2. Create `ai.openclaw.<name>.plist`
3. Assign unique port/token
4. Bootstrap service
5. Run fleet audit

No additional architecture change is required for N instances.
