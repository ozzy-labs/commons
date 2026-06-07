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
setup-repo.sh        -> GitHub repository setup script
init-templates.sh    -> Bootstrap templates with placeholder substitution + repo metadata
```

`templates/` ships starter content that every repo customizes (project name, tech stack, available skills). It is intentionally outside `dist/` so `sync.sh` never touches it — copy these files once when bootstrapping a new repo and edit in place.

Shared skills (`.agents/skills/`, `.claude/skills/`) are no longer distributed from this repo. They live in [`ozzy-labs/skills`](https://github.com/ozzy-labs/skills) and are pulled into consumer repos via the `@ozzylabs/skills` Renovate preset (see [ADR-0016](https://github.com/ozzy-labs/handbook/blob/main/adr/0016-create-skills-repo.md)).

## Quick start: bootstrap a new repo

End-to-end flow for a brand-new ozzy-labs repo. Each script ends with its own "Next steps" hint, so this list is mainly about the order. Detailed flags for each command live in the sections below.

1. **Create the GitHub repo and clone it locally.**

   ```bash
   gh repo create ozzy-labs/<name> --public --description "..."
   gh repo clone ozzy-labs/<name>
   cd <name>
   ```

2. **Apply ozzy-labs GitHub settings** — merge rules (squash only), branch protection, security, Conventional Commits labels.

   ```bash
   /path/to/commons/setup-repo.sh ozzy-labs/<name>
   ```

3. **Sync shared config** — distributes lefthook, mise, editorconfig, workflows, etc., and seeds `.commons/sync.yaml` (including the `skills_commit:` / `skills_adapters:` opt-in stubs).

   ```bash
   /path/to/commons/sync.sh -y .
   ```

4. **Bootstrap templates** — copies `AGENTS.md` / `CLAUDE.md`, substitutes `{{project_name}}` / `{{description}}` placeholders, and applies the repo description + topics via the GitHub API in one shot.

   ```bash
   /path/to/commons/init-templates.sh \
     --name <name> \
     --description "..." \
     --topics ai,cli,multi-agent,... \
     .
   ```

5. **(Optional) Install `@ozzylabs/skills` for local use** — run `npx @ozzylabs/skills install` once on your machine. This places the generic skill bundle under `~/.claude/skills/` (user skills only — no per-repo mirrors). See [ozzy-labs/skills](https://github.com/ozzy-labs/skills) for details. The CI integration uses `ozzy-labs/skills@v1` GitHub Action.

6. **Add project-specific files** (`package.json`, `tsconfig.json`, `src/`, etc.) and edit `AGENTS.md` / `CLAUDE.md` to fill in tech stack and project specifics.

7. **Open the bootstrap PR.** Direct push to `main` is blocked by the ruleset installed in step 2:

   ```bash
   git checkout -b chore/bootstrap
   git add . && git commit -m "chore: bootstrap repo"
   git push -u origin chore/bootstrap
   gh pr create --fill && gh pr merge --squash --delete-branch
   ```

## Usage

```bash
# OzzyLabs Commons CLI
/path/to/commons/commons <command> [args]

# Commands:
#   sync      Sync shared files
#   check     Run health check
#   setup     Initialize repository
#   skills    Sync skills adapters
#   init      Bootstrap templates and metadata
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

Sync metadata lives in the consumer repo at `.commons/sync.yaml`. `sync.sh` reads and writes this single canonical path.

The earlier `.dev-config/sync.yaml` path was supported as a temporary fallback during the migration documented in [ADR-0014](https://github.com/ozzy-labs/handbook/blob/main/adr/0014-rename-dev-config-to-commons.md). All consumers have now completed the rename and the fallback has been removed.

### Skills distribution (user skills only)

Shared skills live in [`ozzy-labs/skills`](https://github.com/ozzy-labs/skills) and are distributed as a single npm package + CLI installer (see [handbook ADR-0027](https://github.com/ozzy-labs/handbook/blob/main/adr/0027-skill-distribution-user-only.md)). End users install the generic skill bundle into `~/.claude/skills/` (or `~/.agents/skills/` for codex-cli) once on their machine:

```bash
npx @ozzylabs/skills install
```

For CI, use the `ozzy-labs/skills@v1` GitHub Action:

```yaml
- uses: ozzy-labs/skills@v1
  with:
    skills: drive,review
    adapter: claude-code
```

The legacy `sync-skills.sh` / `/sync-consumers` flow (Renovate-based per-repo mirror of `dist/{adapter-id}/` into each consumer's `.claude/skills/` / `.agents/skills/`) has been retired — `commons sync.sh` no longer touches the `skills_*` fields. Existing consumers were migrated in [ozzy-labs/skills#100](https://github.com/ozzy-labs/skills/issues/100) by removing project-scoped skill mirrors and dropping `skills_adapters` / `skills_commit` from `.commons/sync.yaml`.

### Repository setup

```bash
# Configure GitHub repository settings
/path/to/commons/setup-repo.sh owner/repo

# Preview changes without applying
/path/to/commons/setup-repo.sh --dry-run owner/repo
```

Sets merge rules (squash only), branch protection (Rulesets), security settings, and Conventional Commits labels. See [ADR-0004](docs/adr/0004-repo-setup-with-rulesets.md) for design decisions.

### Bootstrap templates (`commons init`)

`init-templates.sh` copies `templates/AGENTS.md` and `templates/CLAUDE.md` into a target repo, substitutes `{{project_name}}` and `{{description}}` placeholders, and (when invoked with `--description` or `--topics`) applies the GitHub repo description and topics in one shot. It complements `setup-repo.sh`: that script handles ozzy-labs-wide GitHub settings, while this one handles per-repo bootstrap content.

```bash
# Full bootstrap (file ops + GitHub metadata)
/path/to/commons/init-templates.sh \
  --name agentic-watch \
  --description "Multi-agent CLI that watches blogs..." \
  --topics ai,cli,multi-agent,claude-code,codex,gemini \
  /path/to/agentic-watch

# Files only (no gh API calls)
/path/to/commons/init-templates.sh --name <name> --skip-gh-edit /path/to/repo

# Preview changes
/path/to/commons/init-templates.sh --name <name> --dry-run /path/to/repo
```

`--name` is required. Existing `AGENTS.md` / `CLAUDE.md` files in the target are protected: the script aborts with a diff summary unless `--force` is passed. The repo for `gh api` is auto-detected from the target's `origin` remote, or pass `--repo owner/repo` to override.

### Automated sync (scheduled PR)

Consumer repos get a workflow distributed at `.github/workflows/sync-commons.yaml`. It runs weekly (Monday 00:00 UTC) and on manual dispatch, checks the repo against the latest `commons`, and — if any non-pinned file diverges — runs `sync.sh --yes` and opens a pull request. Review and merge manually; the workflow never auto-merges.

First-time setup for a consumer repo:

1. Run `sync.sh` manually once to pick up `sync-commons.yaml` into `.github/workflows/`
2. The repo settings must allow creating PRs (already the case if `setup-repo.sh` was run)
3. The weekly schedule takes over from the next Monday; `workflow_dispatch` lets you trigger it on demand

### Legacy push-mode sync (removed)

Earlier versions of this repo shipped:

- A `commons-sync.json` Renovate preset (`extends: ["github>ozzy-labs/commons:commons-sync"]`) — removed in [ozzy-labs/skills#80](https://github.com/ozzy-labs/skills/issues/80) Step 4
- A push-mode `/sync-consumers` skill + `commons/scripts/sync-consumers.sh` helper — removed in [ozzy-labs/skills#102](https://github.com/ozzy-labs/skills/issues/102) (epic [#96](https://github.com/ozzy-labs/skills/issues/96))

Both have been retired. Skills are now distributed via the npm package + CLI installer (`npx @ozzylabs/skills install`), and the consumer-side `sync-commons.yaml` workflow above remains the canonical path for shared config files. See [handbook ADR-0027](https://github.com/ozzy-labs/handbook/blob/main/adr/0027-skill-distribution-user-only.md) for the rationale.

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
