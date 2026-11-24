---
inclusion: always
---

# Stack and conventions

TypeScript, strict mode, ESM, Node 20+. pnpm workspace. Vitest with fast-check for tests.

## Commands

```bash
pnpm install
pnpm -r build
pnpm -r typecheck            # tsc --noEmit
pnpm -r lint
pnpm test                    # vitest --run   (never watch mode)
pnpm test:prop               # vitest --run the *.prop.test.ts files only
pnpm necro -- scan fixtures/haunted-repo
```

Always pass `--run` to Vitest. Watch mode blocks in an agent session and in CI.

## Credentials

Read from the environment only. Never from a committed config file, never a default value in code,
never printed — including under `--verbose` and in error messages.

| Variable | Used for | Absent means |
|---|---|---|
| `NEBIUS_API_KEY` | LLM classify and verify | heuristics-only degraded mode, stated in the report |
| `TAVILY_API_KEY` | search and extract | degraded discovery: redirect target and archive only |
| `GITHUB_TOKEN` | PR creation, dashboard repo reads | `--pr` exits 2; dashboard cannot scan |

Degraded mode is a first-class path, not an error. A run with no keys must complete and say so.

## Providers

- **LLM:** OpenAI-compatible API at `https://api.tokenfactory.nebius.com/v1/` (Nebius Token
  Factory). Two model slots in config — a fast classifier and a stronger verifier. Validate both
  IDs against `GET /v1/models` on first use and fail with the available IDs listed; never hardcode
  a model ID in source.
- **Search:** Tavily `search` with domain restriction, then `extract`.
- **Archive:** Wayback CDX for snapshot selection, and the `id_` modifier
  (`https://web.archive.org/web/<ts>id_/<url>`) to fetch snapshot content. Always `id_` for content
  comparison — the plain snapshot URL injects the Wayback toolbar into the DOM and skews every
  similarity score.

## Style

- Prefer a pure function with injected dependencies over a class with state. Every pipeline stage
  is a module of pure functions plus one orchestrator.
- Validate external data at the boundary with Zod: config, LLM responses, API payloads. A parsed
  type is trusted inside; an unparsed one is not.
- No thrown errors for expected conditions. A dead link, a missing snapshot and a rejected candidate
  are results, not exceptions. One link can never abort a run.
- Tunable numbers — thresholds, weights, caps, timeouts — live in config with a documented default,
  not as inline constants. They need calibrating against the haunted repo.
