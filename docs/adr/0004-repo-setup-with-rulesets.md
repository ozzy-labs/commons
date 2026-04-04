# ADR-0004: Repository Setup with Rulesets

## Status

Accepted (2026-04-05)

## Context

OzzyLabs の全リポジトリで GitHub のマージ設定・ブランチ保護・セキュリティ設定を統一する必要がある。現状は手動設定のため、リポジトリ間で設定が不揃いになるリスクがある。

ブランチ保護の手段として 2 つの選択肢がある:

1. **Branch Protection Rules（レガシー）** — 広く使われているが、Free プランの private リポジトリでは使用不可
2. **Rulesets** — GitHub 推奨（2023〜GA）。Free プランの private リポジトリでも使用可能

## Decision

### Rulesets を採用する

- Free プランの private リポジトリでも使えるため、プランに依存しない
- Organization レベルでの一括管理にも将来対応可能
- `gh ruleset list/view` で CLI から確認でき、運用しやすい

### PR 承認数は 0 にする

- PR 作成を必須にし、squash merge 運用を強制する
- ソロ開発者が自分の PR をマージできないことを防ぐ
- チーム拡大時に 1 以上に引き上げればよい

### bypass は禁止する

- git-workflow ルールで force push や main への直接 push を例外なく禁止している
- admin にバイパスを許可するとルールと矛盾する
- 緊急時でも PR 経由の運用を徹底する

### CI ステータスチェックは含めない

- CI ワークフロー名がリポジトリごとに異なる（`ci`, `lint`, `build` 等）
- 汎用スクリプトに含めると、CI がないリポジトリで使えない
- 各リポジトリで Rulesets に後から手動追加する運用とする

## Consequences

### Easier

- 新規リポジトリ作成時に `setup-repo.sh` を実行するだけで、git-workflow ルールが GitHub 側でも強制される
- マージ設定・セキュリティ設定の漏れがなくなる
- `gh` CLI のみで完結し、外部ツール不要

### Harder

- Rulesets の `POST` は冪等でない。再実行時に同名 Rulesets が重複作成されるため、既存チェックが必要
- CI ステータスチェックは各リポジトリで個別設定が必要
