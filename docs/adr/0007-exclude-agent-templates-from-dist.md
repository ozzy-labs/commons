# ADR-0007: Exclude AGENTS.md / CLAUDE.md from dist/ as Scaffold Templates

## Status

Accepted (2026-04-25)

## Context

[ADR-0005](0005-unified-dist-with-pin.md) の統合 dist/ 方針のもと、AGENTS.md と CLAUDE.md も `dist/` に含めて配布していた。pin 機構によって consumer 側のカスタマイズを尊重する想定だったが、運用してみると次の問題が顕在化した:

1. **配布する意味がない**

   #59 ロールアウト直後に 10 consumer リポを集計した結果、CLAUDE.md は 8/10、AGENTS.md は 6/10 のリポで template から書き換えられている（残りは starter / docs リポで完全一致のまま）。pin の有無は揺れるが、customize 済みリポは漏れなく pin している。プロジェクト概要・tech stack・主要コマンド・利用 skill 一覧などリポ固有の内容を書き換える性質上、template 一致のリポでも書き換えが起きるのは時間の問題で、`dist/` 経由で配布する意味がない。

2. **新規同期で markdownlint hook が落ちる**

   #59（commons rename ロールアウト）で create-agentic-aws に新規同期した際、配布版 AGENTS.md の `<project-name>` / `<description>` プレースホルダーが MD033/no-inline-html に該当し、pre-commit が失敗した。consumer 側で AGENTS.md を pin するまで sync PR が作れなかった。

3. **scheduled sync workflow（[ADR-0006](0006-renovate-auto-sync-preset.md)）の noise になる**

   未 pin の consumer がいる場合、weekly schedule で AGENTS.md/CLAUDE.md の差分 PR が立て続けに作られる。実態は「テンプレートを書き換えるべきだったのに書き換えていない」だけなので、自動 PR で解決しない。

検討した選択肢:

1. **dist/ に残し、配布時にプレースホルダーを置換する** — sync.sh にテンプレートエンジン相当のロジックを足す必要があり過剰。consumer 側の事情（既に customize 済みかどうか）は sync.sh からは判別できない
2. **dist/ から外し、setup-repo.sh でコピーする** — setup-repo.sh は GitHub API 操作専用（[design.md](../design.md) の棲み分け）なので責務がぶれる
3. **dist/ から外し、独立した `templates/` ディレクトリに置いて手動コピーを促す** — 採用

## Decision

### `templates/` ディレクトリを新設して AGENTS.md / CLAUDE.md を移動する

- `dist/AGENTS.md` → `templates/AGENTS.md`
- `dist/CLAUDE.md` → `templates/CLAUDE.md`

### sync.sh の対象外とする

`sync.sh` は `dist/` 配下のみを走査する（既存の動作）。`templates/` には触らないので、consumer リポに既に存在する AGENTS.md / CLAUDE.md は影響を受けない。consumer 側で pin したまま残しておけば、本変更の前後で挙動は変わらない。

### 新規リポでは手動コピー

`cp /path/to/commons/templates/AGENTS.md /path/to/new-repo/AGENTS.md` を bootstrap 手順に組み込む。setup-repo.sh への取り込みは将来検討（GitHub 設定とファイル scaffold は責務が異なるため、現時点では分けたまま）。

## Consequences

### Easier

- 配布漏れ・pin 漏れによる scheduled sync の noise PR がなくなる
- AGENTS.md テンプレートに含まれるプレースホルダー（`<project-name>` など）が consumer 側 markdownlint と衝突しない
- `dist/` の責務が「全リポ共通で同じであるべきもの」に純化される

### Harder

- 新規リポを bootstrap する際、AGENTS.md / CLAUDE.md を別途 `cp` する手順が増える（README に明記）
- 既存 consumer リポの pinned リストから AGENTS.md / CLAUDE.md を消すかは consumer 判断（消しても sync が走らないため挙動は同じ。残しても害はない）

### 関連 Issue

- #42 — 本 ADR で対応した部分（AGENTS.md / CLAUDE.md 除外）。プロファイル化・汎用 ci.yaml・commitlint Node.js 依存などは scope を残して継続検討
- #59 — markdownlint 失敗の実害ケース
