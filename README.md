English | [日本語](README.ja.md)

# commons

Shared configurations for OzzyLabs repositories.

## Structure

```text
dist/                -> Distributed to every repo
  .claude/
    rules/           -> Rules
    settings.json    -> Allowed tools and permissions
  .devcontainer/     -> Devcontainer config
  .gemini/
    settings.json    -> Gemini CLI config (loads AGENTS.md)
  .github/
    workflows/       -> PR title & branch name validation
    ISSUE_TEMPLATE/  -> Issue templates
    pull_request_template.md
  .vscode/           -> VS Code settings & extensions
  lefthook-base.yaml -> Shared lefthook base config
  lefthook.yaml      -> Lefthook config extending shared base
  .commitlintrc.yaml -> Commitlint config
  .editorconfig      -> Editor settings
  .gitattributes     -> Line ending normalization
  .mdformat.toml     -> Markdown formatter config
  .mise.toml         -> Tool version management
  trivy.yaml         -> Trivy security scanner config
  ...
templates/           -> Scaffold-only files (copied manually for new repos, never synced)
  AGENTS.md          -> Shared AI agent instructions template
  CLAUDE.md          -> Claude Code specific config
sync.sh              -> Sync script
sync-skills.sh       -> @ozzylabs/skills adapter sync script (opt-in per consumer)
setup-repo.sh        -> GitHub repository setup script
```

`templates/` ships starter content that every repo customizes (project name, tech stack, available skills). It is intentionally outside `dist/` so `sync.sh` never touches it — copy these files once when bootstrapping a new repo and edit in place.

Shared skills (`.agents/skills/`, `.claude/skills/`) are no longer distributed from this repo. They live in [`ozzy-labs/skills`](https://github.com/ozzy-labs/skills) and are pulled into consumer repos via the `@ozzylabs/skills` Renovate preset (see [ADR-0016](https://github.com/ozzy-labs/handbook/blob/main/adr/0016-create-skills-repo.md)).

## Usage

```bash
# OzzyLabs Commons CLI
/path/to/commons/commons <command> [args]

# Commands:
#   sync      Sync shared files
#   check     Run health check
#   setup     Initialize repository
#   skills    Sync skills adapters
```

### Sync

```bash
# Sync with interactive confirmation (shows diff for changed files)
commons sync /path/to/target-repo

# Sync without confirmation (overwrite all non-pinned changed files)
commons sync -y /path/to/target-repo

# Preview changes without copying
commons sync --dry-run /path/to/target-repo

# Check if files are in sync (for CI, exits 1 if out of sync)
commons sync --check /path/to/target-repo
```

All files use the same sync policy. In interactive mode, changed files show a diff and prompt for action: update (`y`), merge (`m`), skip (`N`), pin (`pin`), or update all remaining (`all`). Pinned files are skipped in all modes including `-y`. After sync, metadata is written to `.commons/sync.yaml` in the target repo.

### Check

```bash
# Run health check to verify compliance with OzzyLabs conventions
commons check /path/to/target-repo
```

Verifies:

- All shared files are in sync.
- Presence of mandatory files (`LICENSE`, `AGENTS.md`, etc.).
- Presence of required markers in Markdown and YAML files.
- Security configurations (Lefthook, Gitleaks).

### Pin

When a file is intentionally customized in a target repo, it can be **pinned** to prevent future syncs from overwriting it. Pin during interactive sync by choosing `pin` at the prompt, or edit `.commons/sync.yaml` directly.

### Metadata path

Sync metadata lives in the consumer repo at `.commons/sync.yaml`. `sync.sh` reads and writes this single canonical path, and the Renovate preset (`commons-sync.json`'s `managerFilePatterns`) tracks it for `commit:` field bumps.

The earlier `.dev-config/sync.yaml` path was supported as a temporary fallback during the migration documented in [ADR-0014](https://github.com/ozzy-labs/handbook/blob/main/adr/0014-rename-dev-config-to-commons.md). All consumers have now completed the rename and the fallback has been removed.

### Skills sync (opt-in per consumer)

Shared skills live in [`ozzy-labs/skills`](https://github.com/ozzy-labs/skills) and are produced as per-agent adapter outputs under `dist/{adapter-id}/`. Consumers opt in by listing adapter ids in `.commons/sync.yaml`:

```yaml
# Tracked by Renovate via the @ozzylabs/skills preset
skills_commit: <40-char-sha>

# Opt-in per consumer (manual)
skills_adapters:
  - claude-code   # → .claude/skills/{name}/
  - codex-cli     # → .agents/skills/{name}/ + AGENTS.md snippet
  - gemini-cli    # → .gemini/settings.json + AGENTS.md snippet
  - copilot       # → .github/copilot-instructions.md snippet
```

The consumer's sync workflow clones `ozzy-labs/skills` at `skills_commit:` and runs `sync-skills.sh` to apply the opted-in adapter outputs:

```bash
# Sync without confirmation (workflow use)
/path/to/commons/sync-skills.sh -y /path/to/skills/dist /path/to/target-repo

# Preview only
/path/to/commons/sync-skills.sh --dry-run /path/to/skills/dist /path/to/target-repo

# Check if files are in sync (CI, exits 1 if out of sync)
/path/to/commons/sync-skills.sh --check /path/to/skills/dist /path/to/target-repo
```

Snippet targets (`AGENTS.md`, `.github/copilot-instructions.md`) must already contain the marker block — only the content between `<!-- begin: @ozzylabs/skills -->` and `<!-- end: @ozzylabs/skills -->` is replaced. Pinning a path in the metadata file's `pinned:` list (with a trailing `/` for whole directories) skips it across all adapters. Consumer-only skill directories under `.claude/skills/` or `.agents/skills/` are preserved.

### Repository setup

```bash
# Configure GitHub repository settings
/path/to/commons/setup-repo.sh owner/repo

# Preview changes without applying
/path/to/commons/setup-repo.sh --dry-run owner/repo
```

Sets merge rules (squash only), branch protection (Rulesets), security settings, and Conventional Commits labels. See [ADR-0004](docs/adr/0004-repo-setup-with-rulesets.md) for design decisions.

### Automated sync (scheduled PR)

Consumer repos get a workflow distributed at `.github/workflows/sync-commons.yaml`. It runs weekly (Monday 00:00 UTC) and on manual dispatch, checks the repo against the latest `commons`, and — if any non-pinned file diverges — runs `sync.sh --yes` and opens a pull request. Review and merge manually; the workflow never auto-merges.

First-time setup for a consumer repo:

1. Run `sync.sh` manually once to pick up `sync-commons.yaml` into `.github/workflows/`
2. The repo settings must allow creating PRs (already the case if `setup-repo.sh` was run)
3. Make the org-level secrets `SYNC_APP_ID` and `SYNC_APP_PRIVATE_KEY` available to the repo. They belong to a GitHub App with `contents: write`, `pull-requests: write`, and `workflows: write` permissions installed on the org. The default `GITHUB_TOKEN` cannot push changes that touch `.github/workflows/*`, so the workflow uses an App token instead.
4. The weekly schedule takes over from the next Monday; `workflow_dispatch` lets you trigger it on demand

### Automated sync via Renovate (opt-in)

As a lower-latency alternative to the weekly schedule, consumer repos can opt into the `commons-sync` Renovate preset. Renovate watches the commons `main` branch and opens a PR bumping the `commit:` field in `.commons/sync.yaml` whenever a new commit lands. Actual file materialisation remains the consumer workflow's job (it runs `sync.sh --yes` on the Renovate PR branch).

Consumer `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>ozzy-labs/commons:commons-sync"]
}
```

Design details are in [ADR-0006](docs/adr/0006-renovate-auto-sync-preset.md). Consumer-side workflow integration is tracked by the Renovate PoC rollout (handbook#18 / handbook#42); until that lands, the scheduled workflow above is the supported path.

## What stays in each repo

- Domain-specific skills and rules
- Customized files after initial setup (pinned to prevent overwrite)

## Language

- Default: Japanese
- Public files (e.g., README): English with Japanese version
- Commit messages: English
- PR title: English
- PR description: Japanese

## Commit

[Conventional Commits](https://www.conventionalcommits.org/): `<type>[optional scope]: <description>`

Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore

## Branch

[GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow): `main` + feature branches (no direct push)

Naming: `<type>/<short-description>`

## Pull Request (PR)

Title: Conventional Commits format

Merge: squash merge only, delete branch after merge
