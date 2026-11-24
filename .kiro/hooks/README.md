# Agent hooks

Six hooks. Each is a thin JSON wrapper; the logic lives in `scripts/hooks/` so it is readable,
testable and reusable from CI.

| Hook | Trigger | What it does |
|---|---|---|
| `session-start-status` | `SessionStart` | Branch, working tree, scaffolding state, credential presence, spec task progress |
| `property-tests-gate` | `Stop` | Won't let a turn end with the property suite red |
| `secret-leak-guard` | `PreToolUse` (`shell`) | Blocks a `git commit` that would include credentials |
| `core-save-check` | `PostFileSave` | Typecheck + related tests when a `packages/core` source is saved |
| `spec-sync-reminder` | `PostFileSave` | Flags that a spec's `design.md` / `tasks.md` may now disagree with its `requirements.md` |
| `fixture-expectations-reminder` | `PostFileSave` | Flags that `fixtures/haunted-repo/expected.json` may be stale |

## Which hooks fire where

**This matters for the demo.** Per the [hook types docs](https://kiro.dev/docs/hooks/types),
Kiro Web runs only the Prompt Submit, Agent Stop, Session Start, Pre Tool Use and Post Tool Use
triggers. The three `PostFileSave` hooks above are **IDE and CLI only**.

| Hook | Web | IDE | CLI |
|---|---|---|---|
| `session-start-status` | yes | yes | yes |
| `property-tests-gate` | yes | yes | yes |
| `secret-leak-guard` | yes | yes | yes |
| the three `PostFileSave` hooks | **no** | yes | yes |

So record the "hooks firing on save" beat of the demo in the IDE or the CLI. A Kiro Web session
will not show it.

File triggers also fire only on **agent** edits, not on a human editing in the editor.

## They are inert until the workspace is scaffolded

`check-core-save.sh` and `check-properties.sh` both exit 0 immediately when there is no
`package.json` or no `node_modules`. The hooks are committed now and become live the moment
core-pipeline task 1 lands, with no edit needed.

`check-properties.sh` also skips when the turn touched nothing under `packages/core` or `fixtures/`,
so a docs-only or dashboard-only turn is not taxed with a test run.

## Reusing the scripts in CI

```bash
scripts/hooks/check-secrets.sh --all     # scan every tracked file; exit 1 on a finding
scripts/hooks/check-properties.sh        # exit 1 on a red property suite
```

`check-secrets.sh` reports a file, a line and the rule that matched. It never prints the matched
text, so a CI log cannot leak the value it just caught.

## Turning one off

Set `"enabled": false` on the hook entry rather than deleting the file, so the intent stays in
version control.
