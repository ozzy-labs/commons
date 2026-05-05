#!/usr/bin/env bash
# Routine Setup script template.
#
# このファイルの内容を Web UI の Setup script 欄にそのまま貼り付ける。
# ローカル検証用に `bash .claude/routines/<name>/setup.sh` でも動く形に保つ。
# ターゲット環境は Routines のクラウド VM (Ubuntu)。
set -euo pipefail

# 1. mise (polyglot toolchain manager) — installs from .mise.toml
curl https://mise.run | sh
export PATH="${HOME}/.local/bin:${PATH}"
eval "$(mise activate bash)"

# 2. 言語ツールチェーン一括インストール（Python / Node / その他）
mise install

# 3. gh CLI（PR 操作に使用。Routines のクラウド VM にプリインストールされていない）
sudo apt-get update -qq
sudo apt-get install -y -qq gh

# 4. ── project-specific install ──────────────────────────────────
#  以下は routine ごとに書き換える領域。新しい routine を作るときに
#  `cp -r _template <name>/` した後で、対象 repo の依存解決コマンドを書く。
#
# 例:
#   uv sync --frozen                # Python (uv)
#   pnpm install --frozen-lockfile  # Node (pnpm)
#   bundle install --jobs=4         # Ruby
