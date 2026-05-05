# Claude Code Routines

[Claude Code Routines](https://code.claude.com/docs/en/routines)（Anthropic クラウド側で動く非対話エージェント）の設定をリポジトリで管理するためのディレクトリ。

## ⚠️ `.claude/skills/` とは別物

| 項目         | `.claude/skills/`         | `.claude/routines/` (このディレクトリ)     |
| ------------ | ------------------------- | ------------------------------------------ |
| ロード       | Claude Code が auto-load  | **Anthropic クラウド側に手動コピー**       |
| 実行場所     | ローカル CLI              | Anthropic クラウド VM                      |
| 自動連携     | あり                      | **なし**（リポは正本のコピー先にすぎない） |
| シークレット | `.env` から読める         | Web UI 側の secret として別管理            |

このディレクトリのファイルを編集しても**自動では Web UI に反映されない**。必ず手動で同期する。

## ディレクトリ構造

```text
.claude/routines/
├── README.md              # このファイル
├── _template/             # 新規 routine 作成のひな形
│   ├── routine.yaml
│   ├── prompt.md
│   └── setup.sh
└── <routine-name>/        # 1 routine = 1 ディレクトリ
    ├── routine.yaml       # メタデータ・トリガー・権限
    ├── prompt.md          # Web UI の Prompt 欄に貼り付ける本文
    └── setup.sh           # Web UI の Setup script 欄に貼り付ける本文
```

## 運用ルール

### 正本はリポ

- Web UI で直接編集**しない**
- 変更は必ずリポの PR → マージ → Web UI に手で反映、の順で行う
- Anthropic 側に GET routine API がないため drift の機械検知は不可能。規約で守る

### 新規追加

1. `cp -r .claude/routines/_template .claude/routines/<new-name>`
2. 3 ファイルを編集（`routine.yaml` / `prompt.md` / `setup.sh`）
   - `routine.yaml` の `repositories:` を実際の `<owner>/<repo>` に置換
   - `prompt.md` の `<owner>/<repo>` プレースホルダを置換
   - `setup.sh` の **project-specific install** 領域に対象リポの依存解決コマンドを追加
3. `status: draft` のまま PR 作成・マージ
4. [claude.ai/code/routines](https://claude.ai/code/routines) で **New routine** → 各欄に `prompt.md` / `setup.sh` を貼り、`routine.yaml` の cron / 権限 / connectors を反映
5. 表示された `routine_id` を `routine.yaml` に書き戻し、`status: active` に変更する小コミットを `main` に追加

### 更新

1. PR で 3 ファイルを更新 → マージ
2. Web UI に手で反映

### 削除

1. Web UI で routine を削除
2. `git rm -r .claude/routines/<name>/`

### シークレットの取り扱い

- 値は**絶対に commit しない**
- `routine.yaml` の `environment.variables` には**名前だけ**書く
- API trigger の fire token は password manager 等で別管理

## ファイルの約束ごと

### `setup.sh`

- **ローカル実行可能な形に書く**: `bash .claude/routines/<name>/setup.sh` で動くこと
- ターゲット環境は **Routines クラウド VM (Ubuntu)** 前提
- `sudo apt-get` 等の Ubuntu 依存コマンドの利用は OK だが、ローカル検証は WSL/Linux で行う
- mise を介して言語ツールチェーンを揃える前提（`.mise.toml` がリポルートにある想定）
- 重複が増えたら `_lib/setup-common.sh` への切り出しを検討（**3 routine 目を作る前**を目安）

### `prompt.md`

- 完全自律実行を前提に self-contained に書く（`AskUserQuestion` は使わない）
- ローカル MCP サーバー（`knowledge` / `context7` 等）はクラウド環境に存在しない前提で書く
- `claude/*` ブランチで PR を立てる運用に揃える（main 直 push を要求しない）

### `routine.yaml`

- 必須: `name`, `description`, `status`, `repositories`, `model`, `triggers`
- `status` は `active` または `draft` の 2 値（Web UI 未登録は `draft`）
- `routine_id` は Web UI 登録後に書き戻す。空でよいのは `status: draft` のときだけ
- `triggers` は配列（schedule / api / github を将来混在可能）

## バリデーション（任意）

`scripts/routines/validate.py` を用意すれば必須フィールド・cron 妥当性・`status: active` なら `routine_id` が空でないか等を検証できる。Lefthook の **pre-push** に組み込むのが推奨（pre-commit には入れない）。

## opt-out

特定リポでこのディレクトリを管理したくない場合は、`.commons/sync.yaml` の `pinned:` に `.claude/routines/` 配下のパスを追加して同期対象から外す。

## 参考

- [Automate work with routines](https://code.claude.com/docs/en/routines)
- [Trigger a routine via API](https://platform.claude.com/docs/en/api/claude-code/routines-fire)
- [Claude Code on the web（cloud environment）](https://code.claude.com/docs/en/claude-code-on-the-web)
- knowledge MCP: `ai/agents/claude-code-routines`, `ai/practice/scheduled-tasks`
