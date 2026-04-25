#!/usr/bin/env bats

# Dual-path metadata location tests for sync.sh.
#
# Migration period (see ADR-0014 / handbook#79): sync.sh must read & write
#   - canonical: .commons/sync.yaml  (preferred)
#   - fallback : .dev-config/sync.yaml  (legacy, kept until consumers rename)
#
# Required behavior:
#   1. .commons/ only       -> read & write .commons/
#   2. .dev-config/ only    -> read & write .dev-config/ (do NOT auto-migrate)
#   3. Both present         -> .commons/ wins (read & write canonical)
#   4. Neither present      -> create .commons/ (canonical bootstrap)

setup() {
  TEST_DIR="$(mktemp -d)"

  # Minimal fake commons source (enough to trigger a sync)
  SRC_DIR="${TEST_DIR}/commons"
  mkdir -p "${SRC_DIR}/dist"
  echo "claude md" > "${SRC_DIR}/dist/CLAUDE.md"
  echo "editor" > "${SRC_DIR}/dist/.editorconfig"

  git -C "${SRC_DIR}" init -q
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "init"

  cp "${BATS_TEST_DIRNAME}/../sync.sh" "${SRC_DIR}/sync.sh"
  chmod +x "${SRC_DIR}/sync.sh"

  TARGET_DIR="${TEST_DIR}/target"
  mkdir -p "${TARGET_DIR}"
  git -C "${TARGET_DIR}" init -q
  git -C "${TARGET_DIR}" commit -q --allow-empty -m "init"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test ".commons/ only: pinned list is read from canonical and write stays canonical" {
  # Pre-existing .commons/ with a pinned entry
  mkdir -p "${TARGET_DIR}/.commons"
  cat > "${TARGET_DIR}/.commons/sync.yaml" <<'EOF'
commit: abc1234
synced_at: 2026-04-25T00:00:00Z
pinned:
  - CLAUDE.md
EOF
  echo "my custom claude" > "${TARGET_DIR}/CLAUDE.md"
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Pin honored (proves canonical was read)
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my custom claude" ]

  # Write stays at .commons/ — fallback path is NOT created
  [ -f "${TARGET_DIR}/.commons/sync.yaml" ]
  [ ! -f "${TARGET_DIR}/.dev-config/sync.yaml" ]

  # Pin preserved
  local meta
  meta="$(cat "${TARGET_DIR}/.commons/sync.yaml")"
  [[ "$meta" == *"CLAUDE.md"* ]]
}

@test ".dev-config/ only: pinned list is read from fallback and write stays at fallback" {
  # Existing legacy consumer with a pinned entry
  mkdir -p "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
commit: abc1234
synced_at: 2026-04-25T00:00:00Z
pinned:
  - CLAUDE.md
EOF
  echo "my custom claude" > "${TARGET_DIR}/CLAUDE.md"
  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Pin honored (proves fallback was read)
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my custom claude" ]

  # Write must NOT auto-migrate — canonical path stays absent
  [ -f "${TARGET_DIR}/.dev-config/sync.yaml" ]
  [ ! -f "${TARGET_DIR}/.commons/sync.yaml" ]

  # Pin preserved at the legacy path
  local meta
  meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"
  [[ "$meta" == *"CLAUDE.md"* ]]

  # And the human-visible "write:" line points at the legacy path
  [[ "$output" == *".dev-config/sync.yaml"* ]]
}

@test "both present: canonical wins for read AND write" {
  # Canonical pins CLAUDE.md; fallback pins .editorconfig.
  # If canonical wins, only CLAUDE.md is preserved.
  mkdir -p "${TARGET_DIR}/.commons" "${TARGET_DIR}/.dev-config"
  cat > "${TARGET_DIR}/.commons/sync.yaml" <<'EOF'
commit: deadbeef
synced_at: 2026-04-25T00:00:00Z
pinned:
  - CLAUDE.md
EOF
  cat > "${TARGET_DIR}/.dev-config/sync.yaml" <<'EOF'
commit: cafebabe
synced_at: 2026-04-20T00:00:00Z
pinned:
  - .editorconfig
EOF

  echo "my claude" > "${TARGET_DIR}/CLAUDE.md"
  echo "my editor" > "${TARGET_DIR}/.editorconfig"

  echo "updated claude md" > "${SRC_DIR}/dist/CLAUDE.md"
  echo "updated editor"   > "${SRC_DIR}/dist/.editorconfig"

  # Bump source so the canonical pin matters
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "bump"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Canonical pin honored, fallback pin ignored
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my claude" ]
  [ "$(cat "${TARGET_DIR}/.editorconfig")" = "updated editor" ]

  # Canonical metadata gets the fresh commit hash; fallback is left untouched
  local canonical_meta fallback_meta
  canonical_meta="$(cat "${TARGET_DIR}/.commons/sync.yaml")"
  fallback_meta="$(cat "${TARGET_DIR}/.dev-config/sync.yaml")"

  # Canonical updated (no longer the placeholder hash)
  [[ "$canonical_meta" != *"commit: deadbeef"* ]]
  [[ "$canonical_meta" == *"CLAUDE.md"* ]]

  # Fallback untouched
  [[ "$fallback_meta" == *"commit: cafebabe"* ]]
  [[ "$fallback_meta" == *".editorconfig"* ]]
}

@test "neither present: brand-new consumer is bootstrapped at .commons/" {
  # No metadata directories at all
  [ ! -d "${TARGET_DIR}/.commons" ]
  [ ! -d "${TARGET_DIR}/.dev-config" ]

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Canonical created
  [ -f "${TARGET_DIR}/.commons/sync.yaml" ]
  # Legacy NOT created
  [ ! -f "${TARGET_DIR}/.dev-config/sync.yaml" ]

  # Visible write hint points at canonical
  [[ "$output" == *".commons/sync.yaml"* ]]
}

@test ".dev-config/ only: --check reads fallback and reports up-to-date when synced" {
  # First sync to a legacy-only consumer
  mkdir -p "${TARGET_DIR}/.dev-config"
  : > "${TARGET_DIR}/.dev-config/sync.yaml"
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"

  # Sanity: write stayed at fallback
  [ -f "${TARGET_DIR}/.dev-config/sync.yaml" ]
  [ ! -f "${TARGET_DIR}/.commons/sync.yaml" ]

  run "${SRC_DIR}/sync.sh" --check "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}
