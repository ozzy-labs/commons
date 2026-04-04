---
description: 拡張子別リンター・フォーマッターのコマンド対応表。他スキルから参照される。
user-invocable: false
---

# lint-rules - リンター・フォーマッターコマンド対応表

lint スキルから参照される。対象ファイルの拡張子に応じて以下のコマンドを実行する。

## コマンド対応表

| 拡張子 | コマンド |
|--------|---------|
| `.md` | `markdownlint-cli2 <file>` |
| `.yaml` | `yamlfmt <file> && yamllint <file>` |
| `.sh` | `shellcheck <file> && shfmt -w <file>` |

## セキュリティ

全ファイルを対象に Gitleaks でシークレット検出を実行する:

```bash
gitleaks detect --no-banner
```
