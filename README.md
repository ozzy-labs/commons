English | [日本語](README.ja.md)

# commons

Shared configurations for OzzyLabs repositories.

## Structure

```text
dist/                -> Distributed to every repo
  .agents/
    skills/          -> Shared skills (agentskills.io, SSOT)
  .claude/
    skills/          -> Claude Code skill overlays
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
  AGENTS.md          -> Shared AI agent instructions template
  CLAUDE.md          -> Claude Code specific config
  ...
sync.sh              -> Sync script
setup-repo.sh        -> GitHub repository setup script
```

## Usage

```bash
# Sync with interactive confirmation (shows diff for changed files)
/path/to/commons/sync.sh /path/to/target-repo

# Sync without confirmation (overwrite all non-pinned changed files)
/path/to/commons/sync.sh -y /path/to/target-repo

# Preview changes without copying
/path/to/commons/sync.sh --dry-run /path/to/target-repo

# Check if files are in sync (for CI, exits 1 if out of sync)
/path/to/commons/sync.sh --check /path/to/target-repo
```

All files use the same sync policy. In interactive mode, changed files show a diff and prompt for action: update, skip, pin (skip permanently), or update all remaining. Pinned files are skipped in all modes including `-y`. After sync, metadata is written to `.dev-config/sync.yaml` in the target repo.

### Pin

When a file is intentionally customized in a target repo, it can be **pinned** to prevent future syncs from overwriting it. Pin during interactive sync by choosing `pin` at the prompt, or edit `.dev-config/sync.yaml` directly.

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
3. The weekly schedule takes over from the next Monday; `workflow_dispatch` lets you trigger it on demand

### Automated sync via Renovate (opt-in)

As a lower-latency alternative to the weekly schedule, consumer repos can opt into the `commons-sync` Renovate preset. Renovate watches the commons `main` branch and opens a PR bumping `.dev-config/sync.yaml`'s `commit:` field whenever a new commit lands. Actual file materialisation remains the consumer workflow's job (it runs `sync.sh --yes` on the Renovate PR branch).

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
