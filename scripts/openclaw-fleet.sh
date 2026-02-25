#!/usr/bin/env bash
set -euo pipefail

UIDN="$(id -u)"
LAUNCH_DIR="${OPENCLAW_LAUNCH_AGENTS:-${HOME}/Library/LaunchAgents}"
PATTERN="${LAUNCH_DIR}/ai.openclaw.*.plist"
TMP_STATUS="/tmp/openclaw_fleet_status.$$"
TMP_PORT="/tmp/openclaw_fleet_port.$$"

cleanup() {
  rm -f "${TMP_STATUS}" "${TMP_PORT}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage:
  openclaw-fleet.sh list
  openclaw-fleet.sh audit
  openclaw-fleet.sh start
  openclaw-fleet.sh stop
  openclaw-fleet.sh restart
  openclaw-fleet.sh status
  openclaw-fleet.sh enable-boot
  openclaw-fleet.sh up <name>       Enable + bootstrap a single instance (e.g. "critic")
  openclaw-fleet.sh down <name>     Disable + bootout a single instance (stays down)

Environment:
  OPENCLAW_LAUNCH_AGENTS   Override LaunchAgents dir (default: ~/Library/LaunchAgents)
USAGE
}

discover_plists() {
  local found=0
  local f
  for f in ${PATTERN}; do
    if [[ -f "${f}" ]]; then
      echo "${f}"
      found=1
    fi
  done
  if [[ "${found}" -eq 0 ]]; then
    return 1
  fi
}

plist_get() {
  local plist="$1"
  local key="$2"
  plutil -extract "${key}" raw -o - "${plist}" 2>/dev/null || true
}

dup_check() {
  local kind="$1"
  shift

  local dup
  dup="$(printf '%s\n' "$@" | awk 'NF' | sort | uniq -d || true)"
  if [[ -n "${dup}" ]]; then
    while IFS= read -r v; do
      [[ -z "${v}" ]] && continue
      echo "ERROR: duplicate ${kind}: ${v}"
    done <<< "${dup}"
    return 1
  fi

  return 0
}

list_cmd() {
  echo "LABEL\tPORT\tSTATE_DIR\tPLIST"
  discover_plists | while IFS= read -r p; do
    local label port state
    label="$(plist_get "${p}" "Label")"
    port="$(plist_get "${p}" "EnvironmentVariables.OPENCLAW_GATEWAY_PORT")"
    state="$(plist_get "${p}" "EnvironmentVariables.OPENCLAW_STATE_DIR")"
    printf "%s\t%s\t%s\t%s\n" "${label}" "${port}" "${state}" "${p}"
  done
}

audit_cmd() {
  local ok=1
  local labels=()
  local ports=()
  local states=()

  while IFS= read -r p; do
    local label port state run keep out err

    label="$(plist_get "${p}" "Label")"
    port="$(plist_get "${p}" "EnvironmentVariables.OPENCLAW_GATEWAY_PORT")"
    state="$(plist_get "${p}" "EnvironmentVariables.OPENCLAW_STATE_DIR")"
    run="$(plist_get "${p}" "RunAtLoad")"
    keep="$(plist_get "${p}" "KeepAlive")"
    out="$(plist_get "${p}" "StandardOutPath")"
    err="$(plist_get "${p}" "StandardErrorPath")"

    echo "[${label}]"
    echo "  plist: ${p}"
    echo "  port: ${port}"
    echo "  state: ${state}"
    echo "  runAtLoad: ${run}"
    echo "  keepAlive: ${keep}"

    if [[ "${run}" != "1" && "${run}" != "true" ]]; then
      echo "  ERROR: RunAtLoad must be true"
      ok=0
    fi

    if [[ "${keep}" != "1" && "${keep}" != "true" ]]; then
      echo "  ERROR: KeepAlive must be true"
      ok=0
    fi

    if [[ -z "${state}" || ! -d "${state}" ]]; then
      echo "  ERROR: state dir missing"
      ok=0
    fi

    if [[ -n "${state}" && ! -f "${state}/openclaw.json" ]]; then
      echo "  ERROR: missing ${state}/openclaw.json"
      ok=0
    fi

    if [[ -n "${out}" && ! -d "$(dirname "${out}")" ]]; then
      echo "  ERROR: stdout dir missing: $(dirname "${out}")"
      ok=0
    fi

    if [[ -n "${err}" && ! -d "$(dirname "${err}")" ]]; then
      echo "  ERROR: stderr dir missing: $(dirname "${err}")"
      ok=0
    fi

    if [[ -n "${port}" ]] && lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "  listen: yes"
    else
      echo "  listen: no"
    fi

    labels+=("${label}")
    ports+=("${port}")
    states+=("${state}")

    echo
  done < <(discover_plists)

  dup_check "label" "${labels[@]}" || ok=0
  dup_check "port" "${ports[@]}" || ok=0
  dup_check "state_dir" "${states[@]}" || ok=0

  if [[ "${ok}" -eq 1 ]]; then
    echo "AUDIT: PASS"
    return 0
  fi

  echo "AUDIT: FAIL"
  return 1
}

start_cmd() {
  while IFS= read -r p; do
    local label out code
    label="$(plist_get "${p}" "Label")"

    set +e
    out="$(launchctl bootstrap "gui/${UIDN}" "${p}" 2>&1)"
    code=$?
    set -e

    if [[ ${code} -eq 0 ]]; then
      echo "${label} bootstrapped"
      continue
    fi

    if echo "${out}" | grep -qiE "service already loaded|already exists"; then
      echo "${label} already loaded"
      continue
    fi

    echo "${label} bootstrap failed: ${out}" >&2
    return ${code}
  done < <(discover_plists)
}

stop_cmd() {
  while IFS= read -r p; do
    local label
    label="$(plist_get "${p}" "Label")"
    launchctl bootout "gui/${UIDN}/${label}" >/dev/null 2>&1 || true
    echo "${label} booted out"
  done < <(discover_plists)
}

status_cmd() {
  while IFS= read -r p; do
    local label port
    label="$(plist_get "${p}" "Label")"
    port="$(plist_get "${p}" "EnvironmentVariables.OPENCLAW_GATEWAY_PORT")"

    echo "[${label}]"
    if launchctl print "gui/${UIDN}/${label}" >"${TMP_STATUS}" 2>&1; then
      grep -E "state =|pid =|last exit code|runs =" "${TMP_STATUS}" | sed 's/^/  /'
    else
      echo "  not loaded"
    fi

    if [[ -n "${port}" ]] && lsof -nP -iTCP:"${port}" -sTCP:LISTEN >"${TMP_PORT}" 2>/dev/null; then
      sed -n '2,4p' "${TMP_PORT}" | sed 's/^/  /'
    else
      echo "  port ${port} not listening"
    fi

    echo
  done < <(discover_plists)
}

enable_boot_cmd() {
  while IFS= read -r p; do
    local label
    label="$(plist_get "${p}" "Label")"
    launchctl enable "gui/${UIDN}/${label}" >/dev/null 2>&1 || true
    echo "${label} enabled"
  done < <(discover_plists)
}

find_plist_by_name() {
  local name="$1"
  local target="ai.openclaw.${name}"
  while IFS= read -r p; do
    local label
    label="$(plist_get "${p}" "Label")"
    if [[ "${label}" == "${target}" ]]; then
      echo "${p}"
      return 0
    fi
  done < <(discover_plists)
  echo "ERROR: no plist found for '${name}' (looked for label '${target}')" >&2
  return 1
}

up_cmd() {
  local name="${1:?Usage: openclaw-fleet.sh up <name>}"
  local plist label
  plist="$(find_plist_by_name "${name}")"
  label="$(plist_get "${plist}" "Label")"

  launchctl enable "gui/${UIDN}/${label}" 2>/dev/null || true
  local out code
  set +e
  out="$(launchctl bootstrap "gui/${UIDN}" "${plist}" 2>&1)"
  code=$?
  set -e

  if [[ ${code} -eq 0 ]]; then
    echo "${label}: enabled + bootstrapped ✅"
  elif echo "${out}" | grep -qiE "already loaded|already exists"; then
    echo "${label}: already running"
  else
    echo "${label}: bootstrap failed — ${out}" >&2
    return ${code}
  fi

  # Wait briefly and check port
  sleep 2
  local port
  port="$(plist_get "${plist}" "EnvironmentVariables.OPENCLAW_GATEWAY_PORT")"
  if [[ -n "${port}" ]] && lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "${label}: port ${port} listening ✅"
  else
    echo "${label}: port ${port} not yet listening (may need a moment)"
  fi
}

down_cmd() {
  local name="${1:?Usage: openclaw-fleet.sh down <name>}"
  local plist label
  plist="$(find_plist_by_name "${name}")"
  label="$(plist_get "${plist}" "Label")"

  launchctl disable "gui/${UIDN}/${label}" 2>/dev/null || true
  launchctl bootout "gui/${UIDN}/${label}" 2>/dev/null || true
  echo "${label}: disabled + booted out ✅"

  local port
  port="$(plist_get "${plist}" "EnvironmentVariables.OPENCLAW_GATEWAY_PORT")"
  if [[ -n "${port}" ]] && ! lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "${label}: port ${port} confirmed closed ✅"
  else
    echo "${label}: port ${port} still listening (may take a moment to stop)"
  fi
}

cmd="${1:-}"
case "${cmd}" in
  list)
    list_cmd
    ;;
  audit)
    audit_cmd
    ;;
  start)
    start_cmd
    ;;
  stop)
    stop_cmd
    ;;
  restart)
    stop_cmd
    start_cmd
    ;;
  status)
    status_cmd
    ;;
  enable-boot)
    enable_boot_cmd
    ;;
  up)
    up_cmd "${2:-}"
    ;;
  down)
    down_cmd "${2:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
