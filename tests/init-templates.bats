#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  TEST_DIR="$(mktemp -d)"
  TARGET_DIR="${TEST_DIR}/target"
  mkdir -p "${TARGET_DIR}"
  git -C "${TARGET_DIR}" init -q
  git -C "${TARGET_DIR}" config user.email "test@example.com"
  git -C "${TARGET_DIR}" config user.name "Test User"
  git -C "${TARGET_DIR}" commit -q --allow-empty -m "init"

  SCRIPT="${BATS_TEST_DIRNAME}/../init-templates.sh"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "exits 1 with usage when no arguments given" {
  run "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "exits 1 when --name is missing" {
  run "${SCRIPT}" --skip-gh-edit "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--name is required"* ]]
}

@test "exits 1 on unknown option" {
  run "${SCRIPT}" --invalid "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --invalid"* ]]
}

@test "exits 1 when target directory does not exist" {
  run "${SCRIPT}" --name foo --skip-gh-edit "${TEST_DIR}/nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"target directory not found"* ]]
}

@test "copies templates and substitutes placeholders" {
  run "${SCRIPT}" \
    --name agentic-watch \
    --description "Multi-agent CLI" \
    --skip-gh-edit \
    "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  [ -f "${TARGET_DIR}/AGENTS.md" ]
  [ -f "${TARGET_DIR}/CLAUDE.md" ]
  grep -q "agentic-watch" "${TARGET_DIR}/AGENTS.md"
  grep -q "Multi-agent CLI" "${TARGET_DIR}/AGENTS.md"

  # No literal placeholders remain
  run ! grep -q "{{project_name}}" "${TARGET_DIR}/AGENTS.md"
  run ! grep -q "{{description}}" "${TARGET_DIR}/AGENTS.md"
}

@test "leaves description placeholder empty when --description not given" {
  run "${SCRIPT}" --name foo --skip-gh-edit "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  grep -q "foo" "${TARGET_DIR}/AGENTS.md"
  # The placeholder is replaced with empty string when no description given
  run ! grep -q "{{description}}" "${TARGET_DIR}/AGENTS.md"
}

@test "refuses to overwrite existing files without --force" {
  echo "custom AGENTS.md" >"${TARGET_DIR}/AGENTS.md"
  run "${SCRIPT}" --name foo --skip-gh-edit "${TARGET_DIR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing to overwrite"* ]]
  [[ "$output" == *"--force"* ]]
  # Existing file preserved
  [ "$(cat "${TARGET_DIR}/AGENTS.md")" = "custom AGENTS.md" ]
}

@test "--force overwrites existing files" {
  echo "custom AGENTS.md" >"${TARGET_DIR}/AGENTS.md"
  run "${SCRIPT}" --name foo --description "desc" --skip-gh-edit --force "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  grep -q "foo" "${TARGET_DIR}/AGENTS.md"
  run ! grep -q "custom AGENTS.md" "${TARGET_DIR}/AGENTS.md"
}

@test "unchanged files are reported as unchanged and not rewritten" {
  # First run creates the files
  "${SCRIPT}" --name foo --description "desc" --skip-gh-edit "${TARGET_DIR}"
  local first_mtime
  first_mtime="$(stat -c %Y "${TARGET_DIR}/AGENTS.md")"

  # Sleep 1s so mtime would visibly change if rewritten
  sleep 1

  # Second run with same args should be no-op
  run "${SCRIPT}" --name foo --description "desc" --skip-gh-edit "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged: AGENTS.md"* ]]
  [[ "$output" == *"unchanged: CLAUDE.md"* ]]
}

@test "--dry-run shows plan without modifying files" {
  run "${SCRIPT}" \
    --name agentic-watch \
    --description "desc" \
    --topics ai,cli \
    --repo ozzy-labs/agentic-watch \
    --dry-run \
    "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new:"*"AGENTS.md"* ]]
  [[ "$output" == *"new:"*"CLAUDE.md"* ]]
  [[ "$output" == *"description: desc"* ]]
  [[ "$output" == *"topics:"*"ai,cli"* ]]
  [[ "$output" == *"Dry run"* ]]
  # Files not actually created
  [ ! -f "${TARGET_DIR}/AGENTS.md" ]
  [ ! -f "${TARGET_DIR}/CLAUDE.md" ]
}

@test "--dry-run respects existing files (no overwrite check failure)" {
  echo "custom" >"${TARGET_DIR}/AGENTS.md"
  run "${SCRIPT}" --name foo --skip-gh-edit --dry-run "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"overwrite:"*"AGENTS.md"* ]]
  # Existing file preserved
  [ "$(cat "${TARGET_DIR}/AGENTS.md")" = "custom" ]
}

@test "auto-detects repo from target's origin remote" {
  git -C "${TARGET_DIR}" remote add origin https://github.com/test-org/test-repo.git
  run "${SCRIPT}" \
    --name foo \
    --description "desc" \
    --dry-run \
    "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub metadata (test-org/test-repo)"* ]]
}

@test "auto-detects repo from ssh-style origin remote" {
  git -C "${TARGET_DIR}" remote add origin git@github.com:test-org/test-repo.git
  run "${SCRIPT}" \
    --name foo \
    --description "desc" \
    --dry-run \
    "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub metadata (test-org/test-repo)"* ]]
}

@test "--repo overrides remote detection" {
  git -C "${TARGET_DIR}" remote add origin https://github.com/wrong/wrong.git
  run "${SCRIPT}" \
    --name foo \
    --description "desc" \
    --repo override/repo \
    --dry-run \
    "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub metadata (override/repo)"* ]]
}

@test "--skip-gh-edit suppresses GitHub metadata plan" {
  run "${SCRIPT}" \
    --name foo \
    --description "desc" \
    --topics ai,cli \
    --repo o/r \
    --skip-gh-edit \
    --dry-run \
    "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  run ! grep -q "GitHub metadata" <<<"$output"
}

@test "no GitHub metadata block when neither description nor topics given" {
  run "${SCRIPT}" --name foo --repo o/r --dry-run "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  run ! grep -q "GitHub metadata" <<<"$output"
}

@test "prints next-step hints by default" {
  run "${SCRIPT}" --name foo --skip-gh-edit "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Templates init complete."* ]]
  [[ "$output" == *"Next steps:"* ]]
  [[ "$output" == *"chore/bootstrap"* ]]
}

@test "--quiet suppresses next-step hints" {
  run "${SCRIPT}" --name foo --skip-gh-edit --quiet "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Templates init complete."* ]]
  run ! grep -q "Next steps:" <<<"$output"
}

@test "templates with substitution are valid markdown (no broken placeholders)" {
  "${SCRIPT}" \
    --name "my-project" \
    --description "A description with: special chars & symbols" \
    --skip-gh-edit \
    "${TARGET_DIR}"

  # No partial placeholder leftovers
  run ! grep -qE '\{\{[a-z_]+\}\}' "${TARGET_DIR}/AGENTS.md"
  run ! grep -qE '\{\{[a-z_]+\}\}' "${TARGET_DIR}/CLAUDE.md"

  # Special chars preserved
  grep -q "special chars & symbols" "${TARGET_DIR}/AGENTS.md"
}
