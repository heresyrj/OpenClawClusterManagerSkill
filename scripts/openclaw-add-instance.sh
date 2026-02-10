#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-${HOME}/.openclaw}"
LAUNCH_AGENTS="${OPENCLAW_LAUNCH_AGENTS:-${HOME}/Library/LaunchAgents}"
NODE_BIN="${OPENCLAW_NODE_BIN:-$(command -v node || true)}"
OPENCLAW_ENTRY="${OPENCLAW_ENTRY:-}"

usage() {
  cat <<'USAGE'
Usage:
  openclaw-add-instance.sh <name> <port> [options]

Options:
  --from <luca|critic|<name>|/abs/state/dir>  Source config template (default: luca)
  --token <token>                             Gateway auth token (default: auto-generate)
  --start                                     Bootstrap the new LaunchAgent immediately
  --repo-name <name>                          GitHub backup repo name (default: OpenClaw<Name>)
  --repo-owner <owner>                        GitHub owner (default: current gh login)
  --public                                    Create backup repo as public (default: private)
  --no-git-backup                             Skip local git + GitHub backup setup
  --root <path>                               OpenClaw root (default: ~/.openclaw)
  --force                                     Overwrite existing state dir/plist
  -h, --help                                  Show help

Environment overrides:
  OPENCLAW_ROOT
  OPENCLAW_LAUNCH_AGENTS
  OPENCLAW_NODE_BIN
  OPENCLAW_ENTRY
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
  usage
  exit 0
fi

NAME="$1"
PORT="$2"
shift 2

FROM="luca"
TOKEN=""
START_NOW="false"
FORCE="false"
GIT_BACKUP="true"
REPO_NAME=""
REPO_OWNER=""
REPO_VISIBILITY="private"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM="${2:-}"
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    --start)
      START_NOW="true"
      shift
      ;;
    --repo-name)
      REPO_NAME="${2:-}"
      shift 2
      ;;
    --repo-owner)
      REPO_OWNER="${2:-}"
      shift 2
      ;;
    --public)
      REPO_VISIBILITY="public"
      shift
      ;;
    --no-git-backup)
      GIT_BACKUP="false"
      shift
      ;;
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="true"
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

if ! [[ "${NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Invalid name '${NAME}'. Use lowercase letters, numbers, and '-' only." >&2
  exit 1
fi

if [[ "${NAME}" == "gateway" || "${NAME}" == "luca" || "${NAME}" == "critic" ]]; then
  echo "Reserved instance name: ${NAME}" >&2
  exit 1
fi

if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65535 )); then
  echo "Invalid port '${PORT}'." >&2
  exit 1
fi

if lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port ${PORT} is already in use." >&2
  exit 1
fi

mkdir -p "${ROOT}" "${LAUNCH_AGENTS}"

if [[ -z "${NODE_BIN}" || ! -x "${NODE_BIN}" ]]; then
  echo "Node binary not found. Set OPENCLAW_NODE_BIN or install node." >&2
  exit 1
fi

detect_openclaw_entry() {
  local c npm_root

  if [[ -n "${OPENCLAW_ENTRY}" && -f "${OPENCLAW_ENTRY}" ]]; then
    echo "${OPENCLAW_ENTRY}"
    return 0
  fi

  for c in \
    "/opt/homebrew/lib/node_modules/openclaw/dist/index.js" \
    "/usr/local/lib/node_modules/openclaw/dist/index.js"; do
    if [[ -f "${c}" ]]; then
      echo "${c}"
      return 0
    fi
  done

  if command -v npm >/dev/null 2>&1; then
    npm_root="$(npm root -g 2>/dev/null || true)"
    if [[ -n "${npm_root}" && -f "${npm_root}/openclaw/dist/index.js" ]]; then
      echo "${npm_root}/openclaw/dist/index.js"
      return 0
    fi
  fi

  return 1
}

OPENCLAW_ENTRY="$(detect_openclaw_entry || true)"
if [[ -z "${OPENCLAW_ENTRY}" || ! -f "${OPENCLAW_ENTRY}" ]]; then
  echo "OpenClaw entry not found. Set OPENCLAW_ENTRY to openclaw/dist/index.js path." >&2
  exit 1
fi

to_pascal() {
  local in="$1"
  awk -F- '{
    out="";
    for (i=1; i<=NF; i++) {
      out = out toupper(substr($i,1,1)) substr($i,2);
    }
    print out;
  }' <<< "${in}"
}

resolve_source_state() {
  local from="$1"

  case "${from}" in
    luca)
      echo "${ROOT}/.openclaw-luca"
      ;;
    critic)
      echo "${ROOT}/.openclaw-critic"
      ;;
    /*)
      echo "${from}"
      ;;
    *)
      echo "${ROOT}/.openclaw-${from}"
      ;;
  esac
}

SOURCE_STATE="$(resolve_source_state "${FROM}")"
if [[ ! -f "${SOURCE_STATE}/openclaw.json" ]]; then
  echo "Source config not found: ${SOURCE_STATE}/openclaw.json" >&2
  exit 1
fi

STATE_DIR="${ROOT}/.openclaw-${NAME}"
PLIST_PATH="${LAUNCH_AGENTS}/ai.openclaw.${NAME}.plist"
LABEL="ai.openclaw.${NAME}"
MARKER="openclaw-${NAME}"

if [[ -z "${TOKEN}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    TOKEN="$(openssl rand -hex 24)"
  else
    TOKEN="openclaw-${NAME}-$(date +%s)"
  fi
fi

if [[ "${FORCE}" != "true" ]]; then
  if [[ -e "${STATE_DIR}" ]]; then
    echo "State dir already exists: ${STATE_DIR} (use --force to overwrite)" >&2
    exit 1
  fi
  if [[ -e "${PLIST_PATH}" ]]; then
    echo "LaunchAgent already exists: ${PLIST_PATH} (use --force to overwrite)" >&2
    exit 1
  fi
else
  rm -rf "${STATE_DIR}"
  rm -f "${PLIST_PATH}"
fi

mkdir -p \
  "${STATE_DIR}/logs" \
  "${STATE_DIR}/workspace" \
  "${STATE_DIR}/cron" \
  "${STATE_DIR}/canvas" \
  "${STATE_DIR}/agents" \
  "${STATE_DIR}/identity"

cp "${SOURCE_STATE}/openclaw.json" "${STATE_DIR}/openclaw.json"
if [[ -f "${SOURCE_STATE}/.env" ]]; then
  cp "${SOURCE_STATE}/.env" "${STATE_DIR}/.env"
fi

"${NODE_BIN}" -e '
const fs = require("fs");
const cfgPath = process.argv[1];
const instance = process.argv[2];
const port = Number(process.argv[3]);
const token = process.argv[4];
const stateDir = process.argv[5];
const workspace = stateDir + "/workspace";
const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));

cfg.gateway = cfg.gateway && typeof cfg.gateway === "object" ? cfg.gateway : {};
cfg.gateway.port = port;
cfg.gateway.mode = cfg.gateway.mode || "local";
cfg.gateway.bind = cfg.gateway.bind || "loopback";
cfg.gateway.auth = cfg.gateway.auth && typeof cfg.gateway.auth === "object" ? cfg.gateway.auth : {};
cfg.gateway.auth.token = token;

if (cfg.models && cfg.models.defaults && typeof cfg.models.defaults === "object") {
  cfg.models.defaults.workspace = workspace;
}

if (cfg.memory && cfg.memory.qmd && Array.isArray(cfg.memory.qmd.paths)) {
  cfg.memory.qmd.paths = cfg.memory.qmd.paths.map((entry, idx) => {
    if (!entry || typeof entry !== "object") return entry;
    if (idx === 0 || entry.name === "workspace-docs") {
      return { ...entry, path: workspace };
    }
    return entry;
  });
}

cfg.meta = cfg.meta && typeof cfg.meta === "object" ? cfg.meta : {};
cfg.meta.lastTouchedAt = new Date().toISOString();
cfg.meta.instanceName = instance;

fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + "\n");
' "${STATE_DIR}/openclaw.json" "${NAME}" "${PORT}" "${TOKEN}" "${STATE_DIR}"

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
      <string>${NODE_BIN}</string>
      <string>${OPENCLAW_ENTRY}</string>
      <string>gateway</string>
      <string>--port</string>
      <string>${PORT}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
      <key>HOME</key>
      <string>${HOME}</string>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
      <key>OPENCLAW_GATEWAY_PORT</key>
      <string>${PORT}</string>
      <key>OPENCLAW_GATEWAY_TOKEN</key>
      <string>${TOKEN}</string>
      <key>OPENCLAW_LAUNCHD_LABEL</key>
      <string>${LABEL}</string>
      <key>OPENCLAW_SERVICE_KIND</key>
      <string>gateway</string>
      <key>OPENCLAW_SERVICE_MARKER</key>
      <string>${MARKER}</string>
      <key>OPENCLAW_STATE_DIR</key>
      <string>${STATE_DIR}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${STATE_DIR}/logs/gateway.log</string>
    <key>StandardErrorPath</key>
    <string>${STATE_DIR}/logs/gateway.err.log</string>
  </dict>
</plist>
PLIST

plutil -lint "${PLIST_PATH}" >/dev/null

GIT_REMOTE_URL=""
if [[ "${GIT_BACKUP}" == "true" ]]; then
  (
    cd "${STATE_DIR}"

    if [[ ! -d .git ]]; then
      git init -b main >/dev/null
    fi

    cat > .gitignore <<'GITIGNORE'
# Secrets
.env

# Backup variants
*.bak
*.bak.*
*.backup
*.backup.*
.backup-*/
openclaw.json.backup*
openclaw.json.*.bak*
openclaw.json.*backup*

# Runtime/generated data
logs/
media/
agents/*/qmd/xdg-cache/
browser/openclaw/user-data/
extensions/**/node_modules/

# Embedded workspace git metadata backup folder
.workspace-embedded-git-backup-*/

# Optional legacy nested workspace
workspace-engineer/
GITIGNORE

    if [[ -d workspace/.git ]]; then
      ts="$(date +%Y%m%d%H%M%S)"
      mv workspace/.git ".workspace-embedded-git-backup-${ts}"
    fi

    git add -A
    if ! git diff --cached --quiet; then
      git commit -m "Initialize OpenClaw ${NAME} state backup repo" >/dev/null
    fi

    if command -v gh >/dev/null 2>&1 && gh auth status -h github.com >/dev/null 2>&1; then
      owner="${REPO_OWNER}"
      if [[ -z "${owner}" ]]; then
        owner="$(gh api user -q .login)"
      fi

      repo_name="${REPO_NAME}"
      if [[ -z "${repo_name}" ]]; then
        repo_name="OpenClaw$(to_pascal "${NAME}")"
      fi

      full="${owner}/${repo_name}"
      url="https://github.com/${full}.git"

      if ! gh repo view "${full}" >/dev/null 2>&1; then
        if [[ "${REPO_VISIBILITY}" == "public" ]]; then
          gh repo create "${full}" --public --description "OpenClaw ${NAME} local state backup" >/dev/null
        else
          gh repo create "${full}" --private --description "OpenClaw ${NAME} local state backup" >/dev/null
        fi
      fi

      if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "${url}"
      else
        git remote add origin "${url}"
      fi

      git push -u origin main >/dev/null
      echo "${url}" > "${STATE_DIR}/.git-remote-url"
    fi
  )

  if [[ -f "${STATE_DIR}/.git-remote-url" ]]; then
    GIT_REMOTE_URL="$(cat "${STATE_DIR}/.git-remote-url")"
    rm -f "${STATE_DIR}/.git-remote-url"
  fi
fi

if [[ "${START_NOW}" == "true" ]]; then
  launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"
fi

echo "Created instance: ${NAME}"
echo "Label:           ${LABEL}"
echo "State dir:       ${STATE_DIR}"
echo "Port:            ${PORT}"
echo "LaunchAgent:     ${PLIST_PATH}"
echo "Gateway token:   ${TOKEN}"
if [[ "${GIT_BACKUP}" == "true" ]]; then
  if [[ -n "${GIT_REMOTE_URL}" ]]; then
    echo "Backup git:      ${GIT_REMOTE_URL}"
  else
    echo "Backup git:      local git initialized (GitHub remote not configured)"
  fi
else
  echo "Backup git:      skipped (--no-git-backup)"
fi
if [[ "${START_NOW}" == "true" ]]; then
  echo "Status:          bootstrapped"
else
  echo "Start command:   launchctl bootstrap gui/$(id -u) ${PLIST_PATH}"
fi
