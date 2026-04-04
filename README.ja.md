[English](README.md) | 日本語

# ai-config

OzzyLabs リポジトリ共通の AI エージェント設定。

## 構成

```text
claude/
  skills/   -> 共通ワークフロースキル
  rules/    -> 共通ルール
sync.sh     -> 同期スクリプト（claude/ -> .claude/）
```

## 使い方

対象リポジトリから同期スクリプトを実行する:

```bash
/path/to/ai-config/sync.sh /path/to/target-repo
```

`claude/` 内の全ファイルが対象リポジトリの `.claude/` にコピーされる。リポジトリ固有のファイル（test, lint-rules, settings.json, CLAUDE.md 等）には影響しない。

## 共有対象

| 種別 | ファイル | 用途 |
|------|----------|------|
| スキル | commit, commit-conventions, drive, implement, lint, pr, review, ship | ワークフロー制御 |
| ルール | git-workflow.md | ブランチ・コミット・PR 規約 |

## リポジトリ固有のまま残すもの

- `CLAUDE.md` — プロジェクト概要、技術スタック、コマンド、検証手順
- `.claude/settings.json` — 許可ツール・権限設定
- `.claude/skills/test/` — テストコマンド（リポジトリ固有）
- `.claude/skills/lint-rules/` — リンターコマンド（リポジトリ固有）
- ドメイン固有のスキル・ルール

## 言語

- デフォルト: 日本語
- 公開ファイル（README など）: 英語版と日本語版を用意
- コミットメッセージ: 英語
- PR タイトル: 英語
- PR 説明: 日本語

## コミット

[Conventional Commits](https://www.conventionalcommits.org/): `<type>[optional scope]: <description>`

Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore

## ブランチ

[GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow): `main` + feature branches（直接 push 不可）

命名: `<type>/<short-description>`

## Pull Request (PR)

タイトル: Conventional Commits 形式

マージ: squash merge のみ、マージ後にブランチを削除
