#!/usr/bin/env bash
set -euo pipefail

# GitHub repository setup script
# Usage:
#   setup-repo.sh [options] <owner/repo>
# Options:
#   --dry-run   Show what would be configured without making changes

# Parse arguments
DRY_RUN=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Usage:" >&2
  echo "  $0 [options] <owner/repo>" >&2
  echo "  Options:" >&2
  echo "    --dry-run   Show what would be configured without making changes" >&2
  exit 1
fi

REPO="$1"

# Verify gh CLI is installed and authenticated
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI is not installed. See https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh CLI is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

# Verify repository exists
if ! gh repo view "${REPO}" --json name >/dev/null 2>&1; then
  echo "Error: Repository ${REPO} not found or not accessible." >&2
  exit 1
fi

# Detect visibility
VISIBILITY="$(gh repo view "${REPO}" --json visibility --jq '.visibility')"
echo "Repository: ${REPO} (${VISIBILITY})"
echo ""

run_api() {
  local method="$1"
  local endpoint="$2"
  shift 2

  if [[ "${DRY_RUN}" == true ]]; then
    echo "  [dry-run] ${method} ${endpoint}"
    return 0
  fi

  local err
  if ! err="$(gh api --method "${method}" "${endpoint}" "$@" 2>&1 >/dev/null)"; then
    echo "  ⚠ ${method} ${endpoint} failed: ${err}" >&2
    return 1
  fi
}

run_api_with_input() {
  local method="$1"
  local endpoint="$2"
  local input="$3"

  if [[ "${DRY_RUN}" == true ]]; then
    echo "  [dry-run] ${method} ${endpoint}"
    return 0
  fi

  local err
  if ! err="$(echo "${input}" | gh api --method "${method}" "${endpoint}" --input - 2>&1 >/dev/null)"; then
    echo "  ⚠ ${method} ${endpoint} failed: ${err}" >&2
    return 1
  fi
}

# ── 1. Repository settings ──────────────────────────────────────────
echo "1. Repository settings"

run_api_with_input PATCH "/repos/${REPO}" '{
  "has_wiki": false,
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "delete_branch_on_merge": true,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY",
  "allow_auto_merge": true
}'
echo "  ✓ Merge: squash only, auto-delete branch, auto-merge allowed"
echo "  ✓ Wiki: disabled"

# ── 2. Security settings ────────────────────────────────────────────
echo ""
echo "2. Security settings"

run_api_with_input PATCH "/repos/${REPO}" '{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}' || true
echo "  ✓ Secret scanning: enabled"
echo "  ✓ Push protection: enabled"

run_api PUT "/repos/${REPO}/vulnerability-alerts" || true
echo "  ✓ Dependabot alerts: enabled"

run_api_with_input PATCH "/repos/${REPO}" '{
  "security_and_analysis": {
    "dependabot_security_updates": { "status": "enabled" }
  }
}' || true
echo "  ✓ Dependabot security updates: enabled"

if [[ "${VISIBILITY}" == "PUBLIC" ]]; then
  run_api PUT "/repos/${REPO}/private-vulnerability-reporting" || true
  echo "  ✓ Private vulnerability reporting: enabled"
else
  echo "  - Private vulnerability reporting: skipped (private repo)"
fi

# ── 3. Branch protection (Rulesets) ─────────────────────────────────
echo ""
echo "3. Branch protection (Rulesets)"

RULESET_NAME="main-protection"

# Check if ruleset already exists
EXISTING_RULESET_ID="$(gh api "/repos/${REPO}/rulesets" 2>/dev/null | jq -r --arg name "${RULESET_NAME}" '.[] | select(.name == $name) | .id' 2>/dev/null || true)"

RULESET_BODY='{
  "name": "'"${RULESET_NAME}"'",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request" }
  ]
}'

if [[ -n "${EXISTING_RULESET_ID}" ]]; then
  run_api_with_input PUT "/repos/${REPO}/rulesets/${EXISTING_RULESET_ID}" "${RULESET_BODY}"
  echo "  ✓ Ruleset '${RULESET_NAME}': updated (id: ${EXISTING_RULESET_ID})"
else
  run_api_with_input POST "/repos/${REPO}/rulesets" "${RULESET_BODY}"
  echo "  ✓ Ruleset '${RULESET_NAME}': created"
fi
echo "    - Direct push to main: blocked"
echo "    - Force push: blocked"
echo "    - Branch deletion: blocked"
echo "    - Pull request: required (0 approvals)"
echo "    - Linear history: required"
echo "    - Bypass: none"

# ── 4. Labels ───────────────────────────────────────────────────────
echo ""
echo "4. Labels"

# Default GitHub labels to remove
DEFAULT_LABELS=(
  "bug"
  "documentation"
  "duplicate"
  "enhancement"
  "good first issue"
  "help wanted"
  "invalid"
  "question"
  "wontfix"
)

# Conventional Commits labels
declare -A CC_LABELS=(
  ["feat"]="a2eeef"
  ["fix"]="d73a4a"
  ["docs"]="0075ca"
  ["style"]="e4e669"
  ["refactor"]="c5def5"
  ["perf"]="f9d0c4"
  ["test"]="bfd4f2"
  ["build"]="d4c5f9"
  ["ci"]="0e8a16"
  ["chore"]="cfd3d7"
)

for label in "${DEFAULT_LABELS[@]}"; do
  if [[ "${DRY_RUN}" == true ]]; then
    echo "  [dry-run] delete label: ${label}"
  else
    gh label delete "${label}" --repo "${REPO}" --yes 2>/dev/null || true
  fi
done
echo "  ✓ Default labels: removed"

for label in "${!CC_LABELS[@]}"; do
  color="${CC_LABELS[${label}]}"
  if [[ "${DRY_RUN}" == true ]]; then
    echo "  [dry-run] create label: ${label} (#${color})"
  else
    gh label create "${label}" --repo "${REPO}" --color "${color}" --force 2>/dev/null || true
  fi
done
echo "  ✓ Conventional Commits labels: created"

echo ""
echo "Setup complete."
