#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-${HOME}/.openclaw}"
APP_STATE_DIR="${OPENCLAW_APP_STATE_DIR:-${ROOT}/.openclaw-app}"
LAUNCH_DIR="${OPENCLAW_LAUNCH_AGENTS:-${HOME}/Library/LaunchAgents}"
ENV_LABEL="${OPENCLAW_DESKTOP_ENV_LABEL:-com.openclaw.desktop-env}"
ENV_PLIST="${LAUNCH_DIR}/${ENV_LABEL}.plist"
APP_NAME="${OPENCLAW_DESKTOP_APP_NAME:-OpenClaw}"
RELAUNCH="false"

ROOT_AGENTS="${ROOT}/agents"
APP_AGENTS="${APP_STATE_DIR}/agents"
ROOT_JSON="${ROOT}/exec-approvals.json"
APP_JSON="${APP_STATE_DIR}/exec-approvals.json"
ROOT_SOCK="${ROOT}/exec-approvals.sock"
APP_SOCK="${APP_STATE_DIR}/exec-approvals.sock"

usage() {
  cat <<'USAGE'
Usage:
  openclaw-desktop-state.sh setup [options]
  openclaw-desktop-state.sh status [options]

Commands:
  setup    Configure desktop app state isolation under .openclaw-app
  status   Show current desktop app state wiring and runtime checks

Options:
  --root <path>            OpenClaw root (default: ~/.openclaw)
  --app-state-dir <path>   Desktop app state dir (default: <root>/.openclaw-app)
  --app-name <name>        macOS app name for relaunch (default: OpenClaw)
  --relaunch               Quit + relaunch desktop app during setup
  -h, --help               Show help

Environment:
  OPENCLAW_ROOT
  OPENCLAW_APP_STATE_DIR
  OPENCLAW_LAUNCH_AGENTS
  OPENCLAW_DESKTOP_ENV_LABEL
  OPENCLAW_DESKTOP_APP_NAME
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    setup|status)
      CMD="$1"
      shift
      ;;
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --app-state-dir)
      APP_STATE_DIR="${2:-}"
      shift 2
      ;;
    --app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --relaunch)
      RELAUNCH="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

CMD="${CMD:-}"
if [[ -z "${CMD}" ]]; then
  usage
  exit 1
fi

# Recompute derived paths in case --root/--app-state-dir were passed.
APP_STATE_DIR="${OPENCLAW_APP_STATE_DIR:-${APP_STATE_DIR}}"
ROOT_AGENTS="${ROOT}/agents"
APP_AGENTS="${APP_STATE_DIR}/agents"
ROOT_JSON="${ROOT}/exec-approvals.json"
APP_JSON="${APP_STATE_DIR}/exec-approvals.json"
ROOT_SOCK="${ROOT}/exec-approvals.sock"
APP_SOCK="${APP_STATE_DIR}/exec-approvals.sock"

ensure_dirs() {
  mkdir -p "${ROOT}" "${APP_STATE_DIR}" "${APP_AGENTS}" "${APP_STATE_DIR}/logs" "${LAUNCH_DIR}"
}

merge_agents_into_app() {
  if [[ -d "${ROOT_AGENTS}" && ! -L "${ROOT_AGENTS}" ]]; then
    rsync -a "${ROOT_AGENTS}/" "${APP_AGENTS}/"
  fi
}

ensure_app_json() {
  local ts
  ts="$(date +%Y%m%d%H%M%S)"

  if [[ ! -f "${APP_JSON}" ]]; then
    if [[ -f "${ROOT_JSON}" ]]; then
      cp -f "${ROOT_JSON}" "${APP_JSON}"
    else
      cat > "${APP_JSON}" <<'EOF'
{
  "version": 1,
  "agents": {}
}
EOF
    fi
  fi

  cp -f "${APP_JSON}" "${APP_JSON}.backup-${ts}"

  python3 - "${APP_JSON}" "${APP_SOCK}" <<'PY'
import json
import os
import secrets
import sys

json_path = sys.argv[1]
socket_path = sys.argv[2]

with open(json_path, "r", encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict):
    data = {"version": 1, "agents": {}}

data["version"] = 1
agents = data.get("agents")
if not isinstance(agents, dict):
    data["agents"] = {}

socket = data.get("socket")
if not isinstance(socket, dict):
    socket = {}
socket["path"] = socket_path
if not socket.get("token"):
    socket["token"] = secrets.token_urlsafe(24)
data["socket"] = socket

with open(json_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

  chmod 600 "${APP_JSON}"
}

set_root_symlinks() {
  python3 - "${ROOT_AGENTS}" "${APP_AGENTS}" "${ROOT_JSON}" "${APP_JSON}" "${ROOT_SOCK}" "${APP_SOCK}" <<'PY'
import os
import shutil
import sys

root_agents, app_agents, root_json, app_json, root_sock, app_sock = sys.argv[1:]

def replace_with_symlink(dst: str, src: str) -> None:
    if os.path.lexists(dst):
        if os.path.isdir(dst) and not os.path.islink(dst):
            shutil.rmtree(dst)
        else:
            os.unlink(dst)
    os.symlink(src, dst)

replace_with_symlink(root_agents, app_agents)
replace_with_symlink(root_json, app_json)
replace_with_symlink(root_sock, app_sock)
PY
}

write_env_launchagent() {
  # Retire known legacy labels to avoid confusion.
  launchctl bootout "gui/$(id -u)/ai.openclaw.desktop-env" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/com.jianruan.openclaw-desktop-env" >/dev/null 2>&1 || true
  rm -f "${LAUNCH_DIR}/ai.openclaw.desktop-env.plist" "${LAUNCH_DIR}/com.jianruan.openclaw-desktop-env.plist"

  cat > "${ENV_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${ENV_LABEL}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/sh</string>
      <string>-c</string>
      <string>/bin/launchctl setenv OPENCLAW_STATE_DIR ${APP_STATE_DIR}; /bin/launchctl setenv CLAWDBOT_STATE_DIR ${APP_STATE_DIR}</string>
    </array>
    <key>StandardOutPath</key>
    <string>${APP_STATE_DIR}/logs/desktop-env.log</string>
    <key>StandardErrorPath</key>
    <string>${APP_STATE_DIR}/logs/desktop-env.err.log</string>
  </dict>
</plist>
EOF

  plutil -lint "${ENV_PLIST}" >/dev/null
  launchctl bootout "gui/$(id -u)/${ENV_LABEL}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "${ENV_PLIST}"
  launchctl setenv OPENCLAW_STATE_DIR "${APP_STATE_DIR}"
  launchctl setenv CLAWDBOT_STATE_DIR "${APP_STATE_DIR}"
}

relaunch_app_if_requested() {
  if [[ "${RELAUNCH}" != "true" ]]; then
    return
  fi

  osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
  sleep 1
  open -a "${APP_NAME}" >/dev/null 2>&1 || true
}

status_cmd() {
  echo "Desktop app state:"
  echo "  root: ${ROOT}"
  echo "  app_state_dir: ${APP_STATE_DIR}"
  echo "  env_label: ${ENV_LABEL}"
  echo

  echo "launchctl env:"
  echo "  OPENCLAW_STATE_DIR=$(launchctl getenv OPENCLAW_STATE_DIR)"
  echo "  CLAWDBOT_STATE_DIR=$(launchctl getenv CLAWDBOT_STATE_DIR)"
  echo

  echo "root links:"
  ls -ld "${ROOT_AGENTS}" "${ROOT_JSON}" "${ROOT_SOCK}" 2>/dev/null || true
  echo

  echo "approvals socket in JSON:"
  python3 - "${APP_JSON}" <<'PY'
import json
import sys
p = sys.argv[1]
try:
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    print("  file:", p)
    print("  socket.path:", data.get("socket", {}).get("path"))
except Exception as e:
    print("  error:", e)
PY
  echo

  echo "desktop app process:"
  ps -ax -o pid,command | grep -F "/Applications/OpenClaw.app/Contents/MacOS/OpenClaw" | grep -v grep || true
  echo

  echo "open socket owners:"
  lsof "${ROOT_SOCK}" "${APP_SOCK}" 2>/dev/null || true
}

setup_cmd() {
  ensure_dirs
  merge_agents_into_app
  ensure_app_json
  write_env_launchagent
  set_root_symlinks
  relaunch_app_if_requested
  status_cmd
}

case "${CMD}" in
  setup)
    setup_cmd
    ;;
  status)
    status_cmd
    ;;
  *)
    usage
    exit 1
    ;;
esac
