#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  TEST_DIR="$(mktemp -d)"

  # --- Fake skills dist ---
  SKILLS_DIST="${TEST_DIR}/skills-dist"

  # claude-code adapter
  mkdir -p "${SKILLS_DIST}/claude-code/.claude/skills/commit"
  mkdir -p "${SKILLS_DIST}/claude-code/.claude/skills/lint"
  echo "claude commit skill" >"${SKILLS_DIST}/claude-code/.claude/skills/commit/SKILL.md"
  echo "claude lint skill" >"${SKILLS_DIST}/claude-code/.claude/skills/lint/SKILL.md"

  # codex-cli adapter
  mkdir -p "${SKILLS_DIST}/codex-cli/.agents/skills/commit"
  mkdir -p "${SKILLS_DIST}/codex-cli/.agents/skills/lint"
  echo "codex commit skill" >"${SKILLS_DIST}/codex-cli/.agents/skills/commit/SKILL.md"
  echo "codex lint skill" >"${SKILLS_DIST}/codex-cli/.agents/skills/lint/SKILL.md"
  cat >"${SKILLS_DIST}/codex-cli/AGENTS.md.snippet" <<'EOF'
<!-- begin: @ozzylabs/skills -->
## Available Skills

- `commit` — codex
<!-- end: @ozzylabs/skills -->
EOF

  # gemini-cli adapter
  mkdir -p "${SKILLS_DIST}/gemini-cli/.gemini"
  echo '{"contextFileName":"AGENTS.md"}' >"${SKILLS_DIST}/gemini-cli/.gemini/settings.json"
  cp "${SKILLS_DIST}/codex-cli/AGENTS.md.snippet" "${SKILLS_DIST}/gemini-cli/AGENTS.md.snippet"

  # copilot adapter
  mkdir -p "${SKILLS_DIST}/copilot/.github"
  cat >"${SKILLS_DIST}/copilot/.github/copilot-instructions.md.snippet" <<'EOF'
<!-- begin: @ozzylabs/skills -->
## Available Skills

- `commit` — copilot
<!-- end: @ozzylabs/skills -->
EOF

  # --- Target repo ---
  TARGET_DIR="${TEST_DIR}/target"
  mkdir -p "${TARGET_DIR}"
  git -C "${TARGET_DIR}" init -q
  git -C "${TARGET_DIR}" commit -q --allow-empty -m "init"

  # AGENTS.md with marker block
  cat >"${TARGET_DIR}/AGENTS.md" <<'EOF'
# AGENTS.md

intro text

<!-- begin: @ozzylabs/skills -->
old skills content
<!-- end: @ozzylabs/skills -->

footer text
EOF

  # copilot-instructions.md with marker block
  mkdir -p "${TARGET_DIR}/.github"
  cat >"${TARGET_DIR}/.github/copilot-instructions.md" <<'EOF'
# Copilot

intro

<!-- begin: @ozzylabs/skills -->
old copilot
<!-- end: @ozzylabs/skills -->

footer
EOF

  SCRIPT="${BATS_TEST_DIRNAME}/../sync-skills.sh"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

write_metadata() {
  mkdir -p "${TARGET_DIR}/.commons"
  printf '%s\n' "$1" >"${TARGET_DIR}/.commons/sync.yaml"
}

@test "exits 1 with usage when no arguments given" {
  run "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "exits 1 on unknown option" {
  run "${SCRIPT}" --invalid "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --invalid"* ]]
}

@test "exits 1 when target is not a git repo" {
  local not_git="${TEST_DIR}/not-git"
  mkdir -p "${not_git}"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${not_git}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "exits 1 when skills dist root not found" {
  write_metadata "skills_adapters:
  - claude-code"
  run "${SCRIPT}" -y "${TEST_DIR}/nonexistent" "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills dist root not found"* ]]
}

@test "exits 0 with 'Nothing to sync' when no skills_adapters configured" {
  write_metadata "commit: abc1234"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to sync."* ]]
}

@test "exits 1 on unknown adapter" {
  write_metadata "skills_adapters:
  - nonexistent-adapter"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown adapter"* ]]
}

@test "claude-code adapter copies skill dirs into .claude/skills/" {
  write_metadata "skills_adapters:
  - claude-code"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ -f "${TARGET_DIR}/.claude/skills/lint/SKILL.md" ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "claude commit skill" ]
}

@test "codex-cli adapter copies skill dirs and replaces AGENTS.md marker block" {
  write_metadata "skills_adapters:
  - codex-cli"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.agents/skills/commit/SKILL.md" ]
  [ "$(cat "${TARGET_DIR}/.agents/skills/commit/SKILL.md")" = "codex commit skill" ]

  # Surrounding AGENTS.md content preserved
  grep -q "intro text" "${TARGET_DIR}/AGENTS.md"
  grep -q "footer text" "${TARGET_DIR}/AGENTS.md"

  # Snippet content present, old content gone
  grep -q "commit. — codex" "${TARGET_DIR}/AGENTS.md"
  run ! grep -q "old skills content" "${TARGET_DIR}/AGENTS.md"
}

@test "gemini-cli adapter copies settings.json and updates AGENTS.md" {
  write_metadata "skills_adapters:
  - gemini-cli"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.gemini/settings.json" ]
  grep -q "contextFileName" "${TARGET_DIR}/.gemini/settings.json"
  grep -q "intro text" "${TARGET_DIR}/AGENTS.md"
  run ! grep -q "old skills content" "${TARGET_DIR}/AGENTS.md"
}

@test "copilot adapter replaces .github/copilot-instructions.md marker block" {
  write_metadata "skills_adapters:
  - copilot"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  grep -q "intro" "${TARGET_DIR}/.github/copilot-instructions.md"
  grep -q "footer" "${TARGET_DIR}/.github/copilot-instructions.md"
  grep -q "commit. — copilot" "${TARGET_DIR}/.github/copilot-instructions.md"
  run ! grep -q "old copilot" "${TARGET_DIR}/.github/copilot-instructions.md"
}

@test "all four adapters can be opted-in together" {
  write_metadata "skills_adapters:
  - claude-code
  - codex-cli
  - gemini-cli
  - copilot"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ -f "${TARGET_DIR}/.agents/skills/commit/SKILL.md" ]
  [ -f "${TARGET_DIR}/.gemini/settings.json" ]
  grep -q "commit. — codex" "${TARGET_DIR}/AGENTS.md"
  grep -q "commit. — copilot" "${TARGET_DIR}/.github/copilot-instructions.md"
}

@test "flow-style skills_adapters list is supported" {
  write_metadata "skills_adapters: [claude-code, codex-cli]"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ -f "${TARGET_DIR}/.agents/skills/commit/SKILL.md" ]
}

@test "pinned files are skipped" {
  write_metadata "skills_adapters:
  - claude-code
pinned:
  - .claude/skills/commit/SKILL.md"

  mkdir -p "${TARGET_DIR}/.claude/skills/commit"
  echo "my custom" >"${TARGET_DIR}/.claude/skills/commit/SKILL.md"

  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "my custom" ]
  [[ "$output" == *"pinned:"*".claude/skills/commit/SKILL.md"* ]]

  # Non-pinned skill in same adapter still copied
  [ -f "${TARGET_DIR}/.claude/skills/lint/SKILL.md" ]
}

@test "directory pin (trailing slash) skips every file under it" {
  write_metadata "skills_adapters:
  - claude-code
pinned:
  - .claude/skills/commit/"

  mkdir -p "${TARGET_DIR}/.claude/skills/commit"
  echo "my custom" >"${TARGET_DIR}/.claude/skills/commit/SKILL.md"

  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "my custom" ]
  [ -f "${TARGET_DIR}/.claude/skills/lint/SKILL.md" ]
}

@test "pinning AGENTS.md skips snippet replacement" {
  write_metadata "skills_adapters:
  - codex-cli
pinned:
  - AGENTS.md"

  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  grep -q "old skills content" "${TARGET_DIR}/AGENTS.md"
  # Skill files still copied
  [ -f "${TARGET_DIR}/.agents/skills/commit/SKILL.md" ]
}

@test "consumer-only skill dirs in destination are preserved" {
  write_metadata "skills_adapters:
  - claude-code"

  mkdir -p "${TARGET_DIR}/.claude/skills/my-domain"
  echo "my domain skill" >"${TARGET_DIR}/.claude/skills/my-domain/SKILL.md"

  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
  [ -f "${TARGET_DIR}/.claude/skills/my-domain/SKILL.md" ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/my-domain/SKILL.md")" = "my domain skill" ]
}

@test "AGENTS.md without marker errors out" {
  write_metadata "skills_adapters:
  - codex-cli"
  echo "no markers here" >"${TARGET_DIR}/AGENTS.md"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing the"*"marker"* ]]
}

@test "missing AGENTS.md errors out for snippet adapter" {
  write_metadata "skills_adapters:
  - codex-cli"
  rm -f "${TARGET_DIR}/AGENTS.md"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "--check exits 0 when in sync" {
  write_metadata "skills_adapters:
  - claude-code"
  "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"

  run "${SCRIPT}" --check "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "--check exits 1 when out of sync" {
  write_metadata "skills_adapters:
  - claude-code"
  run "${SCRIPT}" --check "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"out of sync"* ]]
}

@test "--check does not modify files" {
  write_metadata "skills_adapters:
  - claude-code"
  run "${SCRIPT}" --check "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [ ! -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
}

@test "--check ignores pinned files" {
  write_metadata "skills_adapters:
  - claude-code
pinned:
  - .claude/skills/commit/SKILL.md
  - .claude/skills/lint/SKILL.md"

  run "${SCRIPT}" --check "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
}

@test "--dry-run shows summary but does not copy" {
  write_metadata "skills_adapters:
  - claude-code"
  run "${SCRIPT}" --dry-run "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"file(s) to sync"* ]]
  [ ! -f "${TARGET_DIR}/.claude/skills/commit/SKILL.md" ]
}

@test "second sync reports nothing to sync" {
  write_metadata "skills_adapters:
  - claude-code
  - codex-cli"
  "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"

  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to sync."* ]]
}

@test "snippet replacement is idempotent" {
  write_metadata "skills_adapters:
  - codex-cli
  - copilot"
  "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"

  run "${SCRIPT}" --check "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
}

@test "shared AGENTS.md snippet from codex-cli + gemini-cli together is no-op on second snippet" {
  write_metadata "skills_adapters:
  - codex-cli
  - gemini-cli"
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  grep -q "commit. — codex" "${TARGET_DIR}/AGENTS.md"

  # Second run: nothing to sync
  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to sync."* ]]
}

@test "interleaved comments and blank lines in pinned list are handled" {
  write_metadata "skills_adapters:
  - claude-code
pinned:
  # group: customised commit skill
  - .claude/skills/commit/SKILL.md

  # group: blocked
  - .claude/skills/lint/SKILL.md"

  mkdir -p "${TARGET_DIR}/.claude/skills/commit"
  mkdir -p "${TARGET_DIR}/.claude/skills/lint"
  echo "my commit" >"${TARGET_DIR}/.claude/skills/commit/SKILL.md"
  echo "my lint" >"${TARGET_DIR}/.claude/skills/lint/SKILL.md"

  run "${SCRIPT}" -y "${SKILLS_DIST}" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/commit/SKILL.md")" = "my commit" ]
  [ "$(cat "${TARGET_DIR}/.claude/skills/lint/SKILL.md")" = "my lint" ]
}
