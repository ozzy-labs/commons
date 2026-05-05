# Routine Prompt Template

> このファイルの内容を Web UI の **Prompt** 欄にそのまま貼り付ける。
> 完全自律実行が前提（`AskUserQuestion` は機能しない）。

---

You are running `ROUTINE_NAME` for the `<owner>/<repo>` repository. This is a fully autonomous run — there is no human to answer prompts.

## Goal

(このルーチンが達成すべきゴールを 1〜2 文で記述)

## Steps

1. ステップ 1
2. ステップ 2
3. ステップ 3

## Hard constraints

- Do NOT use `AskUserQuestion` — the run is autonomous.
- Do NOT call MCP servers (`knowledge`, `context7`); they are not configured in the cloud environment.
- Do NOT push to `main` directly. Always use a `claude/<scope>/...` branch.
- Do NOT amend or force-push.
- Do NOT modify files outside the scope of this routine.
- Use Conventional Commits with the appropriate `type(scope):` prefix.
