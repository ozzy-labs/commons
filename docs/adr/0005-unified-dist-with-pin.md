# ADR-0005: Unified dist/ Directory with Pin Mechanism

## Status

Accepted (2026-04-05)

Supersedes: ADR-0002, ADR-0003

## Context

従来は `shared/`（毎回上書き）と `templates/`（存在しない場合のみコピー）の2ディレクトリで同期ポリシーを分けていた。しかし、devcontainer のように「基本は同期したいが、リポジトリ側で意図的に乖離する可能性があるファイル」を扱うには、この二択では不十分だった。

検討した選択肢:

1. **3ディレクトリ方式** — `shared/` + `templates/` + `managed/` にポリシーを3分割
2. **マニフェスト方式** — 単一ディレクトリ + YAML でファイルごとにポリシーを宣言
3. **統合方式** — 単一ディレクトリ、全ファイル同一ポリシー、ターゲット側で pin により乖離を宣言

## Decision

### 統合方式を採用する

`shared/` と `templates/` を廃止し、`dist/` に統合する。全ファイルに同一の同期ポリシーを適用する。

### 同期ポリシー

| ファイル状態 | 対話モード | `-y` / `--yes` | `--check`（CI） | `--dry-run` |
|---|---|---|---|---|
| 未存在 | コピー | コピー | exit 1 | 表示 |
| 同一 | スキップ | スキップ | OK | 表示 |
| 差分あり | 差分表示→選択 | 上書き | exit 1 | 表示 |
| 差分あり (pinned) | スキップ | スキップ | OK | 表示 |

### pin 機構

ターゲットリポジトリ側で意図的な乖離を宣言する仕組み:

- 対話モードで差分のあるファイルについて選択: `[y/N/pin/all]`
- pinned ファイルは全モードでスキップ（意図的な乖離を尊重）
- 設定: 対話モードで `pin` を選択、または `sync.yaml` を手動編集
- 解除: `sync.yaml` から該当行を削除

### メタデータの配置

同期メタデータは `.dev-config/sync.yaml` に記録する（旧 `.claude/.dev-config-sync`）。dev-config の同期メタデータは Claude 固有の設定ではないため、独立したディレクトリに配置する。

```yaml
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
  - .claude/settings.json
```

## Consequences

### Easier

- ディレクトリ構成が単純（`dist/` のみ）
- ファイル追加時に shared/templates の判断が不要
- 全ファイルの差分を確認してから同期できる（従来の shared は無条件上書き）
- pin によりリポジトリ固有のカスタマイズを明示的に管理できる

### Harder

- 従来の shared ファイル（毎回自動上書き）も対話モードでは確認が必要になる（`-y` で従来の挙動）
- pin の管理が必要（どのファイルを pin したか把握する必要がある）
- 既存リポジトリのメタデータ移行が必要（`.claude/.dev-config-sync` → `.dev-config/sync.yaml`）
