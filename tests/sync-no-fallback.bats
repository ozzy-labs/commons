#!/usr/bin/env bats

# Post-migration tests: the legacy `.dev-config/sync.yaml` fallback was
# supported during the migration documented in ADR-0014 / handbook#79
# and has now been removed. sync.sh must read & write only the canonical
# `.commons/sync.yaml` path and must NOT honour `.dev-config/` metadata.

setup() {
  TEST_DIR="$(mktemp -d)"

  # Minimal fake commons source (enough to trigger a sync)
  SRC_DIR="${TEST_DIR}/commons"
  mkdir -p "${SRC_DIR}/dist"
  echo "claude md" > "${SRC_DIR}/dist/CLAUDE.md"
  echo "editor" > "${SRC_DIR}/dist/.editorconfig"

  git -C "${SRC_DIR}" init -q
  git -C "${SRC_DIR}" config user.email "test@example.com"
  git -C "${SRC_DIR}" config user.name "Test User"
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "init"

  cp "${BATS_TEST_DIRNAME}/../sync.sh" "${SRC_DIR}/sync.sh"
  chmod +x "${SRC_DIR}/sync.sh"

  TARGET_DIR="${TEST_DIR}/target"
  mkdir -p "${TARGET_DIR}"
  git -C "${TARGET_DIR}" init -q
  git -C "${TARGET_DIR}" config user.email "test@example.com"
  git -C "${TARGET_DIR}" config user.name "Test User"
  git -C "${TARGET_DIR}" commit -q --allow-empty -m "init"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "brand-new consumer is bootstrapped at .commons/" {
  [ ! -d "${TARGET_DIR}/.commons" ]
  [ ! -d "${TARGET_DIR}/.dev-config" ]

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  [ -f "${TARGET_DIR}/.commons/sync.yaml" ]
  [ ! -f "${TARGET_DIR}/.dev-config/sync.yaml" ]
  [[ "$output" == *".commons/sync.yaml"* ]]
}

@test ".commons/ pinned list is honoured" {
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

  # Pin honored from canonical
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "my custom claude" ]
  [ -f "${TARGET_DIR}/.commons/sync.yaml" ]
  [ ! -f "${TARGET_DIR}/.dev-config/sync.yaml" ]
}

@test "legacy .dev-config/ metadata is ignored after fallback removal" {
  # A consumer that never migrated still has only .dev-config/. After the
  # fallback removal, sync.sh must not treat it as the metadata source —
  # it must bootstrap a fresh .commons/ instead, and the legacy pin must
  # NOT be honoured.
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

  # Legacy pin ignored: file is overwritten because metadata is read from
  # .commons/ (which doesn't exist yet).
  [ "$(cat "${TARGET_DIR}/CLAUDE.md")" = "updated claude md" ]

  # New canonical metadata is bootstrapped.
  [ -f "${TARGET_DIR}/.commons/sync.yaml" ]

  # Visible write hint points at canonical, not the legacy path.
  [[ "$output" == *".commons/sync.yaml"* ]]
  [[ "$output" != *".dev-config/sync.yaml"* ]]
}
