#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"

  # Create fake ai-config source repo
  SRC_DIR="${TEST_DIR}/ai-config"
  mkdir -p "${SRC_DIR}/shared/.claude/skills/commit"
  mkdir -p "${SRC_DIR}/shared/.claude/rules"
  mkdir -p "${SRC_DIR}/templates/.claude/skills/lint-rules"
  echo "shared skill" > "${SRC_DIR}/shared/.claude/skills/commit/SKILL.md"
  echo "shared rule" > "${SRC_DIR}/shared/.claude/rules/git-workflow.md"
  echo "template lint" > "${SRC_DIR}/templates/.claude/skills/lint-rules/SKILL.md"
  echo "template claude" > "${SRC_DIR}/templates/CLAUDE.md"

  # Init as git repo (needed for metadata commit hash)
  git -C "${SRC_DIR}" init -q
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "init"

  # Copy real sync.sh
  cp "${BATS_TEST_DIRNAME}/../sync.sh" "${SRC_DIR}/sync.sh"
  chmod +x "${SRC_DIR}/sync.sh"

  # Create fake target repo
  TARGET_DIR="${TEST_DIR}/target"
  mkdir -p "${TARGET_DIR}"
  git -C "${TARGET_DIR}" init -q
  git -C "${TARGET_DIR}" commit -q --allow-empty -m "init"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "copies new shared files to target" {
  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "shared skill" ]
  [ -f "${TARGET_DIR}/.claude/rules/git-workflow.md" ]
}

@test "overwrites changed shared files" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Modify source
  echo "updated skill" > "${SRC_DIR}/shared/.claude/skills/commit/SKILL.md"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "updated skill" ]
}

@test "copies new template files to target" {
  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/CLAUDE.md" ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "template claude" ]
  [ -f "${TARGET_DIR}/.claude/skills/lint-rules/SKILL.md" ]
}

@test "skips existing template files" {
  # Pre-create template file with custom content
  mkdir -p "${TARGET_DIR}/.claude/skills/lint-rules"
  echo "custom lint" > "${TARGET_DIR}/.claude/skills/lint-rules/SKILL.md"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/lint-rules/SKILL.md")" = "custom lint" ]
}

@test "--force completes without interactive prompt" {
  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sync complete."* ]]
}

@test "--dry-run shows summary but does not copy files" {
  run "${SRC_DIR}/sync.sh" --dry-run "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"file(s) to copy"* ]]
  # Files should NOT exist in target
  [ ! -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ ! -f "${TARGET_DIR}/CLAUDE.md" ]
  # Metadata should NOT exist
  [ ! -f "${TARGET_DIR}/.claude/.ai-config-sync" ]
}

@test "writes metadata file with commit hash and timestamp" {
  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/.ai-config-sync" ]

  local meta
  meta="$(cat "${TARGET_DIR}/.claude/.ai-config-sync")"
  [[ "$meta" == *"commit: "* ]]
  [[ "$meta" == *"synced_at: "* ]]
  # Verify commit hash is a valid short hash (hex chars)
  local hash
  hash="$(grep '^commit:' "${TARGET_DIR}/.claude/.ai-config-sync" | awk '{print $2}')"
  [[ "$hash" =~ ^[0-9a-f]+$ ]]
}

@test "reports nothing to sync when already up to date" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to sync."* ]]
}

@test "errors when target is not a git repository" {
  local not_git="${TEST_DIR}/not-git"
  mkdir -p "${not_git}"

  run "${SRC_DIR}/sync.sh" --force "${not_git}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
}
