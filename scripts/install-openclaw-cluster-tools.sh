#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEST_ROOT="${OPENCLAW_ROOT:-${HOME}/.openclaw}"
FORCE="false"

usage() {
  cat <<'USAGE'
Usage:
  install-openclaw-cluster-tools.sh [options]

Options:
  --root <path>   Target OpenClaw root (default: ~/.openclaw)
  --force         Overwrite existing destination files
  -h, --help      Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      DEST_ROOT="${2:-}"
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

if [[ -z "${DEST_ROOT}" ]]; then
  echo "Destination root cannot be empty." >&2
  exit 1
fi

mkdir -p "${DEST_ROOT}"

install_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [[ ! -f "${src}" ]]; then
    echo "Missing source file: ${src}" >&2
    exit 1
  fi

  if [[ -f "${dst}" && "${FORCE}" != "true" ]]; then
    echo "skip (exists): ${dst}"
    return
  fi

  cp "${src}" "${dst}"
  chmod "${mode}" "${dst}"
  echo "installed: ${dst}"
}

install_doc() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "${src}" ]]; then
    echo "Missing source doc: ${src}" >&2
    exit 1
  fi

  if [[ -f "${dst}" && "${FORCE}" != "true" ]]; then
    echo "skip (exists): ${dst}"
    return
  fi

  cp "${src}" "${dst}"
  chmod 0644 "${dst}"
  echo "installed: ${dst}"
}

install_file "${SKILL_DIR}/scripts/openclaw-fleet.sh" "${DEST_ROOT}/openclaw-fleet.sh" 0755
install_file "${SKILL_DIR}/scripts/openclaw-add-instance.sh" "${DEST_ROOT}/openclaw-add-instance.sh" 0755
install_file "${SKILL_DIR}/scripts/openclaw-migrate-root-state.sh" "${DEST_ROOT}/openclaw-migrate-root-state.sh" 0755

install_doc "${SKILL_DIR}/references/architecture.md" "${DEST_ROOT}/OPENCLAW_CLUSTER_ARCHITECTURE.md"
install_doc "${SKILL_DIR}/references/operations.md" "${DEST_ROOT}/OPENCLAW_CLUSTER_OPERATIONS.md"
install_doc "${SKILL_DIR}/references/migration-playbook.md" "${DEST_ROOT}/OPENCLAW_CLUSTER_MIGRATION.md"
install_doc "${SKILL_DIR}/references/backup-policy.md" "${DEST_ROOT}/OPENCLAW_CLUSTER_BACKUP_POLICY.md"

echo
echo "Installation complete."
echo "Root: ${DEST_ROOT}"
echo "Run: ${DEST_ROOT}/openclaw-fleet.sh audit"
