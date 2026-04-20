# ADR-0002: Separate Shared Files and Templates

## Status

Superseded by [ADR-0005](0005-unified-dist-with-pin.md) (2026-04-05)

## Context

commons が配布するファイルには2種類ある:

- **共有ファイル**: 全リポジトリで同一であるべき（ワークフロースキル、ルール）
- **テンプレート**: 初期セットアップ用の雛形（CLAUDE.md、settings.json、lint-rules）

これらの配布方法を決める必要がある。

選択肢:

1. **単一ディレクトリ** — 全ファイルを1つのディレクトリに配置し、ファイルごとに上書き/スキップを判定
2. **ディレクトリ分離** — `shared/`（毎回上書き）と `templates/`（存在しない場合のみコピー）に分離

## Decision

`shared/` と `templates/` にディレクトリで分離する。

## Consequences

### Easier

- ファイルの性質（共有 vs テンプレート）がディレクトリから自明
- sync.sh の動作がシンプル（ディレクトリごとに異なるコピー戦略）
- 新しいファイル追加時に適切なディレクトリに置くだけ

### Harder

- 同じ `.claude/` 配下のファイルが `shared/` と `templates/` に分かれる（skills/commit は shared、skills/lint-rules は templates）
