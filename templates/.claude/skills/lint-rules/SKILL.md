---
description: 拡張子別リンター・フォーマッターのコマンド対応表と型チェックルール。他スキルから参照される。
user-invocable: false
---

# lint-rules - リンター・フォーマッターコマンド対応表

lint スキルから参照される。対象ファイルの拡張子に応じて以下のコマンドを実行する。

## コマンド対応表

| 拡張子 | コマンド |
|--------|---------|
| `.ts`, `.tsx`, `.js`, `.jsx`, `.json` | `biome check --write <file>` |
| `.md` | `markdownlint-cli2 <file>` |
| `.yaml` | `yamlfmt <file> && yamllint <file>` |
| `.toml` | `taplo format <file>` |
| `.sh` | `shellcheck <file> && shfmt -w <file>` |

## 型チェック

TypeScript / JavaScript / Astro ファイルが変更された場合、lint 完了後に型チェックを実行する:

```bash
pnpm run typecheck
```

## セキュリティ

全ファイルを対象に Gitleaks でシークレット検出を実行する:

```bash
gitleaks detect --no-banner
```
