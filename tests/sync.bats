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

@test "exits 1 with usage when no arguments given" {
  run "${SRC_DIR}/sync.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "exits 1 on unknown option" {
  run "${SRC_DIR}/sync.sh" --invalid "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --invalid"* ]]
}

@test "copies new files to target" {
  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "skill content" ]
  [ -f "${TARGET_DIR}/.claude/rules/git-workflow.md" ]
  [ -f "${TARGET_DIR}/CLAUDE.md" ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "claude md" ]
  [ -f "${TARGET_DIR}/.claude/skills/lint-rules/SKILL.md" ]
}

@test "overwrites changed files with -y" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Modify source
  echo "updated skill" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "updated skill" ]
}

@test "overwrites customized files with --yes" {
  "${SRC_DIR}/sync.sh" --yes "${TARGET_DIR}"

  # Customize target file
  echo "custom content" > "${TARGET_DIR}/CLAUDE.md"

  # Modify source so there's a diff
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" --yes "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "updated claude md" ]
}

@test "-y completes without interactive prompt" {
  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
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
  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
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

@test "metadata includes user-editable comment" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  local meta
  meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"
  [[ "$meta" == *"user-editable"* ]]
}

@test "reports nothing to sync when already up to date" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to sync."* ]]
}

@test "--check exits 0 when files are up to date" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

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
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

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

  run "${SRC_DIR}/sync.sh" -y "${not_git}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "pinned files are skipped during sync" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Pin CLAUDE.md
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
# Auto-updated by dev-config sync.sh
# 'pinned' is user-editable — add or remove paths freely
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
EOF

  # Customize pinned file
  echo "my custom claude" > "${TARGET_DIR}/CLAUDE.md"

  # Modify source
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  # Pinned file should NOT be overwritten
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my custom claude" ]
  [[ "$output" == *"pinned:"*"CLAUDE.md"* ]]
}

@test "pinned files are skipped in --check mode" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Pin and customize CLAUDE.md
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
# Auto-updated by dev-config sync.sh
# 'pinned' is user-editable — add or remove paths freely
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

@test "pinned list is preserved across syncs" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Pin a file
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
# Auto-updated by dev-config sync.sh
# 'pinned' is user-editable — add or remove paths freely
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
EOF

  # Modify a non-pinned file and sync
  echo "updated skill" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Pin should still be in metadata
  local meta
  meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"
  [[ "$meta" == *"pinned:"* ]]
  [[ "$meta" == *"CLAUDE.md"* ]]
}

@test "pinned files with YAML quotes are recognized" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Pin CLAUDE.md with YAML double quotes
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - "CLAUDE.md"
EOF

  echo "my custom claude" > "${TARGET_DIR}/CLAUDE.md"
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my custom claude" ]
}

@test "pinned files with trailing spaces are recognized" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Pin CLAUDE.md with trailing spaces
  mkdir -p "${TARGET_DIR}/.dev-config"
  printf 'commit: abc1234\nsynced_at: 2026-04-05T00:00:00Z\npinned:\n  - CLAUDE.md   \n' \
    > "${TARGET_DIR}/.dev-config/sync.yaml"

  echo "my custom claude" > "${TARGET_DIR}/CLAUDE.md"
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my custom claude" ]
}

@test "multiple pinned files are all skipped" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
  - .editorconfig
EOF

  echo "my claude" > "${TARGET_DIR}/CLAUDE.md"
  echo "my editor" > "${TARGET_DIR}/.editorconfig"

  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"
  echo "updated editorconfig" > "${SRC_DIR}/dist/.editorconfig"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Both pinned files should NOT be overwritten
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my claude" ]
  [ "$(cat "${TARGET_DIR}/.editorconfig")" = "my editor" ]

  # Both should appear in pinned output
  [[ "$output" == *"pinned:"*"CLAUDE.md"* ]]
  [[ "$output" == *"pinned:"*".editorconfig"* ]]
}

@test "metadata is written atomically via temp file" {
  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.dev-config/sync.yaml" ]
  # No leftover temp files
  local tmp_count
  tmp_count="$(find "${TARGET_DIR}/.dev-config" -name 'sync.yaml.tmp.*' | wc -l)"
  [ "$tmp_count" -eq 0 ]
}

@test "interactive mode: new files are copied without prompting" {
  # First sync to establish baseline
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Add a new file to source
  echo "new-file-content" > "${SRC_DIR}/dist/NEW_FILE.md"
  git -C "${SRC_DIR}" add . && git -C "${SRC_DIR}" commit -q -m "add new file"

  # Also change an existing file so interactive prompt appears
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  # Provide "n" to skip the changed file — new file should still be copied
  run bash -c 'printf "n\n" | "${1}" "${2}"' _ "${SRC_DIR}/sync.sh" "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # New file should have been copied without prompting
  [ -f "${TARGET_DIR}/NEW_FILE.md" ]
  [ "$(cat "${TARGET_DIR}/NEW_FILE.md")" = "new-file-content" ]

  # Changed file should NOT be copied (we chose "n")
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "claude md" ]
}

@test "interactive mode: skip unchanged and respond to input" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  echo "updated skill" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  # Provide "n" to skip the first changed file, then "y" for the second
  run bash -c 'printf "n\ny\n" | "${1}" "${2}"' _ "${SRC_DIR}/sync.sh" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sync complete."* ]]
}

@test "interactive mode: pin adds file to pinned list" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  # Choose "pin" for the changed file
  run bash -c 'printf "pin\n" | "${1}" "${2}"' _ "${SRC_DIR}/sync.sh" "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # File should NOT be overwritten
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "claude md" ]

  # File should be in pinned list
  local meta
  meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"
  [[ "$meta" == *"pinned:"* ]]
  [[ "$meta" == *"CLAUDE.md"* ]]
}

@test "interactive mode: all copies remaining changed files without prompting" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  echo "updated skill" > "${SRC_DIR}/dist/.claude/skills/commit/SKILL.md"
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"
  echo "updated editorconfig" > "${SRC_DIR}/dist/.editorconfig"

  # Choose "all" at the first prompt — remaining files should be copied
  run bash -c 'printf "all\n" | "${1}" "${2}"' _ "${SRC_DIR}/sync.sh" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sync complete."* ]]

  # All changed files should be updated
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "updated skill" ]
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "updated claude md" ]
  [ "$(cat "${TARGET_DIR}/.editorconfig")" = "updated editorconfig" ]
}
