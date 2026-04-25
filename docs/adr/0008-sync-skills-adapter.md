# ADR-0008: Skills Adapter Sync via Dedicated `sync-skills.sh`

## Status

Accepted (2026-04-25)

Parent issue: [handbook#68](https://github.com/ozzy-labs/handbook/issues/68)

Related: [handbook ADR-0018](https://github.com/ozzy-labs/handbook/blob/main/adr/0018-agent-adapter-layer.md), [ADR-0006](0006-renovate-auto-sync-preset.md)

## Context

[ADR-0016 (handbook)](https://github.com/ozzy-labs/handbook/blob/main/adr/0016-create-skills-repo.md) で skills SSOT を `ozzy-labs/skills` に分離し、[handbook ADR-0018](https://github.com/ozzy-labs/handbook/blob/main/adr/0018-agent-adapter-layer.md) で adapter 層が導入された。skills repo は次のような per-agent adapter 出力を `dist/{adapter-id}/` に生成する:

- `dist/claude-code/.claude/skills/{name}/` — Claude Code 用
- `dist/codex-cli/.agents/skills/{name}/` + `AGENTS.md.snippet` — Codex CLI 用
- `dist/gemini-cli/.gemini/settings.json` + `AGENTS.md.snippet` — Gemini CLI 用
- `dist/copilot/.github/copilot-instructions.md.snippet` — GitHub Copilot 用

[handbook PR #64](https://github.com/ozzy-labs/handbook/pull/64) で PoC consumer (handbook) を adapter sync に移行する際は、handbook 自身の `.github/workflows/sync-skills.yaml` 内に bash ロジックを直書きしていた。これを 9 consumer に展開するため、共通スクリプトとして commons に抜き出す必要がある。

検討した選択肢:

1. **commons の `sync.sh` を拡張する** — adapter id ごとの分岐を `sync.sh` に追加
2. **専用スクリプト `sync-skills.sh` を新設する** — adapter sync 専用
3. **各 consumer の workflow に bash を直書きしたまま** — 共通化しない

## Decision

### 専用スクリプト `sync-skills.sh` を新設する（選択肢 2）

`sync.sh` と `sync-skills.sh` は責務とデータソースが異なるため、別スクリプトに分ける。

| 観点 | sync.sh | sync-skills.sh |
|------|---------|----------------|
| ソース | ローカルの `dist/`（commons リポ自身） | 別リポ（`ozzy-labs/skills`）の dist |
| 同期モデル | ディレクトリミラー（[ADR-0001](0001-directory-mirror-structure.md)） | per-adapter の細かい変換（per-skill-dir copy + snippet 置換） |
| 呼び出し元 | consumer の `sync-commons.yaml` workflow | consumer の `sync-skills.yaml` workflow |
| 引数 | target repo path | skills dist root path + target repo path |
| Renovate 連携 | `commit:` を bump（[ADR-0006](0006-renovate-auto-sync-preset.md)） | `skills_commit:` を bump（skills repo 側 [skills#23](https://github.com/ozzy-labs/skills/issues/23) で実装） |

これらを 1 スクリプトに統合すると、引数仕様・モード・ファイルレイアウトが二重化して読みづらくなる。分離した方がそれぞれの責務が明確になる。

### opt-in は `.dev-config/sync.yaml` の `skills_adapters:` リストで宣言する

```yaml
commit: <commons SHA>          # sync.sh が管理（ADR-0006）
synced_at: <timestamp>          # sync.sh が管理
skills_commit: <skills SHA>     # Renovate（@ozzylabs/skills preset）が管理
skills_adapters:                # consumer が手動で opt-in
  - claude-code
  - codex-cli
pinned:                         # consumer が手動で管理
  - AGENTS.md
```

- `skills_adapters` 未定義 / 空 → `sync-skills.sh` は no-op で exit 0
- 既存メタデータ（`commit`, `synced_at`, `pinned`）と同居して干渉しない
- adapter id は `{claude-code, codex-cli, gemini-cli, copilot}` のいずれかを許容

### Snippet 対象（AGENTS.md / copilot-instructions.md）はマーカーブロック内のみ置換

`<!-- begin: @ozzylabs/skills -->` と `<!-- end: @ozzylabs/skills -->` のマーカー間だけを snippet 内容で置換する。マーカーが target ファイルに存在しない場合はエラー終了する。consumer は initial setup として手動でマーカーブロックを挿入しておく必要がある（handbook #64 が確立した運用）。

### Skill ディレクトリは per-skill-dir コピー（atomic 置換、consumer-only ディレクトリは保持）

`.claude/skills/` や `.agents/skills/` 配下に consumer 固有のスキルディレクトリを置けるよう、親ディレクトリは削除しない。同期対象の skill ディレクトリ単位で個別ファイルをコピーする。

### pinned セマンティクスを維持

`sync.sh` と同じ `pinned:` リストを参照する。pinned はファイルパス（例: `.claude/skills/commit/SKILL.md`）またはディレクトリ（末尾 `/` を付ける、例: `.claude/skills/commit/`）で指定できる。

## Consequences

### Positive

- 9 consumer の workflow から重複ロジックが消え、commons 1 箇所で `sync-skills.sh` を保守すれば済む
- bats テスト（`tests/sync-skills.bats`）で adapter sync の挙動が CI で守られる
- skills 側の出力フォーマット変更（adapter 追加など）に追従する際も、本スクリプト 1 ファイルの修正で済む
- `sync.sh` の責務（commons の dist ミラー）が純化される
- Renovate（`skills_commit` bump）と consumer workflow（`sync-skills.sh` 実行）の役割分担が明確

### Negative / Trade-offs

- consumer 側に `sync.sh` と `sync-skills.sh` の 2 スクリプトを呼ぶ workflow が共存する（直近は `sync-commons.yaml` と `sync-skills.yaml` の 2 ワークフロー）
- snippet 対象ファイル（AGENTS.md / copilot-instructions.md）に initial setup でマーカーを差し込む手順が必要（pin と同じく consumer 責務）
- `sync-skills.sh` 単体では skills repo を取得しない（呼び出し元の workflow が `actions/checkout` でクローンを用意する前提）

## Alternatives considered

### sync.sh を拡張する（選択肢 1）

`sync.sh` に adapter id 引数を追加し、内部で skills clone も行うパターン。`sync.sh` の引数体系が崩れ、commons の dist ミラーモデル（[ADR-0001](0001-directory-mirror-structure.md)）と adapter sync の per-target ロジックが混在する。読みやすさで劣る。

### 各 consumer の workflow に直書きする（選択肢 3）

handbook#64 で採用した PoC スタイル。9 consumer に展開すると bash ロジックが 9 箇所にコピーされ、skills 側の adapter 仕様変更時に 9 箇所修正が必要になる。共通化の動機がそもそも本 issue。

## References

- [handbook#68](https://github.com/ozzy-labs/handbook/issues/68) — adapter rollout 親 issue
- [handbook#64](https://github.com/ozzy-labs/handbook/pull/64) — PoC consumer の handbook 移行（参考実装）
- [ozzy-labs/skills#23](https://github.com/ozzy-labs/skills/issues/23) — skills 側 `skills-sync.json` の adapter 対応（本 ADR とペア）
- [handbook ADR-0018](https://github.com/ozzy-labs/handbook/blob/main/adr/0018-agent-adapter-layer.md) — adapter layer architecture
- [ADR-0006](0006-renovate-auto-sync-preset.md) — commons 側の Renovate auto-sync preset（同じ思想、別リポ向け）
