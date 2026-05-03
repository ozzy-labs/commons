# ADR-0012: GitHub App Token for sync-commons Workflow

## Status

Accepted (2026-05-03)

Resolves: [commons#93](https://github.com/ozzy-labs/commons/issues/93)

## Context

各 consumer リポは `dist/.github/workflows/sync-commons.yaml` で配布される `Sync commons` workflow を使い、`peter-evans/create-pull-request@v7` で `chore/sync-commons` ブランチに sync 結果を push して PR を作成する。

同 workflow は default の `${{ secrets.GITHUB_TOKEN }}` で push しているが、Actions が発行する `GITHUB_TOKEN` には **`workflows` permission が無い**ため、`.github/workflows/*.yaml` を含む差分が含まれた瞬間に以下のエラーで push が拒否される:

```text
! [remote rejected] chore/sync-commons -> chore/sync-commons (refusing to allow a GitHub App to create or update workflow `.github/workflows/pr-check.yaml` without `workflows` permission)
```

`dist/.github/workflows/sync-commons.yaml` 自身も `dist/.github/workflows/pr-check.yaml` も commons から downstream へ sync 配布されるファイルなので、commons 側で workflow が更新されるたびに必ず sync 対象に入り、構造的にこの障害が再発する。実際に `ozzy-labs/skills` で 4/27 schedule 実行と 5/3 manual dispatch ×3 が同じ理由で連続失敗した。

## Decision

`Sync commons` workflow は、専用 GitHub App から発行されるインストールトークンで push する。

### 具体仕様

1. org に `ozzy-labs-sync-bot`（仮称）GitHub App を 1 つ作成する。Repository permissions: `Contents: Write`, `Pull requests: Write`, `Workflows: Write`。downstream リポ全部にインストールする。
2. App ID と Private Key を **org-level secrets** として登録する: `SYNC_APP_ID`, `SYNC_APP_PRIVATE_KEY`。
3. `dist/.github/workflows/sync-commons.yaml` で `actions/create-github-app-token@v1` を最初の step として実行し、後続の `actions/checkout@v4`（自リポ側）と `peter-evans/create-pull-request@v7` の `token:` に同 App token を渡す。

`actions/checkout@v4` のうち `repository: ozzy-labs/commons` を取るステップは public repo を fetch するだけなので App token は不要。

## Alternatives considered

- **fine-grained PAT**: `SYNC_TOKEN` として個人 PAT を登録。手軽だが個人 token なので有効期限管理が必要で、PAT を持つ個人が org を離脱すると downstream 全部が一斉に壊れる。GitHub App はインストール単位で permission が独立しており、個人と切り離せる。
- **`pinned` で `.github/workflows/` 配下を sync 対象から除外する**: 暫定で sync を止められるが、commons 側の workflow 改善（例: pr-check, ci のアップデート）が downstream に永久に伝搬しなくなる。回避策ではなく機能停止に近い。
- **GITHUB_TOKEN に workflows permission を付与する**: 不可。GitHub の仕様上、`GITHUB_TOKEN` に `workflows` scope は付与できない。

## Consequences

### Easier

- `dist/.github/workflows/*` を含む sync が確実に成功するようになり、downstream の workflow 更新ラグが解消する。
- App token は installation 単位で短命（通常 1 時間）かつ App permission に縛られるため、PAT より漏洩リスクが小さい。

### Harder

- 新規 consumer リポを追加するたびに、GitHub App のインストール対象に含める必要がある（org-wide install で運用すれば一度きり）。
- 初回 roll-out では App 作成と secrets 登録という org-admin 権限の作業が必要。
- secrets が未登録のリポでは `actions/create-github-app-token@v1` step が即失敗する。これは fail-fast のメリットでもあるが、初期化漏れを setup-repo.sh で検出する追跡 issue を別途切る価値がある。

## References

- [commons#93](https://github.com/ozzy-labs/commons/issues/93) — 障害報告と修正方針
- [GitHub Actions GITHUB_TOKEN automatic authentication](https://docs.github.com/en/actions/security-guides/automatic-token-authentication)
- [actions/create-github-app-token](https://github.com/actions/create-github-app-token)
- [peter-evans/create-pull-request — push using a GitHub App](https://github.com/peter-evans/create-pull-request/blob/main/docs/concepts-guidelines.md#authenticating-with-github-app-generated-tokens)
