#!/usr/bin/env bash
set -euo pipefail

# commons sync-skills script
#
# Sync @ozzylabs/skills adapter outputs (dist/{adapter-id}/) from a local
# clone of the skills repo into a consumer repo. Consumer opts in by listing
# adapter ids in `.dev-config/sync.yaml`:
#
#   skills_adapters:
#     - claude-code
#     - codex-cli
#
# Caller (typically a workflow) is responsible for cloning ozzy-labs/skills
# at the SHA recorded in `.dev-config/sync.yaml`'s `skills_commit:` field
# and pointing this script at its `dist/` directory.
#
# Usage:
#   sync-skills.sh [options] <skills-dist-root> <target-repo-path>
#
# Options:
#   -y, --yes    Sync without confirmation (default if no flag)
#   --dry-run    Show what would be synced without copying
#   --check      Exit 1 if non-pinned files are out of sync (for CI)

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

if [[ $# -lt 2 ]]; then
  echo "Usage:" >&2
  echo "  $0 [options] <skills-dist-root> <target-repo-path>" >&2
  echo "  Options:" >&2
  echo "    -y, --yes   Sync without confirmation" >&2
  echo "    --dry-run   Show what would be synced without copying" >&2
  echo "    --check     Exit 1 if non-pinned files are out of sync (for CI)" >&2
  exit 1
fi

SKILLS_DIST="${1%/}"
TARGET_DIR="${2%/}"

if [[ ! -d "${SKILLS_DIST}" ]]; then
  echo "Error: skills dist root not found: ${SKILLS_DIST}" >&2
  exit 1
fi

if [[ ! -d "${TARGET_DIR}/.git" ]]; then
  echo "Error: ${TARGET_DIR} is not a git repository" >&2
  exit 1
fi

METADATA_FILE="${TARGET_DIR}/.dev-config/sync.yaml"

# --- YAML helpers ---

# Read a flat list under `key` from a YAML file. Supports both styles:
#
#   key:
#     - item1
#     - item2
#
#   key: [item1, item2]
#
# Returns one item per line.
read_yaml_list() {
  local file="$1"
  local key="$2"
  if [[ ! -f "${file}" ]]; then
    return
  fi

  # Flow style first
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

read_pinned() { read_yaml_list "${METADATA_FILE}" "pinned"; }
read_adapters() { read_yaml_list "${METADATA_FILE}" "skills_adapters"; }

is_pinned() {
  local file="$1"
  local pinned
  while IFS= read -r pinned; do
    [[ -z "${pinned}" ]] && continue
    if [[ "${pinned}" == "${file}" ]]; then
      return 0
    fi
    # Directory pin (trailing slash) skips every file under the prefix
    if [[ "${pinned: -1}" == "/" ]]; then
      local plen=${#pinned}
      if [[ "${#file}" -gt ${plen} ]] && [[ "${file:0:${plen}}" == "${pinned}" ]]; then
        return 0
      fi
    fi
  done < <(read_pinned)
  return 1
}

# --- Adapter setup ---

ADAPTERS=()
while IFS= read -r a; do
  [[ -z "${a}" ]] && continue
  ADAPTERS+=("${a}")
done < <(read_adapters)

if [[ ${#ADAPTERS[@]} -eq 0 ]]; then
  echo "No skills_adapters configured in ${METADATA_FILE}."
  echo "Nothing to sync."
  exit 0
fi

VALID_ADAPTERS=("claude-code" "codex-cli" "gemini-cli" "copilot")
for a in "${ADAPTERS[@]}"; do
  found=false
  for v in "${VALID_ADAPTERS[@]}"; do
    if [[ "${a}" == "${v}" ]]; then
      found=true
      break
    fi
  done
  if ! ${found}; then
    echo "Error: unknown adapter '${a}' in skills_adapters" >&2
    echo "Valid adapters: ${VALID_ADAPTERS[*]}" >&2
    exit 1
  fi
done

# --- Pending operation tables ---
# Each pending op encoded as "src|dest|kind|rel" where kind ∈ {file, snippet}.
pending_ops=()
pending_pinned=()
pending_unchanged=()

# Replace marker block in TARGET with the SNIPPET content (which itself
# contains both begin and end markers); print result to stdout.
replace_snippet_to_stdout() {
  local target="$1" snippet="$2"
  awk -v snippet_file="${snippet}" '
    BEGIN { in_block = 0 }
    /<!-- begin: @ozzylabs\/skills -->/ && !in_block {
      while ((getline line < snippet_file) > 0) print line
      close(snippet_file)
      in_block = 1
      next
    }
    /<!-- end: @ozzylabs\/skills -->/ && in_block {
      in_block = 0
      next
    }
    !in_block { print }
  ' "${target}"
}

add_file_op() {
  local src="$1" dest="$2" rel="$3"
  if is_pinned "${rel}"; then
    pending_pinned+=("${rel}")
    return
  fi
  if [[ -f "${dest}" ]] && diff -q "${src}" "${dest}" >/dev/null 2>&1; then
    pending_unchanged+=("${rel}")
    return
  fi
  pending_ops+=("${src}|${dest}|file|${rel}")
}

add_snippet_op() {
  local snippet="$1" target="$2" rel="$3"
  if is_pinned "${rel}"; then
    pending_pinned+=("${rel}")
    return
  fi
  if [[ -f "${target}" ]] && grep -q '<!-- begin: @ozzylabs/skills -->' "${target}"; then
    local new_content current
    new_content="$(replace_snippet_to_stdout "${target}" "${snippet}")"
    current="$(cat "${target}")"
    if [[ "${new_content}" == "${current}" ]]; then
      pending_unchanged+=("${rel}")
      return
    fi
  fi
  pending_ops+=("${snippet}|${target}|snippet|${rel}")
}

# Per-skill-dir copy: iterate every file under the source skill dirs.
# Consumer-only skill dirs are preserved (we never delete the parent dir).
collect_skill_dir_ops() {
  local src_dir="$1" dst_dir="$2"
  local skill_dir file rel_in_dir dst_file rel
  for skill_dir in "${src_dir}"/*/; do
    [[ -d "${skill_dir}" ]] || continue
    while IFS= read -r file; do
      rel_in_dir="${file#"${src_dir}/"}"
      dst_file="${dst_dir}/${rel_in_dir}"
      rel="${dst_file#"${TARGET_DIR}/"}"
      add_file_op "${file}" "${dst_file}" "${rel}"
    done < <(find "${skill_dir}" -type f | sort)
  done
}

# --- Plan operations per adapter ---

for a in "${ADAPTERS[@]}"; do
  case "${a}" in
  claude-code)
    src_root="${SKILLS_DIST}/claude-code/.claude/skills"
    if [[ ! -d "${src_root}" ]]; then
      echo "Error: ${src_root} not found in skills dist" >&2
      exit 1
    fi
    collect_skill_dir_ops "${src_root}" "${TARGET_DIR}/.claude/skills"
    ;;
  codex-cli)
    src_root="${SKILLS_DIST}/codex-cli/.agents/skills"
    snippet="${SKILLS_DIST}/codex-cli/AGENTS.md.snippet"
    if [[ ! -d "${src_root}" ]]; then
      echo "Error: ${src_root} not found in skills dist" >&2
      exit 1
    fi
    if [[ ! -f "${snippet}" ]]; then
      echo "Error: ${snippet} not found in skills dist" >&2
      exit 1
    fi
    collect_skill_dir_ops "${src_root}" "${TARGET_DIR}/.agents/skills"
    add_snippet_op "${snippet}" "${TARGET_DIR}/AGENTS.md" "AGENTS.md"
    ;;
  gemini-cli)
    src_settings="${SKILLS_DIST}/gemini-cli/.gemini/settings.json"
    snippet="${SKILLS_DIST}/gemini-cli/AGENTS.md.snippet"
    if [[ ! -f "${src_settings}" ]]; then
      echo "Error: ${src_settings} not found in skills dist" >&2
      exit 1
    fi
    if [[ ! -f "${snippet}" ]]; then
      echo "Error: ${snippet} not found in skills dist" >&2
      exit 1
    fi
    add_file_op "${src_settings}" "${TARGET_DIR}/.gemini/settings.json" ".gemini/settings.json"
    add_snippet_op "${snippet}" "${TARGET_DIR}/AGENTS.md" "AGENTS.md"
    ;;
  copilot)
    snippet="${SKILLS_DIST}/copilot/.github/copilot-instructions.md.snippet"
    if [[ ! -f "${snippet}" ]]; then
      echo "Error: ${snippet} not found in skills dist" >&2
      exit 1
    fi
    add_snippet_op "${snippet}" "${TARGET_DIR}/.github/copilot-instructions.md" ".github/copilot-instructions.md"
    ;;
  esac
done

# --- Display summary ---

echo "Skills sync (adapters: ${ADAPTERS[*]}):"
for entry in "${pending_ops[@]+"${pending_ops[@]}"}"; do
  IFS='|' read -r _src dest _kind rel <<<"${entry}"
  if [[ -f "${dest}" ]]; then
    echo "  changed:   ${rel}"
  else
    echo "  new:       ${rel}"
  fi
done
for f in "${pending_unchanged[@]+"${pending_unchanged[@]}"}"; do
  echo "  unchanged: ${f}"
done
for f in "${pending_pinned[@]+"${pending_pinned[@]}"}"; do
  echo "  pinned:    ${f}"
done

# --- Check mode ---

if ${CHECK}; then
  if [[ ${#pending_ops[@]} -gt 0 ]]; then
    echo "Skills are out of sync."
    exit 1
  fi
  echo "All skill files are up to date."
  exit 0
fi

if [[ ${#pending_ops[@]} -eq 0 ]]; then
  echo ""
  echo "Nothing to sync."
  exit 0
fi

echo ""
echo "${#pending_ops[@]} file(s) to sync"

if ${DRY_RUN}; then
  exit 0
fi

# Bulk confirmation prompt for manual use; workflows pass -y to skip.
if ! ${YES}; then
  read -r -p "Apply changes? [y/N] " answer
  case "${answer}" in
  [yY] | yes | YES) ;;
  *)
    echo "Aborted."
    exit 0
    ;;
  esac
fi

# --- Apply ---

for entry in "${pending_ops[@]}"; do
  IFS='|' read -r src dest kind rel <<<"${entry}"
  mkdir -p "$(dirname "${dest}")"
  if [[ "${kind}" == "snippet" ]]; then
    if [[ ! -f "${dest}" ]]; then
      echo "Error: ${dest} does not exist (expected to contain @ozzylabs/skills marker block)" >&2
      exit 1
    fi
    if ! grep -q '<!-- begin: @ozzylabs/skills -->' "${dest}"; then
      echo "Error: ${dest} is missing the '<!-- begin: @ozzylabs/skills -->' marker" >&2
      exit 1
    fi
    tmp="${dest}.tmp.$$"
    replace_snippet_to_stdout "${dest}" "${src}" >"${tmp}" && mv "${tmp}" "${dest}"
    echo "  snippet: ${rel}"
  else
    cp "${src}" "${dest}"
    echo "  copy: ${rel}"
  fi
done

echo ""
echo "Sync complete."
