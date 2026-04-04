# 設計方針

## リポジトリの責務

`ai-config` は、OzzyLabs の全リポジトリに共通する AI エージェント設定を一元管理し、同期する。

### 含むもの

- **共有ファイル（`shared/`）**: 全リポジトリで同一であるべきスキル・ルール。毎回上書きで同期
- **テンプレート（`templates/`）**: 新規リポジトリの初期セットアップ用雛形。存在しない場合のみコピー
- **同期スクリプト（`sync.sh`）**: 上記2種のファイルを対象リポジトリにコピー

### 含まないもの

- リポジトリ固有の設定（CLAUDE.md のプロジェクト概要、settings.json の許可コマンド等）
- CI/CD ワークフロー（`.github` リポジトリで管理）
- AI エージェントの実行環境やランタイム

## ディレクトリ構成の原則

`shared/` と `templates/` はどちらも**対象リポジトリのルートをミラー**する。コピー先がディレクトリ構造から自明になる。

```text
shared/.claude/skills/commit/SKILL.md  → <repo>/.claude/skills/commit/SKILL.md
templates/CLAUDE.md                    → <repo>/CLAUDE.md
templates/.claude/settings.json        → <repo>/.claude/settings.json
```

## 共有 vs テンプレートの判断基準

| 基準 | shared/ | templates/ |
|------|---------|-----------|
| 全リポジトリで同一であるべきか | はい | いいえ |
| 同期時に上書きしてよいか | はい | いいえ（初回のみ） |
| リポジトリ固有にカスタマイズされるか | いいえ | はい |

## マルチエージェント対応

現在は Claude Code のみだが、構造はエージェント追加に対応している:

```text
shared/
├── .claude/       # Claude Code
├── .codex/        # Codex（将来）
└── .github/       # Copilot（将来）
```

各エージェントの設定ディレクトリを `shared/` に並列配置する。
