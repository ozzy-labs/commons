English | [日本語](README.ja.md)

# dev-config

Shared configurations for OzzyLabs repositories.

## Structure

```text
shared/          -> Synced to every repo (always overwrite)
  .claude/
    skills/      -> Shared workflow skills
    rules/       -> Shared rules
templates/       -> Copied on initial setup only (if not exists)
  CLAUDE.md
  .claude/
    settings.json
    skills/lint-rules/
sync.sh          -> Sync script
```

## Usage

```bash
# Sync with confirmation
/path/to/dev-config/sync.sh /path/to/target-repo

# Sync without confirmation
/path/to/dev-config/sync.sh --force /path/to/target-repo

# Preview changes without copying
/path/to/dev-config/sync.sh --dry-run /path/to/target-repo
```

Shared files are always overwritten. Templates are copied only if the target file does not exist. After sync, a metadata file (`.claude/.dev-config-sync`) is written to the target with the source commit hash and timestamp.

## What is shared

| Type | Files | Purpose |
|------|-------|---------|
| Skills | commit, commit-conventions, drive, implement, lint, pr, review, ship, test | Workflow orchestration |
| Rules | git-workflow.md | Branch, commit, PR conventions |

## What is templated

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project overview, commands, verification steps |
| `.claude/settings.json` | Allowed tools and permissions |
| `.claude/skills/lint-rules/` | Linter command mapping (repo-specific) |

## What stays in each repo

- Domain-specific skills and rules
- Customized CLAUDE.md, settings.json, lint-rules (after initial setup)

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
