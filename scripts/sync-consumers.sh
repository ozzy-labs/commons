#!/usr/bin/env bash
set -euo pipefail

# commons/scripts/sync-consumers.sh
#
# Push consumer 同期 helper. /sync-consumers skill (skills / commons 両方) から
# 呼ばれる。target consumer を clone → .commons/sync.yaml の SHA field を bump
# → sync.sh / sync-skills.sh で dist を反映 → branch / commit / push / PR /
# (auto-merge) を実行する。
#
# 仕様 / 設計詳細:
#   - ozzy-labs/skills の Issue #80 (epic), #82 (本 helper の skills portion)
#   - skills/src/skills/sync-consumers/SKILL.md (SSOT)
#
# Usage:
#   sync-consumers.sh \
#     --source <skills|commons> \
#     --target <owner/repo> \
#     [--dry-run] \
#     [--auto-merge] \
#     [--branch-prefix <prefix>] \
#     [--base-branch <branch>] \
#     [--ssot-sha <sha>] \
#     [--source-repo <local-path>]
#
# JSON 戻り値 (stdout):
#   {
#     "target": "ozzy-labs/<repo>",
#     "branch": "<branch>",
#     "pr_url": "<URL or null>",
#     "pr_number": <N or null>,
#     "status": "merged" | "merge-ready" | "auto-merge enabled" | "no-change"
#               | "dry-run" | "failed",
#     "error": "<message or null>"
#   }
#
# exit code:
#   0: 成功 (status: merged / merge-ready / auto-merge enabled / no-change / dry-run)
#   1: エラー (status: failed)

SOURCE=""
TARGET=""
DRY_RUN=false
AUTO_MERGE=false
BRANCH_PREFIX=""
BASE_BRANCH="main"
SSOT_SHA=""
SOURCE_REPO=""

while [[ $# -gt 0 ]]; do
  # --opt=value 形式を --opt value に正規化
  arg="$1"
  val=""
  if [[ "$arg" == --*=* ]]; then
    val="${arg#*=}"
    arg="${arg%%=*}"
  fi
  case "$arg" in
  --source)
    SOURCE="${val:-$2}"
    [[ -z "$val" ]] && shift
    shift
    ;;
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
  --branch-prefix)
    BRANCH_PREFIX="${val:-$2}"
    [[ -z "$val" ]] && shift
    shift
    ;;
  --base-branch)
    BASE_BRANCH="${val:-$2}"
    [[ -z "$val" ]] && shift
    shift
    ;;
  --ssot-sha)
    SSOT_SHA="${val:-$2}"
    [[ -z "$val" ]] && shift
    shift
    ;;
  --source-repo)
    SOURCE_REPO="${val:-$2}"
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

# 必須引数 check
if [[ -z "$SOURCE" || -z "$TARGET" ]]; then
  echo "ERROR: --source and --target are required. Run with --help for usage." >&2
  exit 1
fi
if [[ "$SOURCE" != "skills" && "$SOURCE" != "commons" ]]; then
  echo "ERROR: --source must be 'skills' or 'commons' (got '$SOURCE')" >&2
  exit 1
fi
if [[ ! "$TARGET" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
  echo "ERROR: --target must be in 'owner/repo' format (got '$TARGET')" >&2
  exit 1
fi

# defaults
if [[ -z "$BRANCH_PREFIX" ]]; then
  BRANCH_PREFIX="chore/sync-${SOURCE}"
fi
if [[ -z "$SOURCE_REPO" ]]; then
  if [[ "$SOURCE" == "skills" ]]; then
    SOURCE_REPO="${HOME}/github/ozzy-labs/skills"
  else
    SOURCE_REPO="${HOME}/github/ozzy-labs/commons"
  fi
fi
if [[ ! -d "$SOURCE_REPO/.git" ]]; then
  echo "ERROR: --source-repo '$SOURCE_REPO' is not a git repository" >&2
  exit 1
fi
if [[ -z "$SSOT_SHA" ]]; then
  SSOT_SHA=$(git -C "$SOURCE_REPO" rev-parse HEAD)
fi

SHORT_SHA="${SSOT_SHA:0:7}"
BRANCH="${BRANCH_PREFIX}-${SHORT_SHA}"

# .commons/sync.yaml の bump 対象 field
if [[ "$SOURCE" == "skills" ]]; then
  FIELD="skills_commit"
else
  FIELD="commit"
fi

# 失敗時に JSON で stderr ではなく stdout に出す helper
emit_json() {
  local status="$1"
  local pr_url="${2:-null}"
  local pr_number="${3:-null}"
  local error="${4:-null}"
  if [[ "$pr_url" != "null" ]]; then pr_url="\"$pr_url\""; fi
  if [[ "$error" != "null" ]]; then error="\"${error//\"/\\\"}\""; fi
  cat <<JSON
{
  "target": "$TARGET",
  "branch": "$BRANCH",
  "pr_url": $pr_url,
  "pr_number": $pr_number,
  "status": "$status",
  "error": $error
}
JSON
}

trap_err() {
  local msg="${1:-unknown error}"
  emit_json "failed" "null" "null" "$msg"
  exit 1
}

# dry-run の場合: 想定処理を JSON で返す
if $DRY_RUN; then
  PLAN_COMMONS_REPO="${COMMONS_REPO:-${HOME}/github/ozzy-labs/commons}"
  PLAN_SYNC_CMD=""
  if [[ "$SOURCE" == "skills" ]]; then
    PLAN_SYNC_CMD="$PLAN_COMMONS_REPO/sync-skills.sh -y $SOURCE_REPO/dist <consumer-clone>"
  else
    PLAN_SYNC_CMD="$PLAN_COMMONS_REPO/sync.sh -y <consumer-clone>"
  fi
  MAYBE_AUTO_MERGE=""
  if $AUTO_MERGE; then
    MAYBE_AUTO_MERGE=', "gh pr merge --auto --squash (no --delete-branch)"'
  fi
  cat <<JSON
{
  "target": "$TARGET",
  "branch": "$BRANCH",
  "pr_url": null,
  "pr_number": null,
  "status": "dry-run",
  "would_run": [
    "git clone https://github.com/$TARGET.git <tmpdir> (shallow, $BASE_BRANCH)",
    "git -C <tmpdir> checkout -b $BRANCH",
    "bump .commons/sync.yaml: ${FIELD} -> $SSOT_SHA",
    "$PLAN_SYNC_CMD",
    "git -C <tmpdir> add -A && git -C <tmpdir> commit -m 'chore(deps): sync $SOURCE to $SHORT_SHA'",
    "git -C <tmpdir> push -u origin $BRANCH",
    "gh pr create --repo $TARGET --base $BASE_BRANCH --head $BRANCH --title <title> --body <body>"$MAYBE_AUTO_MERGE
  ],
  "error": null
}
JSON
  exit 0
fi

# 実 sync 実装 (dogfood 経路)
TMPDIR="$(mktemp -d -t sync-consumers-XXXXXX)"
# shellcheck disable=SC2329  # invoked via trap below
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

CONSUMER_DIR="$TMPDIR/consumer"

# 1. clone
if ! git clone --depth 50 --branch "$BASE_BRANCH" "https://github.com/${TARGET}.git" "$CONSUMER_DIR" >&2; then
  trap_err "git clone failed for $TARGET"
fi

# 2. branch 作成
if ! git -C "$CONSUMER_DIR" checkout -b "$BRANCH" >&2; then
  trap_err "git checkout -b $BRANCH failed"
fi

# 3. .commons/sync.yaml の SHA field を bump (commit: or skills_commit:)
SYNC_YAML="$CONSUMER_DIR/.commons/sync.yaml"
if [[ ! -f "$SYNC_YAML" ]]; then
  trap_err ".commons/sync.yaml not found in $TARGET (consumer not opt-in)"
fi
# sed で in-place 書き換え (BSD/GNU 互換)
if ! sed -i.bak -E "s|^${FIELD}:[[:space:]]+[a-f0-9]+|${FIELD}: ${SSOT_SHA}|" "$SYNC_YAML"; then
  trap_err "sed failed to bump $FIELD in $SYNC_YAML"
fi
rm -f "${SYNC_YAML}.bak"

# 4. sync.sh / sync-skills.sh 実行
#
# sync-skills.sh / sync.sh は両方 commons repo に置かれている (commons/sync.sh /
# commons/sync-skills.sh)。--source=skills の場合も呼び出すのは commons の
# sync-skills.sh で、第 1 引数として skills の dist を指す。
COMMONS_SCRIPT_REPO="${COMMONS_REPO:-${HOME}/github/ozzy-labs/commons}"
if [[ ! -d "$COMMONS_SCRIPT_REPO/.git" ]]; then
  trap_err "commons repo not found at $COMMONS_SCRIPT_REPO (set COMMONS_REPO env to override)"
fi
if [[ "$SOURCE" == "skills" ]]; then
  if ! "$COMMONS_SCRIPT_REPO/sync-skills.sh" -y "$SOURCE_REPO/dist" "$CONSUMER_DIR" >&2; then
    trap_err "sync-skills.sh failed"
  fi
else
  if ! "$COMMONS_SCRIPT_REPO/sync.sh" -y "$CONSUMER_DIR" >&2; then
    trap_err "sync.sh failed"
  fi
fi

# 5. 変更が無ければ no-change で終了
if [[ -z "$(git -C "$CONSUMER_DIR" status --short)" ]]; then
  emit_json "no-change"
  exit 0
fi

# 6. commit + push
COMMIT_MSG="chore(deps): sync ${SOURCE} to ${SHORT_SHA}

ozzy-labs/${SOURCE} HEAD ${SHORT_SHA} を取り込むため .commons/sync.yaml の
${FIELD} を bump し、対応する dist を sync.

Synced via commons/scripts/sync-consumers.sh"

git -C "$CONSUMER_DIR" add -A
if ! git -C "$CONSUMER_DIR" commit -m "$COMMIT_MSG" >&2; then
  trap_err "git commit failed"
fi
if ! git -C "$CONSUMER_DIR" push -u origin "$BRANCH" >&2; then
  trap_err "git push failed"
fi

# 7. PR 作成
PR_TITLE="chore(deps): sync ${SOURCE} to ${SHORT_SHA}"
PR_BODY="## Summary

ozzy-labs/${SOURCE} HEAD \`${SHORT_SHA}\` を本リポに同期。

- \`.commons/sync.yaml\` の \`${FIELD}\` を \`${SSOT_SHA}\` に bump
- 対応する \`dist/\` を sync

## Synced via

\`commons/scripts/sync-consumers.sh\` (push 型同期、ozzy-labs/skills#80 epic)"

PR_URL=$(gh pr create \
  --repo "$TARGET" \
  --base "$BASE_BRANCH" \
  --head "$BRANCH" \
  --title "$PR_TITLE" \
  --body "$PR_BODY" 2>&1 | tail -1) || trap_err "gh pr create failed: $PR_URL"
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

STATUS="merge-ready"

# 8. --auto-merge 指定時
if $AUTO_MERGE; then
  if gh pr merge "$PR_NUMBER" --repo "$TARGET" --auto --squash >&2; then
    STATUS="auto-merge enabled"
  else
    # auto-merge 失敗 (branch protection 等) は警告として merge-ready を返す
    STATUS="merge-ready"
  fi
fi

emit_json "$STATUS" "$PR_URL" "$PR_NUMBER"
exit 0
