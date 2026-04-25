# 設計方針

## リポジトリの責務

`commons` は、OzzyLabs の全リポジトリに共通する開発設定を一元管理し、同期する。

### 含むもの

- **配布ファイル（`dist/`）**: 全リポジトリに配布する設定ファイル群。ターゲットリポジトリのルートにミラーされる
- **scaffold テンプレート（`templates/`）**: 新規リポ作成時に手動コピーする雛形（AGENTS.md / CLAUDE.md）。`sync.sh` の対象外
- **同期スクリプト（`sync.sh`）**: 配布ファイルを対象リポジトリにコピー
- **リポジトリ初期設定スクリプト（`setup-repo.sh`）**: GitHub リポジトリの設定（マージルール、ブランチ保護、セキュリティ等）を `gh` CLI で自動化

### 含まないもの

- リポジトリ固有の設定（settings.json の許可コマンド等）
- CI/CD ワークフロー（ビルド・テスト・デプロイ等。`.github` リポジトリで管理。PR 検証ワークフロー `pr-check.yaml` は配布対象）
- AI エージェントの実行環境やランタイム

## ディレクトリ構成の原則

`dist/` は**対象リポジトリのルートをミラー**する。コピー先がディレクトリ構造から自明になる。

```text
dist/.claude/skills/commit/SKILL.md  → <repo>/.claude/skills/commit/SKILL.md
dist/.claude/settings.json           → <repo>/.claude/settings.json
dist/.devcontainer/Dockerfile        → <repo>/.devcontainer/Dockerfile
```

`templates/` 配下のファイル（`AGENTS.md`、`CLAUDE.md`）は scaffold 専用で、新規リポ作成時に手動コピーする。同期対象外なので `sync.sh` は読み書きしない（[ADR-0007](adr/0007-exclude-agent-templates-from-dist.md)）。

## 配布ファイル一覧

### スキル（`dist/.claude/skills/`）

| スキル | 役割 |
|--------|------|
| commit | ステージング＆コミット |
| commit-conventions | コミットメッセージ生成ルール（参照用） |
| drive | implement→ship→review 自律ループ |
| implement | ブランチ作成・実装 |
| lint | リンター実行（lint-rules を参照） |
| lint-rules | リンターコマンド対応表（参照用） |
| pr | プッシュ＆PR 作成 |
| review | コードレビュー |
| ship | lint→commit→pr パイプライン |
| test | ビルド・テスト実行（CLAUDE.md の検証セクションを参照） |

### ルール（`dist/.claude/rules/`）

| ルール | 役割 |
|--------|------|
| git-workflow.md | ブランチ・コミット・PR 規約、禁止事項 |

### 設定ファイル（`dist/`）

| ファイル | 役割 |
|----------|------|
| lefthook-base.yaml | lefthook の共通ベース設定（commit-msg + 共通リンター）。各リポの lefthook.yaml から `extends` で参照 |
| .commitlintrc.yaml | Conventional Commits の検証設定 |
| .editorconfig | エディタ共通設定（文字コード、改行、インデント） |
| .gitattributes | 改行コード正規化、バイナリファイル判定 |
| .github/workflows/pr-check.yaml | PR タイトル・ブランチ名の Conventional Commits 検証 |
| .claude/settings.json | 許可コマンドのベースライン。リポ固有のツールは各リポで追加する |
| .claude/skills/lint-rules/SKILL.md | リンターコマンド対応表。リポの技術スタックに合わせてカスタマイズする |
| SECURITY.md | 脆弱性報告ポリシー（Private Vulnerability Reporting 誘導） |
| .mcp.json | MCP サーバー設定の雛形（Context7） |
| .yamlfmt.yaml | YAML フォーマッター設定 |
| .yamllint.yaml | YAML リンター設定 |
| .markdownlint-cli2.yaml | Markdown リンター設定 |
| .mdformat.toml | Markdown フォーマッター設定（折り返しなし、LF 改行） |
| .mise.toml | ツールバージョン管理のベースライン。リポの技術スタックに合わせてツールを追加する |
| .gitignore | 共通の無視パターン。フレームワーク固有のパターンは各リポで追加する |
| renovate.json | Renovate 依存関係自動更新設定（org shared preset `github>ozzy-labs/.github` を参照） |
| trivy.yaml | Trivy セキュリティスキャナー設定（vuln + secret のみ。IaC/コンテナは各リポでカスタマイズ） |
| biome.json | Biome リンター・フォーマッター設定 |
| lefthook.yaml | 共通ベース（`lefthook-base.yaml`）を `extends` で参照。リポ固有のフック（biome, ruff 等）は各リポで追記する |
| LICENSE | MIT ライセンス |
| CONTRIBUTING.md | コントリビューションポリシー |
| .github/pull_request_template.md | PR テンプレート（Summary, Type of Change, Checklist） |
| .github/ISSUE_TEMPLATE/bug_report.yaml | バグ報告テンプレート |
| .github/ISSUE_TEMPLATE/feature_request.yaml | 機能リクエストテンプレート |
| .vscode/settings.json | VS Code エディタ設定のベースライン |
| .vscode/extensions.json | VS Code 推奨拡張のベースライン |
| .devcontainer/Dockerfile | devcontainer ベースイメージ（Ubuntu 24.04 + Claude Code + mise + zsh） |
| .devcontainer/devcontainer.json | devcontainer 設定（features, mounts, extensions） |
| .devcontainer/initialize.sh | devcontainer 初期化スクリプト（ホスト側のマウント準備） |
| .devcontainer/post-create.sh | devcontainer 作成後スクリプト（セットアップ処理） |

## scaffold テンプレート（`templates/`）

新規リポ作成時に手動コピーする雛形を `templates/` に置く。`sync.sh` は読み書きしない。

| ファイル | 役割 |
|----------|------|
| AGENTS.md | AI エージェント共通 instructions の雛形（プロジェクト概要・tech stack・主要コマンド） |
| CLAUDE.md | Claude Code 固有の追加設定（基本ルール・利用 skill 一覧） |

これらは各リポで必ずカスタマイズされる（過去 9 リポすべてで pin 済み）ため、`dist/` から外して同期対象にしない。背景は [ADR-0007](adr/0007-exclude-agent-templates-from-dist.md) を参照。

## 同期の仕組み

### 同期ポリシー

全ファイルに同一のポリシーを適用する（[ADR-0005](adr/0005-unified-dist-with-pin.md)）。

| ファイル状態 | 対話モード | `-y` / `--yes` | `--check`（CI） | `--dry-run` |
|---|---|---|---|---|
| 未存在 | コピー | コピー | exit 1 | 表示 |
| 同一 | スキップ | スキップ | OK | 表示 |
| 差分あり | 差分表示→選択 | 上書き | exit 1 | 表示 |
| 差分あり (pinned) | スキップ | スキップ | OK | 表示 |

### pin 機構

ターゲットリポジトリ側で意図的な乖離を宣言する仕組み:

- 対話モードで差分のあるファイルについて選択: `[y/N/pin/all]`（y=更新, N=スキップ, pin=永続スキップ, all=残り全て更新）
- pinned ファイルは全モードでスキップ（意図的な乖離を尊重）
- 設定: 対話モードで `pin` を選択、または `.dev-config/sync.yaml` を手動編集
- 解除: `.dev-config/sync.yaml` から該当行を削除

### 同期メタデータ

`sync.sh` は同期完了後、対象リポジトリの `.dev-config/sync.yaml` にメタデータを書き込む:

```yaml
# Auto-updated by commons sync.sh
# 'pinned' is user-editable — add or remove paths freely
commit: abc1234
synced_at: 2026-04-05T00:00:00Z
pinned:
  - CLAUDE.md
  - .claude/settings.json
```

- `--check` は pinned 以外のファイルを検証対象とする
- ファイルコピーが発生した場合、または pinned リストが存在する場合に書き込む（`-y` モードでは無条件に書き込む）
- 対象リポジトリにコミットする想定（`.gitignore` に入れない）
- `--dry-run` 時は書き込まない

## リポジトリ初期設定（setup-repo.sh）

`setup-repo.sh` は GitHub リポジトリの設定を `gh` CLI で自動化する。`sync.sh` がファイル同期を担当するのに対し、`setup-repo.sh` は GitHub 側の設定を担当する。

### 設定内容

#### マージ設定

| 設定 | デフォルト | 変更後 | 理由 |
|------|-----------|--------|------|
| Merge commit | 許可 | 禁止 | squash merge のみの運用 |
| Rebase merge | 許可 | 禁止 | 同上 |
| ブランチ自動削除 | 無効 | 有効 | マージ後のブランチ削除を自動化 |
| Auto merge | 無効 | 有効 | CI 通過後の自動マージを許可（PR ごとに opt-in） |

#### ブランチ保護（Rulesets）

| ルール | 理由 |
|--------|------|
| main への直接 push 禁止 | git-workflow ルール |
| force push 禁止 | git-workflow ルール |
| main の削除禁止 | デフォルトブランチの保護 |
| PR 必須（承認数 0） | PR 作成を強制しつつソロ開発に対応 |
| linear history 必須 | squash merge と整合 |

- bypass は禁止（admin 含む）
- CI ステータスチェックは含めない（リポごとに手動設定）

#### セキュリティ

| 設定 | 理由 |
|------|------|
| Secret scanning | gitleaks と二重防御 |
| Push protection | シークレット漏洩防止 |
| Dependabot alerts | 依存関係の脆弱性検知 |
| Dependabot security updates | 脆弱性の自動修正 PR |
| Private Vulnerability Reporting | SECURITY.md との整合（public リポのみ） |

#### リポジトリ設定

| 設定 | デフォルト | 変更後 | 理由 |
|------|-----------|--------|------|
| Wiki | 有効 | 無効 | ドキュメントはリポ内で管理 |

#### Actions permissions

| 設定 | デフォルト | 変更後 | 理由 |
|------|-----------|--------|------|
| Workflow permissions | read | read-write | PR 作成等のワークフローに write 権限が必要 |
| Allow creating and approving PRs | 無効 | 有効 | ワークフローからの PR 操作を許可 |

#### ラベル

GitHub デフォルトラベル（9 個）を削除し、Conventional Commits の type に合わせたラベルに置換する:

`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

### sync.sh との棲み分け

| 観点 | sync.sh | setup-repo.sh |
|------|---------|---------------|
| 対象 | ファイル（スキル、ルール、設定ファイル） | GitHub リポジトリ設定（API） |
| 実行頻度 | commons 更新時に毎回 | リポジトリ作成時に 1 回 |
| 冪等性 | あり（差分検出） | あり（Rulesets は既存チェックで create/update を切り替え） |
| 依存 | git | gh CLI（認証済み） |

## 既知の制限事項

### sync.sh はファイル削除を扱わない

`dist/` からファイルを削除しても、既に同期済みのターゲットリポジトリからは自動削除されない。ファイルを廃止する場合は、各リポジトリで手動削除する必要がある。

## マルチエージェント対応

現在は Claude Code のみだが、構造はエージェント追加に対応している:

```text
dist/
├── .claude/       # Claude Code
├── .codex/        # Codex（将来）
└── .github/       # Copilot（将来）
```

各エージェントの設定ディレクトリを `dist/` に並列配置する。
