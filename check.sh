#!/usr/bin/env bash
set -euo pipefail

# commons check script
# Usage:
#   check.sh <target-repo-path>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:-.}"

if [[ ! -d "${TARGET_DIR}/.git" ]]; then
  echo "Error: ${TARGET_DIR} is not a git repository" >&2
  exit 1
fi

echo "OzzyLabs Commons Health Check"
echo "Target: ${TARGET_DIR}"
echo "------------------------------"

# 1. Sync Status
echo "1. Sync Status"
if "${SCRIPT_DIR}/sync.sh" --check "${TARGET_DIR}" >/dev/null 2>&1; then
  echo "  [PASS] All shared files are up to date (or pinned)"
else
  echo "  [FAIL] Files are out of sync. Run 'sync.sh ${TARGET_DIR}'"
fi

# 2. Mandatory Files
echo "2. Mandatory Files"
MANDATORY_FILES=("LICENSE" "CONTRIBUTING.md" "SECURITY.md" "README.md" ".gitignore" ".editorconfig" "AGENTS.md")
for f in "${MANDATORY_FILES[@]}"; do
  if [[ -f "${TARGET_DIR}/${f}" ]]; then
    echo "  [PASS] ${f} exists"
  else
    echo "  [FAIL] ${f} is missing"
  fi
done

# 3. Markers
echo "3. Markers"
# Check AGENTS.md for skills markers
if grep -q "<!-- begin: @ozzylabs/skills -->" "${TARGET_DIR}/AGENTS.md" 2>/dev/null; then
  echo "  [PASS] AGENTS.md has @ozzylabs/skills markers"
else
  echo "  [WARN] AGENTS.md is missing @ozzylabs/skills markers (skills sync may fail)"
fi

# Check files that should have commons markers
MARKER_BEGIN="<!-- begin: ozzy-labs/commons -->"
MARKER_BEGIN_HASH="# begin: ozzy-labs/commons"

while IFS= read -r src_path; do
  rel_path="${src_path#"${SCRIPT_DIR}/dist/"}"
  dest_path="${TARGET_DIR}/${rel_path}"

  if [[ ! -f "${dest_path}" ]]; then continue; fi

  if grep -q "${MARKER_BEGIN}" "${src_path}" || grep -q "${MARKER_BEGIN_HASH}" "${src_path}"; then
    if grep -q "${MARKER_BEGIN}" "${dest_path}" || grep -q "${MARKER_BEGIN_HASH}" "${dest_path}"; then
      echo "  [PASS] ${rel_path} has markers"
    else
      echo "  [WARN] ${rel_path} is missing commons markers (partial sync disabled)"
    fi
  fi
done < <(find "${SCRIPT_DIR}/dist" -type f | sort)

# 4. Security
echo "4. Security"
if [[ -f "${TARGET_DIR}/lefthook.yaml" ]] || [[ -f "${TARGET_DIR}/lefthook-base.yaml" ]]; then
  if grep -q "gitleaks" "${TARGET_DIR}/lefthook.yaml" 2>/dev/null || grep -q "gitleaks" "${TARGET_DIR}/lefthook-base.yaml" 2>/dev/null; then
    echo "  [PASS] Gitleaks is configured in Lefthook"
  else
    echo "  [FAIL] Gitleaks is NOT configured in Lefthook"
  fi
else
  echo "  [FAIL] Lefthook is not configured"
fi

echo "------------------------------"
echo "Check complete."
