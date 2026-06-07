#!/usr/bin/env bash
set -euo pipefail

# commons/scripts/migrate-consumer.sh
#
# 14 consumer を user skills only モデルへ強制移行する driver (ozzy-labs/skills#96
# / #100 / handbook ADR-0027)。target consumer を clone し、以下を削除する PR を
# 作成する:
#
#   - .claude/skills/<汎用 10 種>/        (drive / implement / ship / review /
#                                          commit / pr / lint / test /
#                                          commit-conventions / lint-rules)
#   - .agents/skills/<汎用 10 種>/        (同上)
#   - .commons/sync.yaml の skills_adapters / skills_commit セクション
#
# 利用者は PR merge 後に `npx @ozzylabs/skills install` を 1 度実行する。
#
# Usage:
#   migrate-consumer.sh \
#     --target <owner/repo> \
#     [--dry-run] \
#     [--auto-merge] \
#     [--base-branch <branch>]
#
# JSON 戻り値 (stdout):
#   {
#     "target": "ozzy-labs/<repo>",
#     "branch": "<branch>",
#     "pr_url": "<URL or null>",
#     "pr_number": <N or null>,
#     "status": "merged" | "merge-ready" | "auto-merge enabled"
#               | "no-change" | "dry-run" | "failed",
#     "removed_skills": [<name>...],
#     "removed_yaml_fields": [<field>...],
#     "error": "<message or null>"
#   }

TARGET=""
DRY_RUN=false
AUTO_MERGE=false
BASE_BRANCH="main"

while [[ $# -gt 0 ]]; do
  arg="$1"
  val=""
  if [[ "$arg" == --*=* ]]; then
    val="${arg#*=}"
    arg="${arg%%=*}"
  fi
  case "$arg" in
  --target)
    TARGET="${val:-$2}"
    [[ -z "$val" ]] && shift
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --auto-merge)
    AUTO_MERGE=true
    shift
    ;;
  --base-branch)
    BASE_BRANCH="${val:-$2}"
    [[ -z "$val" ]] && shift
    shift
    ;;
  -h | --help)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 0
    ;;
  *)
    echo "ERROR: Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "ERROR: --target is required (e.g. --target=ozzy-labs/agentyard)" >&2
  exit 1
fi
if [[ ! "$TARGET" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
  echo "ERROR: --target must be in 'owner/repo' format (got '$TARGET')" >&2
  exit 1
fi

GENERIC_SKILLS=(
  drive
  implement
  ship
  review
  commit
  pr
  lint
  test
  commit-conventions
  lint-rules
)

# Internal-use skills (health/topics/phase-issue) も過去 sync の残骸として
# 14 consumer に配布されたが、ADR-0027 で skills/commons 内部運用のみと決定。
# migrate 経由で同時に清掃する。
INTERNAL_SKILLS=(
  health
  topics
  phase-issue
)

BRANCH="chore/migrate-to-user-skills"

emit_json() {
  local status="$1"
  local pr_url="${2:-null}"
  local pr_number="${3:-null}"
  local error="${4:-null}"
  local removed_skills_json="${5:-[]}"
  local removed_yaml_json="${6:-[]}"
  [[ "$pr_url" != "null" ]] && pr_url="\"$pr_url\""
  [[ "$error" != "null" ]] && error="\"${error//\"/\\\"}\""
  cat <<JSON
{
  "target": "$TARGET",
  "branch": "$BRANCH",
  "pr_url": $pr_url,
  "pr_number": $pr_number,
  "status": "$status",
  "removed_skills": $removed_skills_json,
  "removed_yaml_fields": $removed_yaml_json,
  "error": $error
}
JSON
}

trap_err() {
  local msg="${1:-unknown error}"
  emit_json "failed" "null" "null" "$msg"
  exit 1
}

TMPDIR="$(mktemp -d -t migrate-consumer-XXXXXX)"
# shellcheck disable=SC2329  # invoked via trap below
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

CONSUMER_DIR="$TMPDIR/consumer"

if ! git clone --depth 50 --branch "$BASE_BRANCH" "https://github.com/${TARGET}.git" "$CONSUMER_DIR" >&2; then
  trap_err "git clone failed for $TARGET"
fi

cd "$CONSUMER_DIR"

REMOVED_SKILLS=()
REMOVED_YAML_FIELDS=()
ANY_CHANGE=false

for skill in "${GENERIC_SKILLS[@]}" "${INTERNAL_SKILLS[@]}"; do
  if [[ -d ".claude/skills/$skill" ]]; then
    REMOVED_SKILLS+=("$skill")
    if ! $DRY_RUN; then
      git rm -rq ".claude/skills/$skill"
    fi
    ANY_CHANGE=true
  fi
  if [[ -d ".agents/skills/$skill" ]]; then
    if ! $DRY_RUN; then
      git rm -rq ".agents/skills/$skill"
    fi
    ANY_CHANGE=true
  fi
done

SYNC_YAML=".commons/sync.yaml"
if [[ -f "$SYNC_YAML" ]]; then
  if grep -q '^skills_commit:' "$SYNC_YAML"; then
    REMOVED_YAML_FIELDS+=("skills_commit")
    if ! $DRY_RUN; then
      sed -i.bak '/^skills_commit:/d' "$SYNC_YAML"
      rm -f "${SYNC_YAML}.bak"
    fi
    ANY_CHANGE=true
  fi
  if grep -q '^skills_adapters:' "$SYNC_YAML"; then
    REMOVED_YAML_FIELDS+=("skills_adapters")
    if ! $DRY_RUN; then
      python3 -c "
with open('$SYNC_YAML', 'r') as f:
    lines = f.readlines()
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith('skills_adapters:'):
        i += 1
        while i < len(lines) and (lines[i].startswith('  -') or lines[i].startswith('  - ')):
            i += 1
        continue
    out.append(line)
    i += 1
with open('$SYNC_YAML', 'w') as f:
    f.writelines(out)
"
    fi
    ANY_CHANGE=true
  fi

  if ! $DRY_RUN; then
    git add "$SYNC_YAML"
  fi
fi

SKILLS_JSON="[]"
if [[ ${#REMOVED_SKILLS[@]} -gt 0 ]]; then
  SKILLS_JSON="[$(printf '"%s",' "${REMOVED_SKILLS[@]}" | sed 's/,$//')]"
fi
YAML_JSON="[]"
if [[ ${#REMOVED_YAML_FIELDS[@]} -gt 0 ]]; then
  YAML_JSON="[$(printf '"%s",' "${REMOVED_YAML_FIELDS[@]}" | sed 's/,$//')]"
fi

if ! $ANY_CHANGE; then
  emit_json "no-change" "null" "null" "null" "$SKILLS_JSON" "$YAML_JSON"
  exit 0
fi

if $DRY_RUN; then
  emit_json "dry-run" "null" "null" "null" "$SKILLS_JSON" "$YAML_JSON"
  exit 0
fi

if ! git checkout -q -b "$BRANCH" >&2; then
  trap_err "git checkout -b $BRANCH failed"
fi

COMMIT_MSG="chore(skills): migrate to @ozzylabs/skills user skills (ref: ozzy-labs/skills#96)

ozzy-labs/skills epic #96 / sub-issue #100 / handbook ADR-0027 で確定した
方針 (consumer 側は user skills only) に従い、project-scope の汎用 skill
コピーを削除する。

主な変更:

- .claude/skills/<汎用 10 種>/ を削除
- .agents/skills/<汎用 10 種>/ を削除
- .commons/sync.yaml から skills_commit / skills_adapters を削除

PR merge 後の利用者向け手順:

  npx @ozzylabs/skills install

を 1 度実行すると ~/.claude/skills/ に user skills として canonical bundle
が配置される。CI で skill を使う場合は ozzy-labs/skills@v1 GitHub Action
を利用 (https://github.com/ozzy-labs/skills#ci-integration)。

Refs: ozzy-labs/skills#96 ozzy-labs/skills#100

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"

git -c user.email=noreply@anthropic.com -c user.name="ozzy-3" commit -q -m "$COMMIT_MSG"
git push -q -u origin "$BRANCH" 2>&1 | tail -1 >&2

PR_TITLE="chore(skills): migrate to @ozzylabs/skills user skills (ref: ozzy-labs/skills#96)"
PR_BODY="## Summary

[ozzy-labs/skills epic #96](https://github.com/ozzy-labs/skills/issues/96) [sub-issue #100](https://github.com/ozzy-labs/skills/issues/100) / [handbook ADR-0027](https://github.com/ozzy-labs/handbook/blob/main/adr/0027-skill-distribution-user-only.md) で確定した方針 (consumer 側は user skills only) に従い、project-scope の汎用 skill コピーを削除する。

## 変更内容

- \`.claude/skills/\` 配下の汎用 skill 10 種を削除 (drive / implement / ship / review / commit / pr / lint / test / commit-conventions / lint-rules)
- \`.agents/skills/\` 配下の同 skill を削除
- \`.commons/sync.yaml\` から \`skills_commit\` / \`skills_adapters\` セクションを削除

## 利用者向け手順 (PR merge 後)

\`\`\`bash
# user skills として canonical bundle を install (1 度だけ)
npx @ozzylabs/skills install
\`\`\`

CI で skill を使う場合は \`ozzy-labs/skills@v1\` GitHub Action を利用。

## Refs

- Parent epic: ozzy-labs/skills#96
- sub-issue: ozzy-labs/skills#100
- ADR: handbook ADR-0027

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

PR_URL=$(gh pr create --repo "$TARGET" --base "$BASE_BRANCH" --head "$BRANCH" --title "$PR_TITLE" --body "$PR_BODY" 2>&1 | tail -1) || trap_err "gh pr create failed: $PR_URL"
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

STATUS="merge-ready"
if $AUTO_MERGE; then
  if gh pr merge "$PR_NUMBER" --repo "$TARGET" --auto --squash 2>/dev/null; then
    STATUS="auto-merge enabled"
  fi
fi

emit_json "$STATUS" "$PR_URL" "$PR_NUMBER" "null" "$SKILLS_JSON" "$YAML_JSON"
exit 0
