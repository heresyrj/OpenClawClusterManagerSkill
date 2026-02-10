#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-${HOME}/.openclaw}"
INSTANCE=""
LAUNCH_DIR="${OPENCLAW_LAUNCH_AGENTS:-${HOME}/Library/LaunchAgents}"
UPDATE_LABEL="ai.openclaw.gateway"
START_AFTER="false"
DRY_RUN="false"

usage() {
  cat <<'USAGE'
Usage:
  openclaw-migrate-root-state.sh --instance <name> [options]

Options:
  --instance <name>   Target instance suffix (e.g. luca => .openclaw-luca)
  --root <path>       OpenClaw root path (default: ~/.openclaw)
  --label <label>     LaunchAgent label to retarget state dir (default: ai.openclaw.gateway)
  --start             Start all OpenClaw launch agents after migration
  --dry-run           Show planned moves only
  -h, --help          Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance)
      INSTANCE="${2:-}"
      shift 2
      ;;
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --label)
      UPDATE_LABEL="${2:-}"
      shift 2
      ;;
    --start)
      START_AFTER="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${INSTANCE}" ]]; then
  echo "--instance is required." >&2
  usage
  exit 1
fi

if ! [[ "${INSTANCE}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Invalid instance name: ${INSTANCE}" >&2
  exit 1
fi

if [[ ! -d "${ROOT}" ]]; then
  echo "Root dir not found: ${ROOT}" >&2
  exit 1
fi

TARGET_DIR="${ROOT}/.openclaw-${INSTANCE}"
mkdir -p "${TARGET_DIR}"

stop_all_openclaw() {
  local p label
  for p in "${LAUNCH_DIR}"/ai.openclaw.*.plist; do
    [[ -f "${p}" ]] || continue
    label="$(plutil -extract Label raw -o - "${p}" 2>/dev/null || true)"
    [[ -z "${label}" ]] && continue
    launchctl bootout "gui/$(id -u)/${label}" >/dev/null 2>&1 || true
    echo "bootout: ${label}"
  done
}

move_item() {
  local src="$1"
  local base
  base="$(basename "${src}")"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "would move: ${src} -> ${TARGET_DIR}/${base}"
    return
  fi

  mv "${src}" "${TARGET_DIR}/${base}"
  echo "moved: ${base}"
}

find_plist_by_label() {
  local label="$1"
  local p l
  for p in "${LAUNCH_DIR}"/ai.openclaw.*.plist; do
    [[ -f "${p}" ]] || continue
    l="$(plutil -extract Label raw -o - "${p}" 2>/dev/null || true)"
    if [[ "${l}" == "${label}" ]]; then
      echo "${p}"
      return 0
    fi
  done
  return 1
}

update_plist_paths() {
  local plist="$1"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "would update plist state dir: ${plist} -> ${TARGET_DIR}"
    return
  fi

  plutil -replace EnvironmentVariables.OPENCLAW_STATE_DIR -string "${TARGET_DIR}" "${plist}"
  plutil -replace StandardOutPath -string "${TARGET_DIR}/logs/gateway.log" "${plist}"
  plutil -replace StandardErrorPath -string "${TARGET_DIR}/logs/gateway.err.log" "${plist}"
  plutil -lint "${plist}" >/dev/null
  echo "updated plist: ${plist}"
}

# Keep these root-level files in container root.
keep_at_root() {
  local base="$1"
  case "${base}" in
    .openclaw-*) return 0 ;;
    openclaw-fleet.sh|openclaw-add-instance.sh|openclaw-migrate-root-state.sh) return 0 ;;
    OPENCLAW_CLUSTER_*.md|MULTI_INSTANCE_*.md) return 0 ;;
    .DS_Store) return 0 ;;
    *) return 1 ;;
  esac
}

# Move common legacy runtime files from root into target instance dir.
move_legacy_state() {
  local entries=(
    agents browser canvas credentials cron devices extensions identity keys logs media memory private subagents
    workspace workspace-engineer
    openclaw.json openclaw.json.*
    .env update-check.json exec-approvals.json exec-approvals.sock
  )

  local pattern item base
  for pattern in "${entries[@]}"; do
    for item in "${ROOT}"/${pattern}; do
      [[ -e "${item}" ]] || continue
      base="$(basename "${item}")"

      if keep_at_root "${base}"; then
        continue
      fi

      if [[ "${item}" == "${TARGET_DIR}" ]]; then
        continue
      fi

      move_item "${item}"
    done
  done
}

echo "Stopping OpenClaw launchd services..."
stop_all_openclaw

echo "Migrating legacy root state into: ${TARGET_DIR}"
move_legacy_state

if [[ "${DRY_RUN}" != "true" ]]; then
  mkdir -p "${TARGET_DIR}/logs" "${TARGET_DIR}/workspace"
fi

if plist_path="$(find_plist_by_label "${UPDATE_LABEL}" 2>/dev/null || true)"; then
  if [[ -n "${plist_path}" ]]; then
    update_plist_paths "${plist_path}"
  else
    echo "warning: label not found, skipped plist update: ${UPDATE_LABEL}" >&2
  fi
else
  echo "warning: label not found, skipped plist update: ${UPDATE_LABEL}" >&2
fi

if [[ "${START_AFTER}" == "true" ]]; then
  echo "Starting OpenClaw launchd services..."
  for p in "${LAUNCH_DIR}"/ai.openclaw.*.plist; do
    [[ -f "${p}" ]] || continue
    launchctl bootstrap "gui/$(id -u)" "${p}" >/dev/null 2>&1 || true
  done
fi

echo
echo "Migration complete."
echo "Target instance dir: ${TARGET_DIR}"
echo "Next: run openclaw-fleet.sh audit && openclaw-fleet.sh status"
