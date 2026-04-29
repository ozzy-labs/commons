
setup() {
  TEST_DIR="$(mktemp -d)"
  SRC_DIR="${TEST_DIR}/commons"
  mkdir -p "${SRC_DIR}/dist"
  
  # Create a file with markers in dist
  cat <<EOF > "${SRC_DIR}/dist/README.md"
<!-- begin: ozzy-labs/commons -->
Common content.
<!-- end: ozzy-labs/commons -->
EOF

  # Init commons repo
  git -C "${SRC_DIR}" init -q
  git -C "${SRC_DIR}" config user.email "test@example.com"
  git -C "${SRC_DIR}" config user.name "Test User"
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "init"
  
  # Copy scripts
  cp "${BATS_TEST_DIRNAME}/../sync.sh" "${SRC_DIR}/sync.sh"
  cp "${BATS_TEST_DIRNAME}/../check.sh" "${SRC_DIR}/check.sh"
  chmod +x "${SRC_DIR}/sync.sh" "${SRC_DIR}/check.sh"

  # Create target repo
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

@test "check.sh reports failures for missing mandatory files" {
  run "${SRC_DIR}/check.sh" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[FAIL] LICENSE is missing"* ]]
  [[ "$output" == *"[FAIL] AGENTS.md is missing"* ]]
}

@test "check.sh reports pass for existing mandatory files" {
  touch "${TARGET_DIR}/LICENSE"
  touch "${TARGET_DIR}/AGENTS.md"
  
  run "${SRC_DIR}/check.sh" "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PASS] LICENSE exists"* ]]
  [[ "$output" == *"[PASS] AGENTS.md exists"* ]]
}

@test "check.sh detects missing markers" {
  touch "${TARGET_DIR}/README.md"
  
  run "${SRC_DIR}/check.sh" "${TARGET_DIR}"
  [[ "$output" == *"[WARN] README.md is missing commons markers"* ]]
}

@test "check.sh detects sync issues" {
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  
  # Modify target file to cause sync mismatch
  echo "modified" > "${TARGET_DIR}/README.md"
  
  run "${SRC_DIR}/check.sh" "${TARGET_DIR}"
  [[ "$output" == *"[FAIL] Files are out of sync"* ]]
}
