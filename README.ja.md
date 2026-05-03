[English](README.md) | 日本語

# commons

OzzyLabs リポジトリ共通の開発設定。

## 構成

```text
dist/                -> 全リポジトリに配布
  .claude/
    rules/           -> ルール
    settings.json    -> 許可ツール・権限設定
  .devcontainer/     -> devcontainer 設定
  .gemini/
    settings.json    -> Gemini CLI 設定（AGENTS.md を読み込む）
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
  trivy.yaml         -> Trivy セキュリティスキャナー設定
  ...
templates/           -> scaffold 専用ファイル（新規リポ作成時に手動でコピー、sync の対象外）
  AGENTS.md          -> AI エージェント共通 instructions の雛形
  CLAUDE.md          -> Claude Code 固有設定
sync.sh              -> 同期スクリプト
sync-skills.sh       -> @ozzylabs/skills adapter 同期スクリプト（consumer ごとに opt-in）
setup-repo.sh        -> GitHub リポジトリ初期設定スクリプト
```

`templates/` には各リポでカスタマイズ前提の雛形（プロジェクト概要・tech stack・利用スキル等）を置く。`sync.sh` の対象外なので、新規リポ初期化時に一度だけ手動コピーしてその後はリポ側で編集する。

共有スキル（`.agents/skills/`、`.claude/skills/`）は本リポからの配布対象外。SSOT は [`ozzy-labs/skills`](https://github.com/ozzy-labs/skills) に置き、各 consumer リポは `@ozzylabs/skills` の Renovate preset 経由で取り込む（[ADR-0016](https://github.com/ozzy-labs/handbook/blob/main/adr/0016-create-skills-repo.md)）。

## 使い方

```bash
# OzzyLabs Commons CLI
/path/to/commons/commons <command> [args]

# コマンド一覧:
#   sync      共有ファイルの同期
#   check     規約適合度診断
#   setup     リポジトリ初期設定
#   skills    スキル・アダプター同期
```

### 同期 (Sync)

```bash
# 対話的に同期（差分のあるファイルは確認あり）
commons sync /path/to/target-repo

# 確認なしで同期（pinned 以外の差分ファイルを全て上書き）
commons sync -y /path/to/target-repo

# コピーせず差分のみ表示
commons sync --dry-run /path/to/target-repo

# 同期状態をチェック（CI 用、差分があれば exit 1）
commons sync --check /path/to/target-repo
```

全ファイルに同一の同期ポリシーを適用する。対話モードでは差分のあるファイルについて更新 (`y`)、マージ (`m`)、スキップ (`N`)、pin（永続スキップ）、全て更新 (`all`) を選択できる。pinned ファイルは `-y` を含む全モードでスキップされる。同期後、対象リポジトリの `.commons/sync.yaml` にメタデータが記録される。

### 規約適合度診断 (Check)

```bash
# リポジトリが OzzyLabs の規約に適合しているか総合的に診断
commons check /path/to/target-repo
```

診断項目:

- 全ての共有ファイルが同期（または pin）されているか
- 必須ファイル（`LICENSE`, `AGENTS.md` 等）が存在するか
- Markdown や YAML に必要なマーカーブロックが含まれているか
- セキュリティ設定（Lefthook, Gitleaks）が有効か

### Pin

ターゲットリポジトリで意図的にカスタマイズしたファイルを **pin** すると、以降の同期で上書きされなくなる。対話的同期時に `pin` を選択するか、`.commons/sync.yaml` を直接編集する。

### メタデータパス

同期メタデータは consumer リポ内の `.commons/sync.yaml` に置く。`sync.sh` はこの単一の canonical パスを読み書きし、Renovate preset（`commons-sync.json` の `managerFilePatterns`）も同じパスを追跡して `commit:` フィールドを更新する。

過去のレガシーパス `.dev-config/sync.yaml` は [ADR-0014](https://github.com/ozzy-labs/handbook/blob/main/adr/0014-rename-dev-config-to-commons.md) で定義された移行期間中のみフォールバックとしてサポートされていた。全 consumer の rename 完了に伴いフォールバックは撤去済み。

### Skills 同期（consumer ごとに opt-in）

共有スキルは [`ozzy-labs/skills`](https://github.com/ozzy-labs/skills) に置かれ、エージェント別 adapter 出力として `dist/{adapter-id}/` 配下に生成される。consumer は `.commons/sync.yaml` に adapter id を列挙して opt-in する:

```yaml
# Renovate が @ozzylabs/skills preset 経由で更新
skills_commit: <40-char-sha>

# Consumer が手動で opt-in 設定
skills_adapters:
  - claude-code   # → .claude/skills/{name}/
  - codex-cli     # → .agents/skills/{name}/ + AGENTS.md snippet
  - gemini-cli    # → .gemini/settings.json + AGENTS.md snippet
  - copilot       # → .github/copilot-instructions.md snippet
```

Consumer の sync workflow が `skills_commit:` の SHA で `ozzy-labs/skills` をクローンし、`sync-skills.sh` で opt-in した adapter 出力を反映する:

```bash
# 確認なしで同期（workflow 用途）
/path/to/commons/sync-skills.sh -y /path/to/skills/dist /path/to/target-repo

# プレビューのみ
/path/to/commons/sync-skills.sh --dry-run /path/to/skills/dist /path/to/target-repo

# 同期状態をチェック（CI 用、差分があれば exit 1）
/path/to/commons/sync-skills.sh --check /path/to/skills/dist /path/to/target-repo
```

Snippet 対象（`AGENTS.md` / `.github/copilot-instructions.md`）は対象ファイルにマーカーブロックが既に存在している必要がある。`<!-- begin: @ozzylabs/skills -->` と `<!-- end: @ozzylabs/skills -->` の間だけが置換され、その他のセクションは保持される。メタデータファイルの `pinned:` リストにパスを追加する（ディレクトリ全体は末尾に `/` を付ける）と、全 adapter で当該パスをスキップする。`.claude/skills/` や `.agents/skills/` 配下に consumer 固有のスキルディレクトリを置いても削除されない。

### リポジトリ初期設定

```bash
# GitHub リポジトリの設定を自動化
/path/to/commons/setup-repo.sh owner/repo

# 変更内容をプレビュー
/path/to/commons/setup-repo.sh --dry-run owner/repo
```

マージルール（squash のみ）、ブランチ保護（Rulesets）、セキュリティ設定、Conventional Commits ラベルを設定する。設計方針は [ADR-0004](docs/adr/0004-repo-setup-with-rulesets.md) を参照。

### 自動同期（定期 PR）

各消費リポには `.github/workflows/sync-commons.yaml` が配布される。このワークフローは毎週（月曜 UTC 00:00）と手動起動で動作し、最新の `commons` と比較して差分があれば `sync.sh --yes` を実行し、プルリクエストを作成する。自動マージはせず、必ずレビューしてマージする。

消費リポ側の初回セットアップ手順:

1. 手動で一度 `sync.sh` を実行し、`sync-commons.yaml` を `.github/workflows/` に取り込む
2. リポ設定で PR 作成が許可されていること（`setup-repo.sh` 実行済みなら OK）
3. 翌週から scheduled で自動起動。`workflow_dispatch` で即時実行も可能

### Renovate 経由の自動同期（opt-in）

週次 schedule の代替として、consumer リポは `commons-sync` Renovate preset を `extends` することで低レイテンシな更新検知に切り替えられる。Renovate は commons の `main` ブランチ HEAD を追跡し、新しい commit が来ると `.commons/sync.yaml` の `commit:` フィールドを書き換える PR を consumer に送る。実ファイルの反映は consumer 側の workflow が `sync.sh --yes` を Renovate PR ブランチ上で実行する役割。

Consumer の `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>ozzy-labs/commons:commons-sync"]
}
```

設計の詳細は [ADR-0006](docs/adr/0006-renovate-auto-sync-preset.md) を参照。consumer 側の workflow 整備は Renovate PoC の roll-out（handbook#18 / handbook#42）で対応予定。それまでは scheduled workflow が推奨パス。

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
