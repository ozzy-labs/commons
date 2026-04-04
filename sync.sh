#!/usr/bin/env bash
set -euo pipefail

# ai-config sync script
# Usage: sync.sh <target-repo-path>
# Copies claude/ -> .claude/ in the target repository

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/claude"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-repo-path>" >&2
  exit 1
fi

TARGET_DIR="$1"

if [[ ! -d "${TARGET_DIR}/.git" ]]; then
  echo "Error: ${TARGET_DIR} is not a git repository" >&2
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "Error: claude/ directory not found at ${SOURCE_DIR}" >&2
  exit 1
fi

copied=0

while IFS= read -r src_path; do
  rel_path="${src_path#"${SOURCE_DIR}/"}"
  dest_path="${TARGET_DIR}/.claude/${rel_path}"

  mkdir -p "$(dirname "${dest_path}")"
  cp "${src_path}" "${dest_path}"
  echo "  copy: claude/${rel_path} -> .claude/${rel_path}"
  copied=$((copied + 1))
done < <(find "${SOURCE_DIR}" -type f | sort)

echo ""
echo "Sync complete: ${copied} files copied"
