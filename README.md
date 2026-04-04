English | [日本語](README.ja.md)

# dev-config

Shared configurations for OzzyLabs repositories.

## Structure

```text
shared/              -> Synced to every repo (always overwrite)
  .claude/
    skills/          -> Shared workflow skills
    rules/           -> Shared rules
  lefthook-base.yaml -> Shared lefthook base config
  .commitlintrc.yaml -> Shared commitlint config
  .editorconfig      -> Editor settings
  .gitattributes     -> Line ending normalization
  .mdformat.toml     -> Markdown formatter config
  .github/workflows/
    pr-check.yaml    -> PR title & branch name validation
templates/           -> Copied on initial setup only (if not exists)
  CLAUDE.md
  SECURITY.md
  .claude/
    settings.json
    skills/lint-rules/
  .mcp.json
  .yamlfmt.yaml
  .yamllint.yaml
  .markdownlint-cli2.yaml
  .mise.toml
  .gitignore
  renovate.json
  biome.json
  lefthook.yaml
  LICENSE
  CONTRIBUTING.md
  .github/
    pull_request_template.md
    ISSUE_TEMPLATE/
  .vscode/
    settings.json
    extensions.json
sync.sh              -> Sync script
setup-repo.sh        -> GitHub repository setup script
```

## Usage

```bash
# Sync with confirmation
/path/to/dev-config/sync.sh /path/to/target-repo

# Sync without confirmation
/path/to/dev-config/sync.sh --force /path/to/target-repo

# Preview changes without copying
/path/to/dev-config/sync.sh --dry-run /path/to/target-repo

# Check if shared files are in sync (for CI)
/path/to/dev-config/sync.sh --check /path/to/target-repo
```

Shared files are always overwritten. Templates are copied only if the target file does not exist. After sync, a metadata file (`.claude/.dev-config-sync`) is written to the target with the source commit hash and timestamp.

### Repository setup

```bash
# Configure GitHub repository settings
/path/to/dev-config/setup-repo.sh owner/repo

# Preview changes without applying
/path/to/dev-config/setup-repo.sh --dry-run owner/repo
```

Sets merge rules (squash only), branch protection (Rulesets), security settings, and Conventional Commits labels. See [ADR-0004](docs/adr/0004-repo-setup-with-rulesets.md) for design decisions.

## What is shared

| Type | Files | Purpose |
|------|-------|---------|
| Skills | commit, commit-conventions, drive, implement, lint, pr, review, ship, test | Workflow orchestration |
| Rules | git-workflow.md | Branch, commit, PR conventions |
| Config | lefthook-base.yaml | Shared lefthook base (commit-msg + common linters) |
| Config | .commitlintrc.yaml | Conventional Commits validation |
| Config | .editorconfig | Editor settings (charset, indent, line ending) |
| Config | .gitattributes | Line ending normalization, binary detection |
| Config | .mdformat.toml | Markdown formatter config |
| Workflow | .github/workflows/pr-check.yaml | PR title & branch name Conventional Commits validation |

## What is templated

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project overview, commands, verification steps |
| `.claude/settings.json` | Allowed tools and permissions |
| `.claude/skills/lint-rules/` | Linter command mapping (repo-specific) |
| `SECURITY.md` | Security vulnerability reporting policy |
| `.mcp.json` | MCP server configuration (Context7) |
| `.yamlfmt.yaml` | YAML formatter config |
| `.yamllint.yaml` | YAML linter config |
| `.markdownlint-cli2.yaml` | Markdown linter config |
| `.mise.toml` | Tool version management baseline |
| `.gitignore` | Common ignore patterns |
| `renovate.json` | Renovate dependency update config |
| `biome.json` | Biome linter/formatter config |
| `lefthook.yaml` | Lefthook config extending shared base |
| `LICENSE` | MIT License |
| `CONTRIBUTING.md` | Contribution policy |
| `.github/pull_request_template.md` | PR template |
| `.github/ISSUE_TEMPLATE/` | Issue templates (bug report, feature request) |
| `.vscode/settings.json` | VS Code editor settings baseline |
| `.vscode/extensions.json` | VS Code recommended extensions baseline |

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
