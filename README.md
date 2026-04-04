English | [日本語](README.ja.md)

# ai-config

Shared AI agent configurations for OzzyLabs repositories.

## Structure

```text
claude/
  skills/   -> Shared workflow skills
  rules/    -> Shared rules
sync.sh     -> Sync script (claude/ -> .claude/)
```

## Usage

Run the sync script from the target repository:

```bash
/path/to/ai-config/sync.sh /path/to/target-repo
```

All files in `claude/` are copied to `.claude/` in the target repository. Repository-specific files (test, lint-rules, settings.json, CLAUDE.md, etc.) are not affected.

## What is shared

| Type | Files | Purpose |
|------|-------|---------|
| Skills | commit, commit-conventions, drive, implement, lint, pr, review, ship | Workflow orchestration |
| Rules | git-workflow.md | Branch, commit, PR conventions |

## What stays in each repo

- `CLAUDE.md` — Project overview, tech stack, commands, verification steps
- `.claude/settings.json` — Allowed tools and permissions
- `.claude/skills/test/` — Test commands (repo-specific)
- `.claude/skills/lint-rules/` — Linter commands (repo-specific)
- Domain-specific skills and rules

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
