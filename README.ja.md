[English](README.md) | 日本語

# dev-config

OzzyLabs リポジトリ共通の開発設定。

## 構成

```text
dist/                -> 全リポジトリに配布
  .claude/
    skills/          -> ワークフロースキル
    rules/           -> ルール
    settings.json    -> 許可ツール・権限設定
  .devcontainer/     -> devcontainer 設定
  .github/
    workflows/       -> PR タイトル・ブランチ名検証
    ISSUE_TEMPLATE/  -> Issue テンプレート
    pull_request_template.md
  .vscode/           -> VS Code 設定・推奨拡張
  lefthook-base.yaml -> 共通 lefthook ベース設定
  lefthook.yaml      -> 共通ベースを参照する lefthook 設定
  .commitlintrc.yaml -> 共通 commitlint 設定
  .editorconfig      -> エディタ共通設定
  .gitattributes     -> 改行コード正規化
  .mdformat.toml     -> Markdown フォーマッター設定
  .mise.toml         -> ツールバージョン管理
  CLAUDE.md          -> プロジェクト概要の雛形
  ...
sync.sh              -> 同期スクリプト
setup-repo.sh        -> GitHub リポジトリ初期設定スクリプト
```

## 使い方

```bash
# 対話的に同期（差分のあるファイルは確認あり）
/path/to/dev-config/sync.sh /path/to/target-repo

# 確認なしで同期（pinned 以外の差分ファイルを全て上書き）
/path/to/dev-config/sync.sh -y /path/to/target-repo

# コピーせず差分のみ表示
/path/to/dev-config/sync.sh --dry-run /path/to/target-repo

# 同期状態をチェック（CI 用、差分があれば exit 1）
/path/to/dev-config/sync.sh --check /path/to/target-repo
```

全ファイルに同一の同期ポリシーを適用する。対話モードでは差分のあるファイルについて更新・スキップ・pin（永続スキップ）・全て更新を選択できる。pinned ファイルは `-y` を含む全モードでスキップされる。同期後、対象リポジトリの `.dev-config/sync.yaml` にメタデータが記録される。

### Pin

ターゲットリポジトリで意図的にカスタマイズしたファイルを **pin** すると、以降の同期で上書きされなくなる。対話的同期時に `pin` を選択するか、`.dev-config/sync.yaml` を直接編集する。

### リポジトリ初期設定

```bash
# GitHub リポジトリの設定を自動化
/path/to/dev-config/setup-repo.sh owner/repo

# 変更内容をプレビュー
/path/to/dev-config/setup-repo.sh --dry-run owner/repo
```

マージルール（squash のみ）、ブランチ保護（Rulesets）、セキュリティ設定、Conventional Commits ラベルを設定する。設計方針は [ADR-0004](docs/adr/0004-repo-setup-with-rulesets.md) を参照。

## リポジトリ固有のまま残すもの

- ドメイン固有のスキル・ルール
- カスタマイズ済みのファイル（pin して上書きを防止）

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
