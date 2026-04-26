#!/usr/bin/env bash
set -euo pipefail

# commons sync script
# Usage:
#   sync.sh [options] <target-repo-path>
# Options:
#   -y, --yes   Sync without confirmation (overwrite all non-pinned changed files)
#   --dry-run   Show what would be synced without copying
#   --check     Exit 1 if non-pinned files are out of sync (for CI)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"

# Parse arguments
YES=false
DRY_RUN=false
CHECK=false
while [[ "${1:-}" == -* ]]; do
  case "$1" in
  -y | --yes)
    YES=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --check)
    CHECK=true
    shift
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Usage:" >&2
  echo "  $0 [options] <target-repo-path>" >&2
  echo "  Options:" >&2
  echo "    -y, --yes   Sync without confirmation" >&2
  echo "    --dry-run   Show what would be synced without copying" >&2
  echo "    --check     Exit 1 if non-pinned files are out of sync (for CI)" >&2
  exit 1
fi

TARGET_DIR="$1"

if [[ ! -d "${TARGET_DIR}/.git" ]]; then
  echo "Error: ${TARGET_DIR} is not a git repository" >&2
  exit 1
fi

# --- Metadata helpers ---
#
# Sync metadata lives at <target>/.commons/sync.yaml. The legacy
# <target>/.dev-config/ path was supported during the migration documented
# in ADR-0014 and was removed once all consumers completed the rename.

METADATA_DIR="${TARGET_DIR}/.commons"
METADATA_FILE="${METADATA_DIR}/sync.yaml"
METADATA_REL="${METADATA_DIR#"${TARGET_DIR}/"}/sync.yaml"

# Read a flat list under `key` from a YAML file (block or flow style).
read_yaml_list() {
  local file="$1"
  local key="$2"
  if [[ ! -f "${file}" ]]; then
    return
  fi
  # Flow style: key: [item1, item2]
  local flow_line
  flow_line="$(grep -E "^${key}:[[:space:]]*\[" "${file}" || true)"
  if [[ -n "${flow_line}" ]]; then
    local body
    body="$(echo "${flow_line}" | sed -E "s/^${key}:[[:space:]]*\[(.*)\].*/\1/")"
    local IFS=','
    local item
    for item in ${body}; do
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"
      item="${item#\"}"
      item="${item%\"}"
      item="${item#\'}"
      item="${item%\'}"
      [[ -n "${item}" ]] && echo "${item}"
    done
    return
  fi
  # Block style
  local in_list=false
  while IFS= read -r line; do
    if [[ "${line}" == "${key}:" ]]; then
      in_list=true
      continue
    fi
    if ${in_list}; then
      if [[ -z "${line}" ]] || [[ "${line}" =~ ^[[:space:]]*# ]]; then
        continue
      fi
      if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        local val="${BASH_REMATCH[1]}"
        val="${val#\"}"
        val="${val%\"}"
        val="${val#\'}"
        val="${val%\'}"
        val="${val%"${val##*[! ]}"}"
        echo "${val}"
      else
        break
      fi
    fi
  done <"${file}"
}

# Read pinned list from metadata
read_pinned() { read_yaml_list "${METADATA_FILE}" "pinned"; }

is_pinned() {
  local file="$1"
  local pinned
  while IFS= read -r pinned; do
    if [[ "${pinned}" == "${file}" ]]; then
      return 0
    fi
  done < <(read_pinned)
  return 1
}

write_metadata() {
  local pinned_list=("$@")
  mkdir -p "${METADATA_DIR}"

  if ! COMMIT_HASH="$(git -C "${SCRIPT_DIR}" rev-parse HEAD 2>/dev/null)"; then
    echo "Warning: commons is not a git repository. Skipping metadata." >&2
    return
  fi
  SYNCED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Preserve skills fields managed by sync-skills.sh
  local existing_skills_commit=""
  local existing_skills_adapters=()
  if [[ -f "${METADATA_FILE}" ]]; then
    existing_skills_commit="$(grep '^skills_commit:' "${METADATA_FILE}" | awk '{print $2}' || true)"
    while IFS= read -r a; do existing_skills_adapters+=("${a}"); done < <(read_yaml_list "${METADATA_FILE}" "skills_adapters")
  fi

  local tmp_file="${METADATA_FILE}.tmp.$$"
  {
    echo "# Auto-updated by commons sync.sh"
    echo "# 'pinned' is user-editable — add or remove paths freely"
    echo "commit: ${COMMIT_HASH}"
    echo "synced_at: ${SYNCED_AT}"
    if [[ -n "${existing_skills_commit:-}" ]]; then
      echo "skills_commit: ${existing_skills_commit}"
    fi
    if [[ ${#existing_skills_adapters[@]} -gt 0 ]]; then
      echo "skills_adapters:"
      for a in "${existing_skills_adapters[@]}"; do echo "  - ${a}"; done
    fi
    if [[ ${#pinned_list[@]} -gt 0 ]]; then
      echo "pinned:"
      for p in "${pinned_list[@]}"; do
        echo "  - ${p}"
      done
    fi
  } >"${tmp_file}" && mv "${tmp_file}" "${METADATA_FILE}"
}

# --- Collect files ---

files_new=()
files_changed=()
files_unchanged=()
files_pinned=()

if [[ -d "${DIST_DIR}" ]]; then
  while IFS= read -r src_path; do
    rel_path="${src_path#"${DIST_DIR}/"}"
    dest_path="${TARGET_DIR}/${rel_path}"

    if is_pinned "${rel_path}"; then
      files_pinned+=("${rel_path}")
    elif [[ ! -f "${dest_path}" ]]; then
      files_new+=("${rel_path}")
    elif ! diff -q "${src_path}" "${dest_path}" >/dev/null 2>&1; then
      files_changed+=("${rel_path}")
    else
      files_unchanged+=("${rel_path}")
    fi
  done < <(find "${DIST_DIR}" -type f | sort)
fi

# --- Display summary ---

echo "Files:"
for f in "${files_new[@]+"${files_new[@]}"}"; do
  echo "  new:       ${f}"
done
for f in "${files_changed[@]+"${files_changed[@]}"}"; do
  echo "  changed:   ${f}"
done
for f in "${files_unchanged[@]+"${files_unchanged[@]}"}"; do
  echo "  unchanged: ${f}"
done
for f in "${files_pinned[@]+"${files_pinned[@]}"}"; do
  echo "  pinned:    ${f}"
done

# Count actionable items
total_copy=$((${#files_new[@]} + ${#files_changed[@]}))

# --- Check mode ---

if [[ "${CHECK}" == true ]]; then
  out_of_sync=$((${#files_new[@]} + ${#files_changed[@]}))
  if [[ ${out_of_sync} -gt 0 ]]; then
    echo "Files are out of sync."
    exit 1
  fi
  echo "All files are up to date."
  exit 0
fi

if [[ ${total_copy} -eq 0 ]]; then
  echo ""
  echo "Nothing to sync."
  exit 0
fi

echo ""
echo "${total_copy} file(s) to sync (${#files_new[@]} new, ${#files_changed[@]} changed)"

# --- Dry-run mode ---

if [[ "${DRY_RUN}" == true ]]; then
  exit 0
fi

# --- Collect current pinned list ---

current_pinned=()
while IFS= read -r p; do
  current_pinned+=("${p}")
done < <(read_pinned)

# --- Yes mode: copy all without confirmation ---

if [[ "${YES}" == true ]]; then
  for f in "${files_new[@]+"${files_new[@]}"}" "${files_changed[@]+"${files_changed[@]}"}"; do
    [[ -z "${f}" ]] && continue
    src="${DIST_DIR}/${f}"
    dest="${TARGET_DIR}/${f}"
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
    echo "  copy: ${f}"
  done
  write_metadata "${current_pinned[@]+"${current_pinned[@]}"}"
  echo "  write: ${METADATA_REL}"
  echo ""
  echo "Sync complete."
  exit 0
fi

# --- Interactive mode ---

copied=0

# Copy new files without confirmation
for f in "${files_new[@]+"${files_new[@]}"}"; do
  [[ -z "${f}" ]] && continue
  src="${DIST_DIR}/${f}"
  dest="${TARGET_DIR}/${f}"
  mkdir -p "$(dirname "${dest}")"
  cp "${src}" "${dest}"
  echo "  copy: ${f}"
  copied=$((copied + 1))
done

# Prompt for each changed file
update_all=false
for f in "${files_changed[@]+"${files_changed[@]}"}"; do
  [[ -z "${f}" ]] && continue
  src="${DIST_DIR}/${f}"
  dest="${TARGET_DIR}/${f}"

  if ${update_all}; then
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
    echo "  copy: ${f}"
    copied=$((copied + 1))
    continue
  fi

  echo ""
  echo "--- ${f} ---"
  diff -u "${dest}" "${src}" --label "target/${f}" --label "dist/${f}" || true
  echo ""
  read -r -p "  Update ${f}? [y/N/pin/all] " answer
  case "${answer}" in
  [yY])
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
    echo "  copy: ${f}"
    copied=$((copied + 1))
    ;;
  [pP] | pin)
    current_pinned+=("${f}")
    echo "  pinned: ${f}"
    ;;
  [aA] | all)
    update_all=true
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
    echo "  copy: ${f}"
    copied=$((copied + 1))
    ;;
  *)
    echo "  skip: ${f}"
    ;;
  esac
done

# Write metadata if any files were copied or pinned list changed
if [[ ${copied} -gt 0 ]] || [[ ${#current_pinned[@]} -gt 0 ]]; then
  write_metadata "${current_pinned[@]+"${current_pinned[@]}"}"
  echo "  write: ${METADATA_REL}"
fi

echo ""
echo "Sync complete."
