#!/usr/bin/env bats

# Smoke-test the Renovate preset file exposed to consumer repos. Validates
# JSON syntax and the core contract fields that consumers depend on.

PRESET_FILE="${BATS_TEST_DIRNAME}/../commons-sync.json"

@test "preset file exists at repo root" {
  [ -f "${PRESET_FILE}" ]
}

@test "preset is valid JSON" {
  jq -e . "${PRESET_FILE}" >/dev/null
}

@test "preset declares the renovate \$schema" {
  jq -e '."$schema" | test("renovate-schema")' "${PRESET_FILE}" >/dev/null
}

@test "preset defines a customManager targeting sync.yaml" {
  jq -e '.customManagers[0].managerFilePatterns | map(test("sync\\.yaml")) | any' \
    "${PRESET_FILE}" >/dev/null
}

@test "preset customManager matches the canonical .commons/sync.yaml path" {
  jq -e '.customManagers[0].managerFilePatterns | map(test("\\.commons/sync\\.yaml")) | any' \
    "${PRESET_FILE}" >/dev/null
}

@test "preset customManager does NOT match the removed .dev-config/sync.yaml fallback" {
  # ADR-0014 / handbook#79: the legacy fallback was removed once all
  # consumers completed the rename to .commons/.
  run jq -e '.customManagers[0].managerFilePatterns | map(test("\\.dev-config/sync\\.yaml")) | any' \
    "${PRESET_FILE}"
  [ "$status" -ne 0 ]
}

@test "preset customManager captures currentDigest via regex" {
  jq -e '.customManagers[0].matchStrings | map(test("currentDigest")) | any' \
    "${PRESET_FILE}" >/dev/null
}

@test "preset uses git-refs datasource pointing at ozzy-labs/commons main" {
  [ "$(jq -r '.customManagers[0].datasourceTemplate' "${PRESET_FILE}")" = "git-refs" ]
  jq -e '.customManagers[0].packageNameTemplate | test("ozzy-labs/commons")' \
    "${PRESET_FILE}" >/dev/null
  [ "$(jq -r '.customManagers[0].currentValueTemplate' "${PRESET_FILE}")" = "main" ]
}
