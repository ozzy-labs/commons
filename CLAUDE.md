# CLAUDE.md

共通方針は AGENTS.md を参照。以下は Claude Code 固有の設定。

## 基本ルール

- ユーザーへの確認には `AskUserQuestion` を使用する

## Skills の共通ルール

- スキル完了時のネクストアクション提案には `AskUserQuestion` を使用する
- ネクストアクションはユーザーの確認なく実行しない
