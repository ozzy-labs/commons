#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"

  # Create fake dev-config source repo
  SRC_DIR="${TEST_DIR}/dev-config"
  mkdir -p "${SRC_DIR}/dist/.claude/skills/commit"
  mkdir -p "${SRC_DIR}/dist/.claude/skills/lint-rules"
  mkdir -p "${SRC_DIR}/dist/.claude/rules"
  mkdir -p "${SRC_DIR}/dist/.github/workflows"
  mkdir -p "${SRC_DIR}/dist/.github/ISSUE_TEMPLATE"
  mkdir -p "${SRC_DIR}/dist/.vscode"
  echo "skill content" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"
  echo "lint-rules content" > "${SRC_DIR}/dist/.claude/skills/lint-rules/SKILL.md"
  echo "rule content" > "${SRC_DIR}/dist/.claude/rules/git-workflow.md"
  echo "settings content" > "${SRC_DIR}/dist/.claude/settings.json"
  echo "lefthook-base" > "${SRC_DIR}/dist/lefthook-base.yaml"
  echo "commitlint" > "${SRC_DIR}/dist/.commitlintrc.yaml"
  echo "editorconfig" > "${SRC_DIR}/dist/.editorconfig"
  echo "gitattributes" > "${SRC_DIR}/dist/.gitattributes"
  echo "mdformat" > "${SRC_DIR}/dist/.mdformat.toml"
  echo "pr-check" > "${SRC_DIR}/dist/.github/workflows/pr-check.yaml"
  echo "claude md" > "${SRC_DIR}/dist/CLAUDE.md"
  echo "security" > "${SRC_DIR}/dist/SECURITY.md"
  echo "mcp" > "${SRC_DIR}/dist/.mcp.json"
  echo "yamlfmt" > "${SRC_DIR}/dist/.yamlfmt.yaml"
  echo "yamllint" > "${SRC_DIR}/dist/.yamllint.yaml"
  echo "markdownlint" > "${SRC_DIR}/dist/.markdownlint-cli2.yaml"
  echo "mise" > "${SRC_DIR}/dist/.mise.toml"
  echo "gitignore" > "${SRC_DIR}/dist/.gitignore"
  echo "renovate" > "${SRC_DIR}/dist/renovate.json"
  echo "biome" > "${SRC_DIR}/dist/biome.json"
  echo "license" > "${SRC_DIR}/dist/LICENSE"
  echo "contributing" > "${SRC_DIR}/dist/CONTRIBUTING.md"
  echo "pr template" > "${SRC_DIR}/dist/.github/pull_request_template.md"
  echo "bug report" > "${SRC_DIR}/dist/.github/ISSUE_TEMPLATE/bug_report.yaml"
  echo "feature request" > "${SRC_DIR}/dist/.github/ISSUE_TEMPLATE/feature_request.yaml"
  echo "vscode settings" > "${SRC_DIR}/dist/.vscode/settings.json"
  echo "vscode extensions" > "${SRC_DIR}/dist/.vscode/extensions.json"
  echo "lefthook" > "${SRC_DIR}/dist/lefthook.yaml"

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

@test "copies new files to target" {
  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "skill content" ]
  [ -f "${TARGET_DIR}/.claude/rules/git-workflow.md" ]
  [ -f "${TARGET_DIR}/CLAUDE.md" ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "claude md" ]
  [ -f "${TARGET_DIR}/.claude/skills/lint-rules/SKILL.md" ]
}

@test "overwrites changed files with --force" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Modify source
  echo "updated skill" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "updated skill" ]
}

@test "overwrites customized files with --force" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Customize target file
  echo "custom content" > "${TARGET_DIR}/CLAUDE.md"

  # Modify source so there's a diff
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "updated claude md" ]
}

@test "--force completes without interactive prompt" {
  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sync complete."* ]]
}

@test "--dry-run shows summary but does not copy files" {
  run "${SRC_DIR}/sync.sh" --dry-run "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"file(s) to sync"* ]]
  # Files should NOT exist in target
  [ ! -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ ! -f "${TARGET_DIR}/CLAUDE.md" ]
  # Metadata should NOT exist
  [ ! -f "${TARGET_DIR}/.dev-config/sync.yaml" ]
}

@test "writes metadata file with commit hash and timestamp" {
  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.dev-config/sync.yaml" ]

  local meta
  meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"
  [[ "$meta" == *"commit: "* ]]
  [[ "$meta" == *"synced_at: "* ]]
  # Verify commit hash is a valid short hash (hex chars)
  local hash
  hash="$(grep '^commit:' "${TARGET_DIR}/.dev-config/sync.yaml" | awk '{print $2}')"
  [[ "$hash" =~ ^[0-9a-f]+$ ]]
}

@test "reports nothing to sync when already up to date" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to sync."* ]]
}

@test "--check exits 0 when files are up to date" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  run "${SRC_DIR}/sync.sh" --check "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "--check exits 1 when files are out of sync" {
  run "${SRC_DIR}/sync.sh" --check "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"out of sync"* ]]
}

@test "--check exits 1 when files have changed" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Modify source
  echo "updated skill" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"

  run "${SRC_DIR}/sync.sh" --check "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"out of sync"* ]]
}

@test "--check does not copy files" {
  run "${SRC_DIR}/sync.sh" --check "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  # Files should NOT exist in target
  [ ! -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  # Metadata should NOT exist
  [ ! -f "${TARGET_DIR}/.dev-config/sync.yaml" ]
}

@test "errors when target is not a git repository" {
  local not_git="${TEST_DIR}/not-git"
  mkdir -p "${not_git}"

  run "${SRC_DIR}/sync.sh" --force "${not_git}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "pinned files are skipped during sync" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Pin CLAUDE.md
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
# Auto-generated by dev-config sync.sh
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
EOF

  # Customize pinned file
  echo "my custom claude" > "${TARGET_DIR}/CLAUDE.md"

  # Modify source
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  # Pinned file should NOT be overwritten
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my custom claude" ]
  [[ "$output" == *"pinned:"*"CLAUDE.md"* ]]
}

@test "pinned files are skipped in --check mode" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Pin and customize CLAUDE.md
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
# Auto-generated by dev-config sync.sh
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
EOF
  echo "my custom claude" > "${TARGET_DIR}/CLAUDE.md"

  # Modify source
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" --check "${TARGET_DIR}"
  # Should pass because CLAUDE.md is pinned (only non-pinned files checked)
  [ "$status" -eq 0 ]
}

@test "--unpin removes file from pinned list" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Pin two files
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
# Auto-generated by dev-config sync.sh
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
  - .claude/settings.json
EOF

  run "${SRC_DIR}/sync.sh" --unpin CLAUDE.md "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unpinned: CLAUDE.md"* ]]

  # Verify CLAUDE.md is no longer pinned but settings.json still is
  local meta
  meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"
  [[ "$meta" != *"CLAUDE.md"* ]]
  [[ "$meta" == *".claude/settings.json"* ]]
}

@test "--unpin reports if file is not pinned" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  run "${SRC_DIR}/sync.sh" --unpin CLAUDE.md "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not pinned"* ]]
}

@test "pinned list is preserved across syncs" {
  "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"

  # Pin a file
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
# Auto-generated by dev-config sync.sh
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
EOF

  # Modify a non-pinned file and sync
  echo "updated skill" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"

  run "${SRC_DIR}/sync.sh" --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Pin should still be in metadata
  local meta
  meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"
  [[ "$meta" == *"pinned:"* ]]
  [[ "$meta" == *"CLAUDE.md"* ]]
}
