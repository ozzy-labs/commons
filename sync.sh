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
QUIET=false
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
  --quiet)
    QUIET=true
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
  echo "    --quiet     Suppress next-step hints (CI use)" >&2
  exit 1
fi

TARGET_DIR="$1"

if [[ ! -d "${TARGET_DIR}/.git" ]]; then
  echo "Error: ${TARGET_DIR} is not a git repository" >&2
  exit 1
fi

# Print bootstrap-oriented next-step hints. Suppressed by --quiet so the
# scheduled sync-commons workflow doesn't clutter CI logs on every run.
print_next_steps() {
  ${QUIET} && return 0
  echo ""
  echo "Next steps:"
  echo "  1. Bootstrap templates (if a fresh repo):"
  echo "       ${SCRIPT_DIR}/init-templates.sh --name <name> ${TARGET_DIR}"
  echo "  2. (Optional) Opt in to @ozzylabs/skills:"
  echo "       Edit .commons/sync.yaml — set skills_commit and skills_adapters"
  echo "       Run:  ${SCRIPT_DIR}/sync-skills.sh -y <skills-repo>/dist ${TARGET_DIR}"
  echo "  3. Add project-specific files (package.json, src/, etc.)"
  echo "  4. Open a PR (chore/bootstrap → main)"
}

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

# Surgical files (JSON/YAML that should be merged instead of overwritten)
is_surgical() {
  local file="$1"
  case "${file}" in
  *.json | *.yaml | *.yml)
    # Exclude certain files that should be handled as a whole
    [[ "${file}" == "lefthook.yaml" ]] && return 1
    # lefthook-base.yaml is a shared base; consumers extend it via lefthook.yaml
    # and never add keys to it. yq surgical merge would compound free-floating
    # header comments and reorder appended commands across syncs.
    [[ "${file}" == "lefthook-base.yaml" ]] && return 1
    # _template scaffolds — full copy preserves comments and layout.
    # Matches both legacy directory form (`_template/<file>`) and current
    # single-file form (`_template.yaml`).
    [[ "${file}" == */_template/* ]] && return 1
    [[ "${file}" == */_template.yaml ]] && return 1
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

surgical_merge() {
  local src="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp)"
  # Merge dist into target. dist (fileIndex 1) overrides target (fileIndex 0).
  if ! yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "${dest}" "${src}" >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    return 1
  fi
  mv "${tmp}" "${dest}"
}

# Marker sections (part of a file managed by commons)
get_markers() {
  local file="$1"
  case "${file}" in
  *.md | *.html | *.xml)
    echo "<!-- begin: ozzy-labs/commons -->|<!-- end: ozzy-labs/commons -->"
    ;;
  *)
    echo "# begin: ozzy-labs/commons|# end: ozzy-labs/commons"
    ;;
  esac
}

has_markers() {
  local file="$1"
  [[ ! -f "${file}" ]] && return 1
  IFS='|' read -r begin end < <(get_markers "${file}")
  grep -q "${begin}" "${file}" && grep -q "${end}" "${file}"
}

compare_marked_sections() {
  local src="$1"
  local dest="$2"
  IFS='|' read -r begin end < <(get_markers "${src}")
  local src_section dest_section
  src_section="$(awk -v begin="${begin}" -v end="${end}" 'index($0, begin) > 0 { in_block = 1 } in_block { print } index($0, end) > 0 { in_block = 0 }' "${src}")"
  dest_section="$(awk -v begin="${begin}" -v end="${end}" 'index($0, begin) > 0 { in_block = 1 } in_block { print } index($0, end) > 0 { in_block = 0 }' "${dest}")"
  [[ "${src_section}" == "${dest_section}" ]]
}

is_file_changed() {
  local src="$1"
  local dest="$2"
  if has_markers "${src}" && has_markers "${dest}"; then
    if compare_marked_sections "${src}" "${dest}"; then
      return 1 # Not changed
    else
      return 0 # Changed
    fi
  else
    if diff -q "${src}" "${dest}" >/dev/null 2>&1; then
      return 1 # Not changed
    else
      return 0 # Changed
    fi
  fi
}

merge_marker_section() {
  local src="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp)"
  IFS='|' read -r begin end < <(get_markers "${src}")
  # Use awk to replace the section in dest with the section from src.
  # The src file must contain the marker block.
  awk -v src_file="${src}" -v begin="${begin}" -v end="${end}" '
    BEGIN {
      in_src = 0
      while ((getline line < src_file) > 0) {
        if (index(line, begin) > 0) in_src = 1
        if (in_src) src_lines[++n] = line
        if (index(line, end) > 0) in_src = 0
      }
      close(src_file)
    }
    index($0, begin) > 0 {
      for (i=1; i<=n; i++) print src_lines[i]
      in_block = 1
      next
    }
    index($0, end) > 0 {
      in_block = 0
      next
    }
    !in_block { print }
  ' "${dest}" >"${tmp}"
  mv "${tmp}" "${dest}"
}

# Strip surrounding double or single quotes from a pinned path value.
strip_yaml_quotes() {
  local v="$1"
  if [[ "${v}" =~ ^\".*\"$ ]]; then
    v="${v:1:${#v}-2}"
  elif [[ "${v}" =~ ^\'.*\'$ ]]; then
    v="${v:1:${#v}-2}"
  fi
  printf '%s' "${v}"
}

# Extract user-added comments from an existing metadata file so the regenerated
# template can preserve them. Two outputs are produced:
#   1. ${header_out}: the contiguous comment block immediately above `pinned:`
#      (excluding any blank line that separates it from prior content). Empty
#      when no such block exists.
#   2. ${entry_out}: a flat record stream where each pinned entry that has
#      preceding comments emits one or more `<path>\t<comment-line>` records
#      (one record per comment line, in source order). Records for paths that
#      are no longer in the pinned list are simply ignored by the restore step.
# Both outputs are truncated before writing. The function is a no-op when the
# source file does not exist.
extract_pinned_comments() {
  local src="$1"
  local header_out="$2"
  local entry_out="$3"
  : >"${header_out}"
  : >"${entry_out}"
  [[ -f "${src}" ]] || return 0

  local line trimmed
  local in_pinned=false
  local -a header_buf=()
  local -a entry_buf=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if ! ${in_pinned}; then
      if [[ "${line}" =~ ^[[:space:]]*# ]]; then
        header_buf+=("${line}")
      elif [[ -z "${line}" || "${line}" =~ ^[[:space:]]*$ ]]; then
        # Blank line resets header candidate
        header_buf=()
      elif [[ "${line}" =~ ^pinned:[[:space:]]*$ ]]; then
        # Flush header candidate as the pinned header block
        if [[ ${#header_buf[@]} -gt 0 ]]; then
          printf '%s\n' "${header_buf[@]}" >>"${header_out}"
        fi
        header_buf=()
        in_pinned=true
      else
        # Other content line resets header candidate
        header_buf=()
      fi
      continue
    fi

    # Inside `pinned:` section
    if [[ "${line}" =~ ^[[:space:]]*# ]]; then
      entry_buf+=("${line}")
      continue
    fi
    if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
      trimmed="${BASH_REMATCH[1]}"
      # Strip trailing whitespace
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      local path
      path="$(strip_yaml_quotes "${trimmed}")"
      if [[ ${#entry_buf[@]} -gt 0 ]]; then
        local c
        for c in "${entry_buf[@]}"; do
          printf '%s\t%s\n' "${path}" "${c}" >>"${entry_out}"
        done
      fi
      entry_buf=()
      continue
    fi
    if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*$ ]]; then
      # Blank line: drop pending entry comments (they were detached)
      entry_buf=()
      continue
    fi
    # Any other content line ends the pinned section
    in_pinned=false
    entry_buf=()
  done <"${src}"
}

# Restore header block (above `pinned:`) and per-entry comments inside the
# regenerated metadata file. Operates in place on ${target}. Per-entry comments
# whose path is no longer in the pinned list are dropped (entries removed from
# pinned lose their comments by design).
restore_pinned_comments() {
  local target="$1"
  local header_in="$2"
  local entry_in="$3"
  local tmp
  tmp="$(mktemp)"

  local in_pinned=false
  local line trimmed path c
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if ! ${in_pinned} && [[ "${line}" =~ ^pinned:[[:space:]]*$ ]]; then
      # Emit preserved header block before `pinned:`
      if [[ -s "${header_in}" ]]; then
        cat "${header_in}" >>"${tmp}"
      fi
      printf '%s\n' "${line}" >>"${tmp}"
      in_pinned=true
      continue
    fi
    if ${in_pinned} && [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
      trimmed="${BASH_REMATCH[1]}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      path="$(strip_yaml_quotes "${trimmed}")"
      # Emit any preserved comment lines whose first field == path
      if [[ -s "${entry_in}" ]]; then
        while IFS=$'\t' read -r p c; do
          if [[ "${p}" == "${path}" ]]; then
            printf '%s\n' "${c}" >>"${tmp}"
          fi
        done <"${entry_in}"
      fi
      printf '%s\n' "${line}" >>"${tmp}"
      continue
    fi
    if ${in_pinned}; then
      # Section ends on any non-(`-`/`#`/blank) line
      if [[ -n "${line}" && ! "${line}" =~ ^[[:space:]]*$ ]] &&
        [[ ! "${line}" =~ ^[[:space:]]*- ]] &&
        [[ ! "${line}" =~ ^[[:space:]]*# ]]; then
        in_pinned=false
      fi
    fi
    printf '%s\n' "${line}" >>"${tmp}"
  done <"${target}"

  mv "${tmp}" "${target}"
}

write_metadata() {
  local pinned_list=("$@")
  mkdir -p "${METADATA_DIR}"

  if ! COMMIT_HASH="$(git -C "${SCRIPT_DIR}" rev-parse HEAD 2>/dev/null)"; then
    echo "Warning: commons is not a git repository. Skipping metadata." >&2
    return
  fi
  SYNCED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Preserve skills fields managed by sync-skills.sh. We always emit the
  # skills_commit / skills_adapters keys (with empty defaults if unset) so
  # consumers can opt in by editing the metadata file directly without
  # consulting external docs — the explanatory comment below names the
  # exact gh command to fetch the SHA.
  local existing_skills_commit=""
  local existing_skills_adapters=()
  if [[ -f "${METADATA_FILE}" ]]; then
    existing_skills_commit="$(grep '^skills_commit:' "${METADATA_FILE}" | awk '{print $2}' | tr -d '"' || true)"
    while IFS= read -r a; do existing_skills_adapters+=("${a}"); done < <(read_yaml_list "${METADATA_FILE}" "skills_adapters")
  fi

  # Extract user-added comments (pinned header block + per-entry comments) so
  # they survive the heredoc-style template regeneration. See Issue #136.
  local header_tmp="${METADATA_FILE}.hdr.$$"
  local entry_tmp="${METADATA_FILE}.ent.$$"
  extract_pinned_comments "${METADATA_FILE}" "${header_tmp}" "${entry_tmp}"

  local tmp_file="${METADATA_FILE}.tmp.$$"
  {
    echo "# Updated by /sync-consumers (push mode). 'commit' / 'skills_commit'"
    echo "# log the last applied SHA; updates are pushed from ozzy-labs/commons"
    echo "# (and ozzy-labs/skills) via the /sync-consumers skill, see"
    echo "# ozzy-labs/skills#80. 'pinned' is user-editable — add or remove paths"
    echo "# freely. 'commit' / 'skills_commit' / 'synced_at' should not be hand-"
    echo "# edited; they are rewritten by sync.sh / sync-skills.sh on each push."
    echo "commit: ${COMMIT_HASH}"
    echo "synced_at: ${SYNCED_AT}"
    echo ""
    echo "# Skills sync (opt-in). Add adapter ids to skills_adapters; skills_commit"
    echo "# is bumped by /sync-consumers --source=skills. The skills repo's main"
    echo "# HEAD SHA can be obtained via:"
    echo "#   gh api repos/ozzy-labs/skills/commits/main --jq .sha"
    if [[ -n "${existing_skills_commit:-}" ]]; then
      echo "skills_commit: ${existing_skills_commit}"
    else
      echo "skills_commit: \"\""
    fi
    if [[ ${#existing_skills_adapters[@]} -gt 0 ]]; then
      echo "skills_adapters:"
      for a in "${existing_skills_adapters[@]}"; do echo "  - ${a}"; done
    else
      echo "skills_adapters: []"
    fi
    if [[ ${#pinned_list[@]} -gt 0 ]]; then
      echo "pinned:"
      for p in "${pinned_list[@]}"; do
        echo "  - ${p}"
      done
    fi
  } >"${tmp_file}"

  # Re-inject preserved comments (header above `pinned:` and per-entry blocks).
  # No-op when both temp files are empty (e.g. first-time init).
  if [[ -s "${header_tmp}" ]] || [[ -s "${entry_tmp}" ]]; then
    restore_pinned_comments "${tmp_file}" "${header_tmp}" "${entry_tmp}"
  fi
  rm -f "${header_tmp}" "${entry_tmp}"

  mv "${tmp_file}" "${METADATA_FILE}"
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
    elif is_file_changed "${src_path}" "${dest_path}"; then
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

    if has_markers "${src}" && has_markers "${dest}"; then
      merge_marker_section "${src}" "${dest}"
      echo "  merge (section): ${f}"
      continue
    fi

    if [[ -f "${dest}" ]] && is_surgical "${f}"; then
      if surgical_merge "${src}" "${dest}"; then
        echo "  merge: ${f}"
        continue
      else
        echo "  warning: surgical merge failed for ${f}, falling back to copy" >&2
      fi
    fi

    cp "${src}" "${dest}"
    echo "  copy: ${f}"
  done
  write_metadata "${current_pinned[@]+"${current_pinned[@]}"}"
  echo "  write: ${METADATA_REL}"
  echo ""
  echo "Sync complete."
  print_next_steps
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

  prompt="  Update ${f}? [y/N/pin/all]"
  if is_surgical "${f}" || (has_markers "${src}" && has_markers "${dest}"); then
    prompt="  Update ${f}? [y/N/m/pin/all]"
  fi

  read -r -p "${prompt} " answer
  case "${answer}" in
  [yY])
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
    echo "  copy: ${f}"
    copied=$((copied + 1))
    ;;
  [mM] | merge)
    if has_markers "${src}" && has_markers "${dest}"; then
      merge_marker_section "${src}" "${dest}"
      echo "  merge (section): ${f}"
      copied=$((copied + 1))
    elif is_surgical "${f}"; then
      if surgical_merge "${src}" "${dest}"; then
        echo "  merge: ${f}"
        copied=$((copied + 1))
      else
        echo "  error: surgical merge failed"
      fi
    else
      echo "  error: ${f} is not mergable (no markers or not structured)"
    fi
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
print_next_steps
