---
name: openclaw-cluster-manager
description: Manage OpenClaw multi-instance clusters on macOS. Use when creating, migrating, auditing, repairing, or scaling local OpenClaw gateway instances (for example Luca, Critic, and future instances), including LaunchAgent lifecycle, path refactors, state isolation, and per-instance Git backup policy enforcement.
---

# OpenClaw Cluster Manager

## Overview

Use this skill to operate OpenClaw as a stable multi-instance cluster on one macOS host.
Enforce launchd-based lifecycle management, strict instance isolation, and repeatable backup policy.

## Workflow

1. Detect current cluster state.
2. Audit invariants (`label`, `port`, `state_dir`, `token` uniqueness).
3. Repair launchd/service issues before changing structure.
4. Add or migrate instances with scripts instead of ad-hoc shell commands.
5. Enforce Git backup policy per instance (`workspace` included, `.env` excluded).
6. Isolate desktop app global state (`.openclaw-app`) from gateway instance states.
7. Re-audit and report final status.

## Core Invariants

1. Use one LaunchAgent plist per instance.
2. Keep `Label`, `OPENCLAW_GATEWAY_PORT`, `OPENCLAW_STATE_DIR`, `OPENCLAW_GATEWAY_TOKEN` unique per instance.
3. Set `RunAtLoad=true` and `KeepAlive=true` on every instance plist.
4. Keep each instance fully self-contained in `~/.openclaw/.openclaw-<name>/`.
5. Do not manage long-running gateways from transient exec/shell sessions.
6. Treat desktop app process state as a separate scope (`~/.openclaw/.openclaw-app`) and keep compatibility symlinks for fixed exec-approvals paths.

## Scripts

Use scripts from `scripts/` directly, or install them into `~/.openclaw`:

1. `scripts/install-openclaw-cluster-tools.sh`
   - Copy canonical scripts/docs into a target root (default `~/.openclaw`).
2. `scripts/openclaw-fleet.sh`
   - Fleet-level operations across all `ai.openclaw.*.plist`: `list|audit|start|stop|restart|status|enable-boot`.
3. `scripts/openclaw-add-instance.sh`
   - Create a new instance (state dir + plist + config + optional GitHub backup repo).
4. `scripts/openclaw-migrate-root-state.sh`
   - Move legacy flat root state into `~/.openclaw/.openclaw-<instance>` safely.
5. `scripts/openclaw-desktop-state.sh`
   - Isolate desktop app state to `~/.openclaw/.openclaw-app`, migrate approvals/session artifacts, and maintain compatibility symlinks.

## Required Operation Order

1. Run `openclaw-fleet.sh audit` first.
2. If audit fails, fix root causes before adding/migrating instances.
3. After any create/migrate step, run `openclaw-fleet.sh status` and confirm ports are listening.
4. Run Git backup checks from `references/backup-policy.md` before pushing.
5. If desktop app is used, run `openclaw-desktop-state.sh status` and ensure approvals/socket point to `.openclaw-app`.

## References

Read only what is needed:

1. `references/architecture.md`
   - Why this structure is stable and where failures come from.
2. `references/operations.md`
   - Day-2 command playbook and validation checklist.
3. `references/migration-playbook.md`
   - Root-state refactor procedure and rollback.
4. `references/backup-policy.md`
   - What to include/exclude in per-instance backup repos.
5. `references/desktop-app-state.md`
   - Desktop app state isolation model, exec-approvals migration, and upgrade-safe compatibility strategy.

## Response Contract

When using this skill for a live operation:

1. Show exact commands executed.
2. Report affected absolute paths.
3. Report final per-instance status with label, port, state dir, and launchd state.
4. Flag unresolved risks explicitly (for example unresolved channel/cache issues outside infra scope).
