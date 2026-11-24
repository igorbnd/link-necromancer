# MCP server — design

> Stretch scope. See [requirements](./requirements.md).

## Overview

A stdio MCP server over `@modelcontextprotocol/sdk`, wrapping `packages/core`. It is the smallest of
the five surfaces: four tools, no state beyond a session-scoped cache, no writes.

## Architecture

```
  agent (Kiro / Claude)
        │  stdio, MCP
        ▼
  ┌──────────────────────────────┐
  │ necro-mcp                    │
  │  tool registry (Zod→JSON     │
  │   Schema, one source)        │
  │  root jail on every path     │
  │  session provider cache      │
  └──────────────┬───────────────┘
                 ▼
          packages/core  ──▶ probe / archive / search / llm
```

## Tool surface

| Tool | Input | Output | Core stages used |
|---|---|---|---|
| `check_links` | path \| dir \| inline content, options | summary + per-link verdicts and suggestions | 1–6 |
| `resurrect_link` | url, context, addedAt | verdict, ranked candidates, evidence, snapshot | 2–5 |
| `verify_replacement` | oldUrl, newUrl, asOf | score, reason, grounded evidence, pass/fail | 5 |
| `propose_edits` | check result \| path | edit set + unified diff | 7 |

`propose_edits` exists because the alternative — having `check_links` return edits inline — makes the
common "just tell me what's broken" call expensive and verbose. Splitting discovery from edit
generation lets an agent pay for byte spans only when it intends to write.

## Schema single-sourcing

Each tool's input and output Zod schema lives next to the tool, and the MCP tool declaration is
generated from it with `zod-to-json-schema` at startup. Handlers parse their input through the same
schema. A schema change therefore updates the declared contract and the runtime validation together;
there is no second hand-written JSON Schema to drift.

## Safety design

- **No write path exists.** The server constructs the core `FileSystem` provider without a `write`
  implementation. There is no flag, no option and no code path that writes a file. This is the same
  structural approach the dashboard uses, and it is why requirement 5.3 is trivially true rather
  than something to verify behaviourally.
- **Root jail.** Every incoming path is resolved against the configured root and rejected if the
  resolved path escapes it, including through symlinks (checked with `realpath`). Inline content is
  accepted with a notional path that is never touched on disk.
- **Credential isolation.** Keys come from the environment of the server process. Tool outputs pass
  through the core redactor.
- **No network from arguments without bounds.** `resurrect_link` and `verify_replacement` take URLs
  straight from an agent, so they reuse the probe path's limits: redirect cap, body cap, per-host
  rate limit. The dashboard's SSRF guard is not required here because the server runs on the user's
  own machine with the user's own network access, but the host-blocklist portion is enabled by
  default and documented as configurable.

## Response shaping

Agent context is the scarce resource, so every response is built in layers and truncated from the
bottom:

1. Summary counts — never truncated.
2. Per-link verdict, cause, file and line — never truncated, but subject to `maxLinks`.
3. Suggested replacement and score — truncated only after layer 4.
4. Evidence quotes and rejected-candidate lists — truncated first.

Truncation is reported in the response (`truncated: { layer, omitted }`) so an agent knows detail
exists and can request it for a specific link rather than re-running the scan.

## Session cache

The core cache decorator is constructed once per server process with an in-memory LRU in front of
the on-disk store. An agent iterating on one document re-checks the same URLs repeatedly; without
this, a five-turn editing session would re-probe every link five times.

## Error handling

| Case | Response |
|---|---|
| Path outside root | Structured error, `retryable: false`, names the root |
| Missing `NEBIUS_API_KEY` | Tools still work in degraded mode; `capabilities` reports the limitation |
| Missing `TAVILY_API_KEY` | `resurrect_link` returns redirect and archive candidates only, flagged degraded |
| Provider rate limit | Structured error, `retryable: true`, with a suggested delay |
| Malformed input | Zod error mapped to a structured error naming the field |
| `maxLinks` hit | Partial result with `truncated` set, not an error |

Marking errors `retryable` matters more for an agent than for a human: an agent will otherwise
either retry a permanent failure forever or give up on a transient one.

## Configuration

```jsonc
// Kiro MCP config
{
  "mcpServers": {
    "link-necromancer": {
      "command": "npx",
      "args": ["-y", "necro-mcp", "--root", "."],
      "env": {
        "NEBIUS_API_KEY": "...",
        "TAVILY_API_KEY": "..."
      }
    }
  }
}
```

## Testing strategy

- **Protocol tests** driving the server over an in-memory transport: list tools, call each tool,
  assert the declared schema matches the actual response shape.
- **Root jail tests**: `../` traversal, absolute paths outside the root, and a symlink pointing out.
- **No-write assertion**: a filesystem snapshot taken before and after an exhaustive tool-call
  sweep must be byte-identical.
- **Truncation tests**: a response over budget keeps layers 1 and 2 intact and reports what it
  dropped.
- **Ungrounded-quote test**: `verify_replacement` with a fixture where the model fabricates a quote
  returns an explicit ungrounded result, not a low score.
- **Agent smoke test**: Kiro configured against the server, asked to fix the links in a haunted
  fixture document, completes the task using `check_links` then `propose_edits`.
