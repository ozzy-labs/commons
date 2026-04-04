#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../setup-repo.sh"
}

@test "exits 1 with usage when no arguments given" {
  run "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"<owner/repo>"* ]]
}

@test "exits 1 on unknown option" {
  run "${SCRIPT}" --invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --invalid"* ]]
}

@test "exits 1 for non-existent repository" {
  run "${SCRIPT}" ozzy-labs/this-repo-does-not-exist-999
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "--dry-run shows all 4 sections without making changes" {
  run "${SCRIPT}" --dry-run ozzy-labs/dev-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"1. Repository settings"* ]]
  [[ "$output" == *"2. Security settings"* ]]
  [[ "$output" == *"3. Branch protection (Rulesets)"* ]]
  [[ "$output" == *"4. Labels"* ]]
  [[ "$output" == *"Setup complete."* ]]
}

@test "--dry-run shows [dry-run] markers for API calls" {
  run "${SCRIPT}" --dry-run ozzy-labs/dev-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] PATCH"* ]]
  [[ "$output" == *"[dry-run] PUT"* ]] || [[ "$output" == *"[dry-run] POST"* ]]
  [[ "$output" == *"[dry-run] delete label:"* ]]
  [[ "$output" == *"[dry-run] create label:"* ]]
}

@test "--dry-run shows repository visibility" {
  run "${SCRIPT}" --dry-run ozzy-labs/dev-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"Repository: ozzy-labs/dev-config"* ]]
}

@test "--dry-run skips private vulnerability reporting for private repo" {
  run "${SCRIPT}" --dry-run ozzy-labs/dev-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (private repo)"* ]]
}

@test "--dry-run shows all 10 Conventional Commits labels" {
  run "${SCRIPT}" --dry-run ozzy-labs/dev-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"create label: feat"* ]]
  [[ "$output" == *"create label: fix"* ]]
  [[ "$output" == *"create label: docs"* ]]
  [[ "$output" == *"create label: style"* ]]
  [[ "$output" == *"create label: refactor"* ]]
  [[ "$output" == *"create label: perf"* ]]
  [[ "$output" == *"create label: test"* ]]
  [[ "$output" == *"create label: build"* ]]
  [[ "$output" == *"create label: ci"* ]]
  [[ "$output" == *"create label: chore"* ]]
}

@test "--dry-run shows all 9 default labels to delete" {
  run "${SCRIPT}" --dry-run ozzy-labs/dev-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"delete label: bug"* ]]
  [[ "$output" == *"delete label: documentation"* ]]
  [[ "$output" == *"delete label: duplicate"* ]]
  [[ "$output" == *"delete label: enhancement"* ]]
  [[ "$output" == *"delete label: good first issue"* ]]
  [[ "$output" == *"delete label: help wanted"* ]]
  [[ "$output" == *"delete label: invalid"* ]]
  [[ "$output" == *"delete label: question"* ]]
  [[ "$output" == *"delete label: wontfix"* ]]
}

@test "usage message includes --dry-run option" {
  run "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--dry-run"* ]]
}
