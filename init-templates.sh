#!/usr/bin/env bash
set -euo pipefail

# init-templates.sh
#
# Bootstrap a new repo from commons/templates/: copy AGENTS.md and CLAUDE.md
# into the target, substitute Mustache-style placeholders, and (optionally)
# apply description / topics to the GitHub repo via the gh CLI.
#
# Usage:
#   init-templates.sh [options] <target-repo-path>
#
# Options:
#   --name <name>         Required. Substituted for {{project_name}}.
#   --description <desc>  Substituted for {{description}}; also applied to
#                         the GitHub repo if --repo (or origin) is set.
#   --topics <t1,t2,...>  Comma-separated topics; replaces the repo's topic
#                         list on GitHub. Requires --repo or origin remote.
#   --repo <owner/repo>   Override repo detection. Default: parsed from the
#                         target's `git remote get-url origin`.
#   --skip-gh-edit        Skip the gh API calls; only do the file ops.
#   --force               Overwrite existing template files in the target
#                         without prompting.
#   --dry-run             Show what would happen without changing anything.
#
# Behavior:
#   1. Copy templates/AGENTS.md and templates/CLAUDE.md to <target>.
#   2. Substitute {{project_name}} and {{description}} placeholders.
#   3. If --description or --topics is given, run gh api to update the repo
#      metadata. (Skipped when --skip-gh-edit, --dry-run, or no repo.)
#   4. Existing files in the target are protected: aborts with a diff
#      summary unless --force is passed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

NAME=""
DESCRIPTION=""
TOPICS=""
REPO=""
SKIP_GH_EDIT=false
FORCE=false
DRY_RUN=false
QUIET=false

while [[ "${1:-}" == --* ]]; do
  case "$1" in
  --name)
    NAME="$2"
    shift 2
    ;;
  --description)
    DESCRIPTION="$2"
    shift 2
    ;;
  --topics)
    TOPICS="$2"
    shift 2
    ;;
  --repo)
    REPO="$2"
    shift 2
    ;;
  --skip-gh-edit)
    SKIP_GH_EDIT=true
    shift
    ;;
  --force)
    FORCE=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
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

usage() {
  echo "Usage:" >&2
  echo "  $0 [options] <target-repo-path>" >&2
  echo "  Required:" >&2
  echo "    --name <name>           Substituted for {{project_name}}" >&2
  echo "  Optional:" >&2
  echo "    --description <desc>    Substituted for {{description}} and applied to repo" >&2
  echo "    --topics <t1,t2,...>    Comma-separated topics applied to repo" >&2
  echo "    --repo <owner/repo>     Override repo detection (default: target's origin)" >&2
  echo "    --skip-gh-edit          Skip gh metadata update" >&2
  echo "    --force                 Overwrite existing files without prompting" >&2
  echo "    --dry-run               Show what would happen without changing anything" >&2
  echo "    --quiet                 Suppress next-step hints (CI use)" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ -z "${NAME}" ]]; then
  echo "Error: --name is required" >&2
  usage
  exit 1
fi

TARGET_DIR="${1%/}"

if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "Error: target directory not found: ${TARGET_DIR}" >&2
  exit 1
fi

# Auto-detect repo from target's git remote if not specified.
if [[ -z "${REPO}" ]] && [[ -d "${TARGET_DIR}/.git" ]]; then
  if origin_url="$(git -C "${TARGET_DIR}" remote get-url origin 2>/dev/null)"; then
    # Strip git@github.com: or https://github.com/ prefix and trailing .git
    REPO="${origin_url#git@github.com:}"
    REPO="${REPO#https://github.com/}"
    REPO="${REPO%.git}"
  fi
fi

# --- Plan phase: figure out what would change ---

new_files=()
overwrite_files=()
unchanged_files=()
template_files=("AGENTS.md" "CLAUDE.md")

# Render a template by substituting {{project_name}} and {{description}}.
# Uses awk with -v and `index()`-based literal substring replacement so user
# values containing regex / sed metacharacters or `&` (which would normally
# expand to the matched text inside gsub's replacement) are interpreted
# verbatim.
render_template() {
  local src="$1"
  awk -v name="${NAME}" -v desc="${DESCRIPTION}" '
    function lit_replace(line, needle, repl,    out, idx, nlen) {
      out = ""
      nlen = length(needle)
      while ((idx = index(line, needle)) > 0) {
        out = out substr(line, 1, idx - 1) repl
        line = substr(line, idx + nlen)
      }
      return out line
    }
    {
      $0 = lit_replace($0, "{{project_name}}", name)
      $0 = lit_replace($0, "{{description}}", desc)
      print
    }
  ' "${src}"
}

for f in "${template_files[@]}"; do
  src="${TEMPLATES_DIR}/${f}"
  if [[ ! -f "${src}" ]]; then
    echo "Error: template not found: ${src}" >&2
    exit 1
  fi
  dest="${TARGET_DIR}/${f}"
  if [[ ! -f "${dest}" ]]; then
    new_files+=("${f}")
    continue
  fi
  rendered="$(render_template "${src}")"
  if [[ "$(cat "${dest}")" == "${rendered}" ]]; then
    unchanged_files+=("${f}")
  else
    overwrite_files+=("${f}")
  fi
done

# --- Display plan ---

echo "Templates plan (target: ${TARGET_DIR}):"
for f in "${new_files[@]+"${new_files[@]}"}"; do
  echo "  new:       ${f}"
done
for f in "${overwrite_files[@]+"${overwrite_files[@]}"}"; do
  echo "  overwrite: ${f}"
done
for f in "${unchanged_files[@]+"${unchanged_files[@]}"}"; do
  echo "  unchanged: ${f}"
done

# Plan gh metadata update
GH_DESC=false
GH_TOPICS=false
if ! ${SKIP_GH_EDIT}; then
  if [[ -n "${DESCRIPTION}" ]] && [[ -n "${REPO}" ]]; then
    GH_DESC=true
  fi
  if [[ -n "${TOPICS}" ]] && [[ -n "${REPO}" ]]; then
    GH_TOPICS=true
  fi
fi

if ${GH_DESC} || ${GH_TOPICS}; then
  echo ""
  echo "GitHub metadata (${REPO}):"
  ${GH_DESC} && echo "  description: ${DESCRIPTION}"
  ${GH_TOPICS} && echo "  topics:      ${TOPICS}"
fi

# --- Existing-file protection ---

if [[ ${#overwrite_files[@]} -gt 0 ]] && ! ${FORCE} && ! ${DRY_RUN}; then
  echo ""
  echo "Refusing to overwrite existing files. Pass --force to apply." >&2
  for f in "${overwrite_files[@]}"; do
    echo "  diff for ${f}:" >&2
    diff -u "${TARGET_DIR}/${f}" <(render_template "${TEMPLATES_DIR}/${f}") --label "current/${f}" --label "rendered/${f}" || true
  done
  exit 1
fi

if ${DRY_RUN}; then
  echo ""
  echo "Dry run — no changes made."
  exit 0
fi

# --- Apply file ops ---

for f in "${new_files[@]+"${new_files[@]}"}" "${overwrite_files[@]+"${overwrite_files[@]}"}"; do
  [[ -z "${f}" ]] && continue
  src="${TEMPLATES_DIR}/${f}"
  dest="${TARGET_DIR}/${f}"
  render_template "${src}" >"${dest}"
  echo "  write: ${f}"
done

# --- Apply gh metadata ---

if ${GH_DESC} || ${GH_TOPICS}; then
  if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is not installed. Skipping repo metadata update." >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh CLI is not authenticated. Run 'gh auth login' first." >&2
    exit 1
  fi

  if ${GH_DESC}; then
    if gh api --method PATCH "/repos/${REPO}" -f "description=${DESCRIPTION}" >/dev/null; then
      echo "  gh: description updated"
    else
      echo "  ⚠ gh: description update failed" >&2
    fi
  fi

  if ${GH_TOPICS}; then
    # GitHub's PUT /repos/{owner}/{repo}/topics expects {"names": [...]} and
    # replaces the entire topic list. Build --field names[]= for each topic.
    topic_args=()
    IFS=',' read -ra TOPIC_ARRAY <<<"${TOPICS}"
    for t in "${TOPIC_ARRAY[@]}"; do
      # Trim whitespace
      t="${t#"${t%%[![:space:]]*}"}"
      t="${t%"${t##*[![:space:]]}"}"
      [[ -z "${t}" ]] && continue
      topic_args+=(--field "names[]=${t}")
    done
    if gh api --method PUT "/repos/${REPO}/topics" "${topic_args[@]}" >/dev/null; then
      echo "  gh: topics updated"
    else
      echo "  ⚠ gh: topics update failed" >&2
    fi
  fi
fi

echo ""
echo "Templates init complete."

if ! ${QUIET}; then
  echo ""
  echo "Next steps:"
  echo "  1. Edit AGENTS.md / CLAUDE.md to fill in tech stack and project specifics"
  echo "  2. Add project-specific files (package.json, src/, etc.)"
  echo "  3. Commit and open a PR (chore/bootstrap → main)"
fi
