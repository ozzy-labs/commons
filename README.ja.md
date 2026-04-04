[English](README.md) | 日本語

# dev-config

OzzyLabs リポジトリ共通の開発設定。

## 構成

```text
shared/          -> 全リポジトリに同期（毎回上書き）
  .claude/
    skills/      -> 共通ワークフロースキル
    rules/       -> 共通ルール
templates/       -> 初期セットアップ用（存在しない場合のみコピー）
  CLAUDE.md
  .claude/
    settings.json
    skills/lint-rules/
sync.sh          -> 同期スクリプト
```

## 使い方

```bash
# 確認付きで同期
/path/to/dev-config/sync.sh /path/to/target-repo

# 確認なしで同期
/path/to/dev-config/sync.sh --force /path/to/target-repo

# コピーせず差分のみ表示
/path/to/dev-config/sync.sh --dry-run /path/to/target-repo
```

共有ファイルは毎回上書きされる。テンプレートは対象ファイルが存在しない場合のみコピーされる。同期後、対象リポジトリの `.claude/.dev-config-sync` にソースのコミットハッシュとタイムスタンプが記録される。

## 共有対象

| 種別 | ファイル | 用途 |
|------|----------|------|
| スキル | commit, commit-conventions, drive, implement, lint, pr, review, ship, test | ワークフロー制御 |
| ルール | git-workflow.md | ブランチ・コミット・PR 規約 |

## テンプレート

| ファイル | 用途 |
|----------|------|
| `CLAUDE.md` | プロジェクト概要、コマンド、検証手順 |
| `.claude/settings.json` | 許可ツール・権限設定 |
| `.claude/skills/lint-rules/` | リンターコマンド対応表（リポジトリ固有） |

## リポジトリ固有のまま残すもの

- ドメイン固有のスキル・ルール
- カスタマイズ済みの CLAUDE.md、settings.json、lint-rules

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
