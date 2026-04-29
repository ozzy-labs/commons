
setup() {
  TEST_DIR="$(mktemp -d)"
  SRC_DIR="${TEST_DIR}/commons"
  mkdir -p "${SRC_DIR}/dist"
  
  # Create a file with markers in dist
  cat <<EOF > "${SRC_DIR}/dist/README.md"
# Project
<!-- begin: ozzy-labs/commons -->
Common content from commons.
<!-- end: ozzy-labs/commons -->
EOF

  # Init commons repo
  git -C "${SRC_DIR}" init -q
  git -C "${SRC_DIR}" config user.email "test@example.com"
  git -C "${SRC_DIR}" config user.name "Test User"
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "init"
  
  # Copy sync.sh
  cp "${BATS_TEST_DIRNAME}/../sync.sh" "${SRC_DIR}/sync.sh"
  chmod +x "${SRC_DIR}/sync.sh"

  # Create target repo
  TARGET_DIR="${TEST_DIR}/target"
  mkdir -p "${TARGET_DIR}"
  git -C "${TARGET_DIR}" init -q
  
  # Create target README.md with custom content outside markers
  cat <<EOF > "${TARGET_DIR}/README.md"
# My Project
<!-- begin: ozzy-labs/commons -->
Old common content.
<!-- end: ozzy-labs/commons -->
Custom user content.
EOF
  git -C "${TARGET_DIR}" add README.md
  git -C "${TARGET_DIR}" config user.email "test@example.com"
  git -C "${TARGET_DIR}" config user.name "Test User"
  git -C "${TARGET_DIR}" commit -q -m "target init"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "marker-based sync updates only the marked section" {
  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  
  # Check results
  grep -q "Common content from commons." "${TARGET_DIR}/README.md"
  grep -q "Custom user content." "${TARGET_DIR}/README.md"
  grep -q "# My Project" "${TARGET_DIR}/README.md"
  ! grep -q "Old common content." "${TARGET_DIR}/README.md"
}

@test "marker-based sync reports no changes if marked section is same" {
  # First sync to align
  "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  
  # Modify custom part in target
  sed -i "s/Custom user content./Modified user content./" "${TARGET_DIR}/README.md"
  
  # Run check mode
  run "${SRC_DIR}/sync.sh" --check "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All files are up to date."* ]]
}

@test "marker-based sync overwrites whole file if markers are missing in target" {
  cat <<EOF > "${TARGET_DIR}/README.md"
# No markers here.
EOF
  
  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  
  # Should have markers now
  grep -q "<!-- begin: ozzy-labs/commons -->" "${TARGET_DIR}/README.md"
  ! grep -q "# No markers here." "${TARGET_DIR}/README.md"
}

@test "marker-based sync works for YAML files with # markers" {
  # Create a file with markers in dist
  cat <<EOF > "${SRC_DIR}/dist/config.yaml"
# begin: ozzy-labs/commons
common: true
# end: ozzy-labs/commons
EOF

  # Update commons repo
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "add config.yaml"

  # Create target with custom content
  cat <<EOF > "${TARGET_DIR}/config.yaml"
custom: true
# begin: ozzy-labs/commons
common: false
# end: ozzy-labs/commons
EOF

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]
  
  # Check results
  grep -q "common: true" "${TARGET_DIR}/config.yaml"
  grep -q "custom: true" "${TARGET_DIR}/config.yaml"
  ! grep -q "common: false" "${TARGET_DIR}/config.yaml"
}
