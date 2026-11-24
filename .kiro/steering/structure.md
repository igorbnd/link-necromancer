---
inclusion: always
---

# Repository structure

pnpm workspace. Five packages, one engine.

```
packages/core     the pipeline: exhume → probe → autopsy → resurrect → verify → adjudicate → deliver
apps/cli          necro scan / necro fix, and the GitHub PR writer
apps/web          the public graveyard dashboard (Next.js on Vercel)
apps/action       the GitHub Action
apps/mcp          the MCP server (stretch)
fixtures/         haunted-repo/ (seeded demo repo + expected.json) and cache/ (recorded providers)
scripts/hooks/    the scripts the agent hooks call
.kiro/specs/      five specs, each requirements.md + design.md + tasks.md
```

## Layering rules

Breaking one of these is the most likely way this codebase goes wrong, because each rule is what
makes a safety property structural rather than conditional.

- **No pipeline logic outside `packages/core`.** If a surface needs behaviour the pipeline does not
  have, add it to core. The CLI, the dashboard, the Action and the MCP server are adapters,
  renderers and configuration.
- **All I/O in core goes through an injected provider interface** (`HttpClient`, `Archive`,
  `Search`, `Llm`, `FileSystem`, `Git`). Core never imports `node:fs` or `fetch` directly outside
  `providers/`. This is what lets the dashboard run the same pipeline against the GitHub API with
  no local clone.
- **Every provider call goes through the cache decorator.** The cache is the test fixture store and
  the demo determinism mechanism, not an optimization.
- **PR creation lives only in `apps/cli`.** It is the only code that writes outside the working
  tree. Keeping it there is why the dashboard and the MCP server cannot open a PR by accident.
- **`apps/web` and `apps/mcp` construct `FileSystem` with no `write` method.** Not a flag — there
  is no code path. Same for `necro scan`, which does not construct a fix applier at all.
- **Verdict adjudication is pure.** `adjudicate()` takes `(condition, bestVerification, config)` and
  returns `(verdict, action)` with no I/O, so the one-action-per-verdict property is a unit test.

## Where things go

| Adding | Goes in |
|---|---|
| A new file type to scan | `packages/core/src/exhume/` |
| A new zombie signal | `packages/core/src/autopsy/heuristics.ts` |
| A new candidate source | `packages/core/src/resurrect/candidates.ts` |
| A new provider | `packages/core/src/providers/`, wrapped in `cache.ts` |
| A new output format | `packages/core/src/deliver/` |
| A new CLI flag | `apps/cli/src/flags.ts` plus the owning command |
| A planted test case | `fixtures/haunted-repo/` **and** its `expected.json` row |

Changing behaviour described in a spec means updating that spec in the same change. The specs are
committed artifacts, not a historical record.
