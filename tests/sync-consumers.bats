#!/usr/bin/env bats

# Tests for scripts/sync-consumers.sh
#
# Coverage:
#   - --help / usage
#   - argument parsing (--opt value AND --opt=value)
#   - argument validation (--source, --target)
#   - --dry-run JSON output (status / would_run / required fields)
#   - field substitution (skills_commit vs commit) based on --source
#   - branch name composition (--branch-prefix + short SHA)

bats_require_minimum_version 1.5.0

setup() {
  TEST_DIR="$(mktemp -d)"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/sync-consumers.sh"

  # Create a fake source repo with a known HEAD SHA so --ssot-sha defaults
  # work deterministically.
  SRC_REPO="${TEST_DIR}/src"
  mkdir -p "${SRC_REPO}"
  (
    cd "${SRC_REPO}"
    git init --quiet -b main
    git config user.email test@example.com
    git config user.name test
    echo "x" >a
    git add a
    git commit --quiet -m "initial"
  )
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "--help prints usage to stderr and exits 0" {
  run "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Usage:"* ]]
  [[ "${output}" == *"--source"* ]]
  [[ "${output}" == *"--target"* ]]
}

@test "missing --source fails with error" {
  run "${SCRIPT}" --target ozzy-labs/foo
  [ "$status" -ne 0 ]
  [[ "${output}" == *"--source"* ]]
}

@test "missing --target fails with error" {
  run "${SCRIPT}" --source skills
  [ "$status" -ne 0 ]
  [[ "${output}" == *"--target"* ]]
}

@test "invalid --source value fails with error" {
  run "${SCRIPT}" --source invalid --target ozzy-labs/foo
  [ "$status" -ne 0 ]
  [[ "${output}" == *"--source must be"* ]]
}

@test "malformed --target (no slash) fails with error" {
  run "${SCRIPT}" --source skills --target invalid-format
  [ "$status" -ne 0 ]
  [[ "${output}" == *"--target must be"* ]]
}

@test "--opt value form is accepted" {
  run "${SCRIPT}" --source skills --target ozzy-labs/foo --dry-run --source-repo "${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *'"status": "dry-run"'* ]]
}

@test "--opt=value form is accepted" {
  run "${SCRIPT}" --source=skills --target=ozzy-labs/foo --dry-run --source-repo="${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *'"status": "dry-run"'* ]]
}

@test "--dry-run JSON includes target, branch, would_run" {
  run "${SCRIPT}" --source skills --target ozzy-labs/foo --dry-run --source-repo "${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *'"target": "ozzy-labs/foo"'* ]]
  [[ "${output}" == *'"branch":'* ]]
  [[ "${output}" == *'"would_run":'* ]]
  [[ "${output}" == *'"status": "dry-run"'* ]]
}

@test "--source=skills bumps skills_commit field" {
  run "${SCRIPT}" --source=skills --target=ozzy-labs/foo --dry-run --source-repo="${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"skills_commit"* ]]
  # commons の commit field 名と区別できていることを確認
  [[ "${output}" != *"bump .commons/sync.yaml: commit -> "* ]]
}

@test "--source=commons bumps commit field" {
  run "${SCRIPT}" --source=commons --target=ozzy-labs/foo --dry-run --source-repo="${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"bump .commons/sync.yaml: commit -> "* ]]
  [[ "${output}" != *"skills_commit"* ]]
}

@test "--branch-prefix overrides the default prefix" {
  run "${SCRIPT}" \
    --source skills \
    --target ozzy-labs/foo \
    --dry-run \
    --source-repo "${SRC_REPO}" \
    --branch-prefix chore/custom-sync
  [ "$status" -eq 0 ]
  [[ "${output}" == *'"branch": "chore/custom-sync-'* ]]
}

@test "default branch-prefix is chore/sync-<source>" {
  run "${SCRIPT}" --source skills --target ozzy-labs/foo --dry-run --source-repo "${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *'"branch": "chore/sync-skills-'* ]]
}

@test "--ssot-sha overrides auto-detected SHA in branch name and would_run" {
  run "${SCRIPT}" \
    --source skills \
    --target ozzy-labs/foo \
    --dry-run \
    --source-repo "${SRC_REPO}" \
    --ssot-sha 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 0 ]
  [[ "${output}" == *'"branch": "chore/sync-skills-0123456"'* ]]
  [[ "${output}" == *"0123456789abcdef0123456789abcdef01234567"* ]]
}

@test "--auto-merge adds gh pr merge to would_run list" {
  run "${SCRIPT}" \
    --source skills \
    --target ozzy-labs/foo \
    --dry-run \
    --auto-merge \
    --source-repo "${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"gh pr merge --auto --squash"* ]]
}

@test "without --auto-merge, gh pr merge is NOT in would_run" {
  run "${SCRIPT}" --source skills --target ozzy-labs/foo --dry-run --source-repo "${SRC_REPO}"
  [ "$status" -eq 0 ]
  [[ "${output}" != *"gh pr merge --auto --squash"* ]]
}

@test "non-existent --source-repo fails with error" {
  run "${SCRIPT}" \
    --source skills \
    --target ozzy-labs/foo \
    --dry-run \
    --source-repo /nonexistent/path
  [ "$status" -ne 0 ]
  [[ "${output}" == *"not a git repository"* ]]
}

@test "unknown option fails with error" {
  run "${SCRIPT}" --source skills --target ozzy-labs/foo --unknown-opt value
  [ "$status" -ne 0 ]
  [[ "${output}" == *"Unknown option"* ]]
}
