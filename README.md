English | [日本語](README.ja.md)

# dev-config

Shared configurations for OzzyLabs repositories.

## Structure

```text
dist/                -> Distributed to every repo
  .claude/
    skills/          -> Workflow skills
    rules/           -> Rules
    settings.json    -> Allowed tools and permissions
  .devcontainer/     -> Devcontainer config
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
  CLAUDE.md          -> Project overview template
  ...
sync.sh              -> Sync script
setup-repo.sh        -> GitHub repository setup script
```

## Usage

```bash
# Sync with interactive confirmation (shows diff for changed files)
/path/to/dev-config/sync.sh /path/to/target-repo

# Sync without confirmation (overwrite all changed files)
/path/to/dev-config/sync.sh --force /path/to/target-repo

# Preview changes without copying
/path/to/dev-config/sync.sh --dry-run /path/to/target-repo

# Check if files are in sync (for CI, exits 1 if out of sync)
/path/to/dev-config/sync.sh --check /path/to/target-repo

# Unpin a previously pinned file
/path/to/dev-config/sync.sh --unpin CLAUDE.md /path/to/target-repo
```

All files use the same sync policy. In interactive mode, changed files show a diff and prompt for action: update, skip, or pin (skip permanently). Pinned files are skipped in all modes including `--force`. After sync, metadata is written to `.dev-config/sync.yaml` in the target repo.

### Pin

When a file is intentionally customized in a target repo, it can be **pinned** to prevent future syncs from overwriting it. Pin during interactive sync by choosing `pin` at the prompt, or edit `.dev-config/sync.yaml` directly.

### Repository setup

```bash
# Configure GitHub repository settings
/path/to/dev-config/setup-repo.sh owner/repo

# Preview changes without applying
/path/to/dev-config/setup-repo.sh --dry-run owner/repo
```

Sets merge rules (squash only), branch protection (Rulesets), security settings, and Conventional Commits labels. See [ADR-0004](docs/adr/0004-repo-setup-with-rulesets.md) for design decisions.

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
