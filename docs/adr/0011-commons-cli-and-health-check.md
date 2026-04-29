# ADR-0011: Commons CLI Wrapper and Health Check Command

## Status

Accepted (2026-04-29)

## Context

これまで `commons` は `sync.sh`, `sync-skills.sh`, `setup-repo.sh` という複数の独立したスクリプトを提供してきた。利用者はそれぞれのパスと引数を個別に把握する必要があり、また「現在のリポジトリが正しく設定されているか」を確認する総合的な手段が不足していた。

## Decision

統合的なエントリポイントとなる `commons` CLI ラッパーと、規約適合度を診断する `check` コマンドを導入する。

### 仕様

1. **`commons` スクリプト**:
    - サブコマンド（`sync`, `check`, `setup`, `skills`）を受け取り、対応する既存スクリプトを実行する。
    - 将来的な拡張のベースラインとする。
2. **`check` コマンド (`check.sh`)**:
    - ターゲットリポジトリに対して以下の診断を行う:
        - **Sync Status**: `sync.sh --check` を実行し、共有ファイルが最新か確認する。
        - **Mandatory Files**: `LICENSE`, `AGENTS.md`, `README.md` 等の必須ファイルの存在を確認する。
        - **Markers**: Markdown や YAML において、部分同期に必要なマーカーブロックが存在するか確認する。
        - **Security**: Lefthook および Gitleaks が正しく構成されているか確認する。

## Consequences

### Easier

- 利用者は単一の `commons` コマンドを覚えるだけで、すべての機能にアクセスできる。
- `commons check` により、リポジトリの「健全性」を客観的に把握できるようになり、設定漏れを防止できる。

### Harder

- 各スクリプトを単体で呼び出す従来のワークフローからの移行が必要（後方互換性のため各スクリプトは維持する）。
