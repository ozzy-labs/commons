
setup() {
  TEST_DIR="$(mktemp -d)"
  SRC_DIR="${TEST_DIR}/commons"
  mkdir -p "${SRC_DIR}/dist"
  
  # Create a surgical file in dist
  cat <<EOF > "${SRC_DIR}/dist/biome.json"
{
  "linter": {
    "rules": {
      "recommended": true,
      "nursery": {
        "noUnusedImports": "error"
      }
    }
  }
}
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
  
  # Create target biome.json with custom rules
  cat <<EOF > "${TARGET_DIR}/biome.json"
{
  "linter": {
    "rules": {
      "recommended": false,
      "suspicious": {
        "noExplicitAny": "warn"
      }
    }
  },
  "formatter": {
    "enabled": true
  }
}
EOF
  git -C "${TARGET_DIR}" add biome.json
  git -C "${TARGET_DIR}" config user.email "test@example.com"
  git -C "${TARGET_DIR}" config user.name "Test User"
  git -C "${TARGET_DIR}" commit -q -m "target init"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "surgical merge preserves target-only keys and overrides shared keys" {
  # This test will fail until we implement surgical merge
  # We want to run sync.sh with a new flag or default behavior
  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  
  # Check if target-only keys are preserved
  # formatter.enabled should be true
  # linter.rules.suspicious.noExplicitAny should be warn
  
  # Check if shared keys are overridden
  # linter.rules.recommended should be true (from dist)
  [ "$(yq '.linter.rules.recommended' "${TARGET_DIR}/biome.json")" = "true" ]
  
  # Check if target-only keys are preserved
  # formatter.enabled should be true
  [ "$(yq '.formatter.enabled' "${TARGET_DIR}/biome.json")" = "true" ]
  
  # linter.rules.suspicious.noExplicitAny should be warn (ignoring quotes)
  run yq '.linter.rules.suspicious.noExplicitAny' "${TARGET_DIR}/biome.json"
  [[ "$output" == *"warn"* ]]

  # Check if dist-only keys are added
  run yq '.linter.rules.nursery.noUnusedImports' "${TARGET_DIR}/biome.json"
  [[ "$output" == *"error"* ]]
  }

@test "surgical merge works for YAML files" {
  # Create a surgical YAML in dist
  cat <<EOF > "${SRC_DIR}/dist/.yamllint.yaml"
extends: default
rules:
  line-length:
    max: 120
    level: warning
EOF

  # Update commons repo
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "add yamllint"

  # Create target .yamllint.yaml with custom rules
  cat <<EOF > "${TARGET_DIR}/.yamllint.yaml"
extends: relaxed
rules:
  indentation:
    spaces: 4
EOF

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Check results
  [ "$(yq '.extends' "${TARGET_DIR}/.yamllint.yaml")" = "default" ]
  [ "$(yq '.rules.line-length.max' "${TARGET_DIR}/.yamllint.yaml")" = "120" ]
  [ "$(yq '.rules.indentation.spaces' "${TARGET_DIR}/.yamllint.yaml")" = "4" ]
}

@test "_template.yaml scaffolds are full-copied (not surgical-merged) to preserve comments" {
  # _template scaffolds carry educational comments and multi-line literal
  # blocks. Surgical merge with yq strips comments and reorders keys, which
  # would cumulatively damage the scaffold across syncs. They must be full-copied.
  mkdir -p "${SRC_DIR}/dist/.claude/routines"
  cat <<'EOF' > "${SRC_DIR}/dist/.claude/routines/_template.yaml"
# Comment that must survive the sync
name: <routine-name>

# Section header comment
status: draft
EOF
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "add routines template"

  # Create existing target with different content (to trigger 'changed' path)
  mkdir -p "${TARGET_DIR}/.claude/routines"
  cat <<'EOF' > "${TARGET_DIR}/.claude/routines/_template.yaml"
name: <old-name>
status: active
EOF
  git -C "${TARGET_DIR}" add .
  git -C "${TARGET_DIR}" commit -q -m "old template"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Should be reported as copy, not merge
  [[ "$output" == *"copy: .claude/routines/_template.yaml"* ]]
  [[ "$output" != *"merge: .claude/routines/_template.yaml"* ]]

  # Comments must be preserved (yq surgical merge would have stripped them)
  grep -q "Comment that must survive the sync" "${TARGET_DIR}/.claude/routines/_template.yaml"
  grep -q "Section header comment" "${TARGET_DIR}/.claude/routines/_template.yaml"
}

@test "lefthook-base.yaml is full-copied (not surgical-merged) to avoid header/key drift" {
  # lefthook-base.yaml is a shared base — consumers extend via lefthook.yaml and
  # never add keys to it. yq surgical merge would compound free-floating header
  # comments across syncs and append new keys at the bottom, drifting from dist.
  cat <<'EOF' > "${SRC_DIR}/dist/lefthook-base.yaml"
# Header comment v2
commit-msg:
  commands:
    commitlint:
      run: new-commitlint --edit {1}
pre-commit:
  commands:
    shell:
      run: new-shfmt
    taplo:
      run: new-taplo
EOF
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "update lefthook-base"

  # Existing target with old header and only `shell` (no taplo)
  cat <<'EOF' > "${TARGET_DIR}/lefthook-base.yaml"
# Header comment v1
commit-msg:
  commands:
    commitlint:
      run: old-commitlint --edit {1}
pre-commit:
  commands:
    shell:
      run: old-shfmt
EOF
  git -C "${TARGET_DIR}" add lefthook-base.yaml
  git -C "${TARGET_DIR}" commit -q -m "old lefthook-base"

  run "${SRC_DIR}/sync.sh" -y "${TARGET_DIR}"
  [ "$status" -eq 0 ]

  # Should be reported as copy, not merge
  [[ "$output" == *"copy: lefthook-base.yaml"* ]]
  [[ "$output" != *"merge: lefthook-base.yaml"* ]]

  # Old header must NOT remain (full copy replaces it)
  ! grep -q "Header comment v1" "${TARGET_DIR}/lefthook-base.yaml"
  grep -q "Header comment v2" "${TARGET_DIR}/lefthook-base.yaml"

  # Header must appear exactly once (no compounding)
  [ "$(grep -c "^# Header comment" "${TARGET_DIR}/lefthook-base.yaml")" = "1" ]

  # New content from dist must win
  [ "$(yq '.commit-msg.commands.commitlint.run' "${TARGET_DIR}/lefthook-base.yaml")" = "new-commitlint --edit {1}" ]
  [ "$(yq '.pre-commit.commands.shell.run' "${TARGET_DIR}/lefthook-base.yaml")" = "new-shfmt" ]
  [ "$(yq '.pre-commit.commands.taplo.run' "${TARGET_DIR}/lefthook-base.yaml")" = "new-taplo" ]
}

@test "interactive mode offers 'm' for surgical files and performs merge" {
  # Create a surgical file in dist
  cat <<EOF > "${SRC_DIR}/dist/biome.json"
{
  "linter": { "rules": { "recommended": true } }
}
EOF
  git -C "${SRC_DIR}" add .
  git -C "${SRC_DIR}" commit -q -m "update biome"

  # Create target with custom content
  cat <<EOF > "${TARGET_DIR}/biome.json"
{
  "linter": { "rules": { "recommended": false } },
  "formatter": { "enabled": true }
}
EOF

  # Simulate interactive input: "m" for the first (and only) changed file
  # We use printf to provide input to the script
  run bash -c "printf 'm\n' | ${SRC_DIR}/sync.sh ${TARGET_DIR}"
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge: biome.json"* ]]
  
  # Verify merge
  [ "$(yq '.linter.rules.recommended' "${TARGET_DIR}/biome.json")" = "true" ]
  [ "$(yq '.formatter.enabled' "${TARGET_DIR}/biome.json")" = "true" ]
}
