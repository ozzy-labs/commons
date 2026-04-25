# ADR-0006: Renovate Auto-Sync Preset for Consumer Repos

## Status

Accepted (2026-04-25)

Relates to: [handbook ADR-0002](https://github.com/ozzy-labs/handbook/blob/main/adr/0002-skills-distribution-via-renovate.md) (skills distribution via Renovate)

Parent issue: [handbook#18](https://github.com/ozzy-labs/handbook/issues/18)

## Context

[ADR-0005](./0005-unified-dist-with-pin.md) で `dist/` を `sync.sh` で全リポへ配布する方式が確立している。現在は各消費リポの `.github/workflows/sync-commons.yaml` が週次（月曜 UTC 00:00）で `sync.sh --check` → 差分があれば `sync.sh --yes` → PR 作成を行う。

handbook ADR-0002 は「共通 skill / 設定は Renovate 自動同期で配布する」ことを決定した。動機:

- 週次 schedule では更新反映までに最大 1 週間のラグがある
- schedule 起動は手動 dispatch 以外に「いつ来るか分からない」
- Renovate の方が事実上のデファクト（依存更新は他も Renovate 管理）であり、同じメンタルモデルに統合できる

ただし Renovate の built-in manager は「sibling repo から sync.sh でファイルをコピーする」モデルを直接サポートしない。`postUpgradeTasks` は Mend Renovate GitHub App では使えない（self-hosted 限定）。したがって Renovate 単体では物理的なファイルコピーはできない。

## Decision

**Renovate を commons の更新検知器として使い、物理コピーは consumer 側の workflow に委譲する。**

commons 側のスコープ（この ADR）:

1. 消費リポが `extends` で参照できる preset を `ozzy-labs/commons` に commit する
2. preset は customManager で `.dev-config/sync.yaml` の `commit:` フィールドを監視する
3. datasource は `git-refs` を使い、`https://github.com/ozzy-labs/commons` の `main` ブランチ HEAD を追跡する
4. Renovate は新しい SHA を検知したら `commit:` だけを書き換えた PR を consumer に送る

### 具体ファイル

- `commons-sync.json` — preset 本体（リポ直下）
  - consumer は `{ "extends": ["github>ozzy-labs/commons:commons-sync"] }` で参照
- `sync.sh` — `commit:` を full 40 文字 SHA で書き込むよう変更
  - Renovate `git-refs` datasource は full SHA を返すため、short SHA だと毎 sync で format 往復が発生する

### Pinned との衝突回避

- Renovate が書き換えるのは `commit:` のみ。`pinned:` リストは正規表現の match 対象外で無改変に保たれる
- 実 sync を担う workflow（consumer 側）が `sync.sh --yes` を実行する際、sync.sh は `.dev-config/sync.yaml` を読み直して `pinned` をそのまま引き継いで再書き込みするため、pinned セマンティクスは保たれる

### スコープ外（別 sub-issue）

- 消費リポへの実際の roll-out は [handbook#42](https://github.com/ozzy-labs/handbook/issues/42) で 1 リポ opt-in 試験
- Renovate PR を受けて `sync.sh --yes` を走らせる workflow の consumer 向け配布は roll-out フェーズで整備する

## Alternatives considered

- **`github-tags` / `github-releases` datasource** — commons は tag / release を運用していない。採用するなら運用設計が先行する
- **`postUpgradeTasks` で sync.sh を実行する** — Mend Renovate GitHub App で使えない。self-hosted 移行は別議論
- **`.dev-config/sync.yaml` ではなく別の marker ファイル（例: `.dev-config/commons.version`）** — ファイル数が増え、sync.sh / metadata 既存ロジックとの整合も増える。commit: フィールドは既に "currently synced version" を表現しているので流用が自然
- **scheduled workflow を廃止して Renovate に一本化** — 初期は併存。opt-in で 1 リポ試験、問題がなければ後続 ADR で整理

## Consequences

### Positive

- commons の更新反映ラグが「最大 1 週間」→ 「Renovate の schedule 粒度（デフォルト 1 時間程度）」に短縮可能
- 既存の `.dev-config/sync.yaml` / `sync.sh` / `pinned` 設計を変えずに乗せられる
- preset として配布されるため、consumer の renovate.json への追加は 1 行

### Negative / Trade-offs

- `git-refs` が `main` ブランチ全コミットを追跡するため、`dist/` 非タッチのコミットでも PR が飛ぶ。consumer の sync workflow が空差分を no-op として扱う必要がある（handbook#42 で対応）
- preset だけでは機能しない（consumer の workflow 整備が必要）。ドキュメントで明示する
- short SHA → full SHA への format 移行が必要。既存 consumer の `.dev-config/sync.yaml` は次回 `sync.sh` 実行時に自動で full SHA に書き換わる

## References

- [handbook ADR-0002](https://github.com/ozzy-labs/handbook/blob/main/adr/0002-skills-distribution-via-renovate.md) — skills distribution via Renovate
- [handbook#18](https://github.com/ozzy-labs/handbook/issues/18) — Renovate auto-sync PoC（parent issue）
- [handbook#42](https://github.com/ozzy-labs/handbook/issues/42) — 1 リポ opt-in 試験（sibling sub-issue）
- [ADR-0005](./0005-unified-dist-with-pin.md) — `dist/` + pin による同期設計
- [Renovate customManagers docs](https://docs.renovatebot.com/modules/manager/regex/)
- [Renovate git-refs datasource docs](https://docs.renovatebot.com/modules/datasource/git-refs/)
