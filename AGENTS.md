# AGENTS.md

このファイルは AI エージェント向けの共通 instructions です。

## 基本方針

- 日本語で応答する
- 推奨案とその理由を提示する
- `.env` ファイルは読み取り・ステージングしない
- 破壊的な Git 操作を避ける

## プロジェクト概要

`commons`: OzzyLabs リポジトリ共通の開発設定を管理・配布するリポジトリ。

## Tech Stack

- Shell: Bash (sync.sh, setup-repo.sh)
- Testing: bats-core
- Version management: mise (`.mise.toml`)
- Git hooks: Lefthook
- Linting: markdownlint-cli2, yamlfmt, yamllint, shellcheck, shfmt, gitleaks, trivy

## プロジェクト構成

- `dist/` — 全リポジトリに配布するファイル群
- `dist/.agents/skills/` — 共有スキル（agentskills.io 準拠、SSOT）
- `dist/.claude/skills/` — Claude Code スキルオーバーレイ
- `tests/` — bats テスト
- `sync.sh` — 配布ファイルの同期スクリプト
- `setup-repo.sh` — GitHub リポジトリ初期設定スクリプト
- `docs/adr/` — Architecture Decision Records

## 主要コマンド

```bash
bats tests/               # 全テスト実行
sync.sh <target-repo>     # ファイル同期（対話モード）
sync.sh -y <target-repo>  # ファイル同期（自動モード）
sync.sh --check <target>  # 同期状態チェック（CI 用）
setup-repo.sh owner/repo  # GitHub リポジトリ設定
```

## 検証（必須）

コード変更後、報告前に以下を通すこと:

1. `bats tests/` — 全テスト通過

## 編集ルール

- スキル・ルールは**全リポジトリ共通**であることを意識する
- リポジトリ固有のコマンド・パス・URL を直書きしない（CLAUDE.md や lint-rules を参照させる）
- `dist/` 内のファイルは全て同期対象になる（対話モードでは差分確認あり、`-y`/`--yes` で上書き）
- ターゲットリポジトリで pin されたファイルは同期時にスキップされる

## コーディング規約

- インデント: 2 スペース
- 改行コード: LF
- ファイル末尾: 改行あり

## 規約

言語・コミット・ブランチ・PR のルールは README.md を参照すること。

## Adapter Files

| Agent | Configuration |
|-------|---------------|
| Claude Code | `CLAUDE.md`, `.claude/` |
| Gemini CLI | `.gemini/settings.json` → `AGENTS.md` |
| Codex CLI | `AGENTS.md` + `.agents/skills/` |
| GitHub Copilot | `AGENTS.md` + `.agents/skills/` |
