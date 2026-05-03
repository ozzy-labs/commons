# ADR-0012: Pin .github/workflows/\* in Consumers Instead of Distributing via Sync

## Status

Accepted (2026-05-03)

Supersedes the previously proposed App-token approach (see PR #94, reverted in this same change).

## Context

`Sync commons` workflow が downstream リポで `.github/workflows/*.yaml` の差分を含む PR を push しようとしたとき、デフォルトの `GITHUB_TOKEN` には `workflows` permission が無く、`refusing to allow a GitHub App to create or update workflow ... without workflows permission` エラーで連続失敗していた（observed on `ozzy-labs/skills`、Issue #93）。

最初の対応として PR #94 で専用 GitHub App を発行し `actions/create-github-app-token@v1` 経由で workflows scope を持つトークンに切り替える案を merge した。しかしこの方式は次のコストを伴う:

- org admin による GitHub App の作成・install・private key の rotate 運用
- `SYNC_APP_ID` / `SYNC_APP_PRIVATE_KEY` の org-level secrets 配布
- 全 downstream リポ（`skills`, `create-agentic-aws`, `gh-tasks`, `handbook` 等）への install 設定

ozzy-labs は個人 org 規模で、workflow ファイルの更新は年に数回のペースに留まる見込みであり、上記コストはペイしないと判断した。

## Decision

`.github/workflows/*.yaml` を **commons の自動同期対象から除外**する。具体的には:

1. **commons 自身**: `.commons/sync.yaml` の `pinned` に `.github/workflows/sync-commons.yaml` と `.github/workflows/pr-check.yaml` を追加する。
2. **downstream consumers**: 各 downstream リポでも同様に `.commons/sync.yaml` の `pinned` に上記2ファイルを追加する。`setup-repo.sh` の初期セットアップ時はコピーされるため、その後の自動同期から除外することで `GITHUB_TOKEN` で push できる差分のみが PR 化される。
3. **workflow の更新**: commons 側で workflow を改善した際は、各 consumer の管理者が手動で差分を取り込む（`cp dist/.github/workflows/*.yaml /path/to/consumer/.github/workflows/` 等）。

## Consequences

### Easier

- GitHub App / PAT / org secrets の運用が不要。token rotate の心配なし。
- すべての downstream リポは GitHub Actions のデフォルト `GITHUB_TOKEN` のみで運用できる。
- secrets 漏洩の attack surface を増やさない。

### Harder

- workflow の改善が各 consumer に自動伝搬しない。commons 側で改善 PR を merge した後、各 consumer で人手で取り込む手間が発生する。
- consumer 側で workflow が古いまま放置されるリスクがある（初回 setup 後にメンテされない）。`commons check` 等で workflow の drift を検出する補助機能を将来検討する余地あり。
