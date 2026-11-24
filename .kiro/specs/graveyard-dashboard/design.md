# Graveyard dashboard — design

## Overview

Next.js App Router on Vercel. The server runs the same `core.scan()` the CLI runs, with two
adapters swapped in: a `FileSystem` backed by the GitHub contents API and a `Git` backed by the
GitHub GraphQL blame API. No new pipeline code exists in this app — if the dashboard needs a
behaviour the pipeline does not have, it goes in core.

The hard problem is not the UI. It is finishing a scan inside a serverless function while streaming
progress, without cloning a repo, and without becoming an open proxy.

## Architecture

```
  Browser                        Vercel                            External
  ───────                        ──────                            ────────
  paste repo URL
      │  POST /api/scan            ┌──────────────────────┐
      ├──────────────────────────▶ │ validate + resolve   │──▶ GitHub REST: repo, ref → SHA
      │  { jobId }                 │ rate limit by IP     │
      │◀─────────────────────────  └──────────┬───────────┘
      │                                       │  cache hit on (owner,repo,sha,opts)? → return
      │  GET /api/scan/:id/events             ▼
      ├──────────────────────────▶ ┌──────────────────────┐──▶ GitHub REST tree + contents
      │   SSE: stage events        │   core.scan()        │──▶ GitHub GraphQL blame
      │◀═════════════════════════  │  GithubFileSystem    │──▶ target sites (probe, SSRF-guarded)
      │                            │  GithubGit           │──▶ Wayback CDX + snapshots
      │   SSE: final RunReport     │  Tavily, Nebius      │──▶ Tavily, Nebius Token Factory
      │◀═════════════════════════  └──────────┬───────────┘
      │                                       ▼
      │  GET /api/scan/:id         ┌──────────────────────┐
      ├──────────────────────────▶ │  KV: report by jobId │
      │                            └──────────────────────┘
      ▼
  render graveyard, download patch
```

### Why a job plus SSE rather than one request

A single `POST` that returns the finished report is simpler but gives the visitor a blank page for
up to a minute, and on a timeout loses everything. The job model costs one KV store and buys three
things the demo needs: streamed progress, partial results on budget exhaustion, and a shareable
permalink that replays from cache. The report is written to KV incrementally as stages complete, so
a function that dies at 95% still leaves a usable partial report behind.

## Serverless budget design

Target: finish inside the configured function `maxDuration`, reserving 20% headroom. The caps are
derived from that target rather than guessed:

| Knob | Default | Reason |
|---|---|---|
| Max files read | 200 | Tree listing is one call; contents are batched; reading dominates nothing |
| Max unique links probed | 50 | Probing is the long pole: 50 links at 16-way concurrency with retries fits the budget |
| Max bytes fetched per scan | 32 MB | Bounds memory and egress |
| Wall-clock budget | `maxDuration × 0.8` | Leaves room to write the partial report and flush SSE |
| Per-link LLM calls | 2 (one classify, one verify) | Bounds cost and latency |

The core pipeline already accepts `maxLinks` and a wall-clock budget and returns partial results
cleanly, so the app sets these and does not implement its own cutoff logic.

Two levers keep the demo fast regardless: the provider cache is shared and persistent (Vercel KV or
Upstash Redis rather than a local directory, via a KV cache backend injected into the core cache
decorator), and completed scans are cached by commit SHA. The seeded haunted repo will be warm, so
the demo scan returns in seconds.

## Repository access adapters

### `GithubFileSystem`

- `GET /repos/{o}/{r}/git/trees/{sha}?recursive=1` for the file list, filtered by the core's
  extension set and the optional subdirectory, then truncated to the file cap.
- File contents in batches via `GET /repos/{o}/{r}/contents/{path}?ref={sha}` with the raw media
  type. If the tree response is flagged `truncated`, the app says so and scans what it got.
- Read-only: `write` is not implemented, which makes "the dashboard cannot modify a repo"
  structural.

### `GithubGit`

GraphQL blame, because `git blame` needs history the app does not have:

```graphql
query($owner:String!, $name:String!, $ref:String!, $path:String!) {
  repository(owner:$owner, name:$name) {
    object(expression:$ref) { ... on Commit {
      blame(path:$path) { ranges { startingLine endingLine commit { authoredDate oid } } }
    }}
  }
}
```

Ranges are expanded into the line-indexed map the core `Git` interface expects. Blame is requested
only for files that actually produced links, and only for repos under the file cap — on a blame
failure or rate limit the adapter falls back to the earliest commit touching the file
(`GET /repos/{o}/{r}/commits?path={path}&until={sha}`) and marks the date approximate, which the UI
shows on the evidence card.

Unauthenticated GitHub API limits are too low for this, so the server uses its own token for reads
only. That token is server-side, read-scoped, and never reaches the client.

## SSRF defence

This is the one place where a stranger's input causes the server to make arbitrary outbound
requests, so the guard is explicit and sits in the probe path, not in the URL parser:

1. Parse and reject non-`http(s)` schemes and hosts that are IP literals in a private, loopback,
   link-local, unique-local or metadata range.
2. Resolve the hostname and reject if **any** resolved address falls in those ranges. A hostname
   that resolves to `169.254.169.254` is the attack this blocks.
3. Pin the connection to the validated address so a DNS rebind between the check and the request
   cannot slip through, implemented with an undici connector that supplies the checked IP.
4. Re-run the full check on every redirect hop. A public URL redirecting to `127.0.0.1` is the other
   half of the attack.
5. Cap redirects, body size and total scan bytes.

Steps 2 through 4 are what make this a real defence rather than a string check; a parse-time-only
guard is the common way this gets built wrong.

## UI structure

```
apps/web/
  app/
    page.tsx                     submit form, example repos, stated limits
    scan/[jobId]/page.tsx        graveyard view, hydrates from KV, subscribes to SSE
    api/scan/route.ts            POST: validate, rate limit, resolve SHA, cache check, start job
    api/scan/[id]/route.ts       GET: current report
    api/scan/[id]/events/route.ts SSE stream
    api/scan/[id]/patch/route.ts unified diff download
  components/
    SubmitForm.tsx
    Graveyard.tsx                grid, filters, sort, summary
    Headstone.tsx                one card; variant chosen by verdict
    EvidenceCard.tsx             the two quotes, timestamps, score, reason, deciding tier
    ResurrectionAnimation.tsx    reduced-motion aware, replayable
    DegradedNotice.tsx
    PartialNotice.tsx
    ExportBar.tsx                patch, markdown, PR body, JSON
  lib/
    github-fs.ts                 GithubFileSystem
    github-git.ts                GithubGit
    ssrf.ts                      the guard above
    kv-cache.ts                  KV backend for the core cache decorator
    ratelimit.ts
    jobs.ts                      job lifecycle, incremental report writes
```

### Verdict to visual mapping

| Verdict | Visual | Icon | Text badge |
|---|---|---|---|
| `ALIVE` | living ground, collapsed by default | 🌱 | ALIVE |
| `RESURRECTED` | ghost rising from an open grave | 👻 | RESURRECTED |
| `ARCHIVED` | sealed crypt | ⚱️ | ARCHIVED |
| `DRIFTED` | cracked tombstone | 🪦 (cracked) | DRIFTED |
| `PARKED` | tombstone with a "for sale" sign | 🏚️ | PARKED |
| `SOFT_404` | tombstone, hollow | 🕳️ | SOFT_404 |
| `UNRESOLVED` | plain tombstone | 🪦 | UNRESOLVED |

Icon plus text badge means colour is never the only carrier, satisfying requirement 5.3 without a
separate accessibility pass. The `cause` badge sits beside the verdict badge, which is how a judge
sees "200 OK, and parked" — the point the demo turns on.

### Motion

The resurrection animation is CSS-driven and gated on a `useReducedMotion` hook. Under reduced
motion the ghost appears in its final state immediately and the replay control is hidden. The
animation is decorative only: no information is conveyed solely by movement.

## Export

`ExportBar` has no client-side generation logic. The patch comes from `GET /api/scan/:id/patch`,
which calls the core unified-diff emitter over the stored report, so the browser download and the
CLI's `--patch` output come from one implementation. Markdown report and PR body likewise reuse the
core and CLI renderers.

## Error handling

| Case | Behaviour |
|---|---|
| Private or missing repo | 404 with a specific message; UI suggests the CLI for private repos |
| Rate limited | 429 with `Retry-After`; UI shows the time |
| Tree truncated by GitHub | Scan what was returned, show a partial notice naming the cause |
| Blame unavailable | Approximate dates, marked on the evidence card |
| Budget or cap hit | Partial report, notice naming the cap, completed verdicts fully usable |
| Function dies mid-scan | Last incremental report in KV is served; UI offers retry |
| No links found | Empty-graveyard state, not an error |
| SSE connection drops | Client reconnects and re-reads the report; no progress lost |

## Testing strategy

- **SSRF test suite** is the priority: IP-literal rejection, hostname-resolving-to-private
  rejection, redirect-to-private rejection, and a rebind simulation where DNS returns a public
  address on the first lookup and a private one on the second.
- **Adapter tests** for `GithubFileSystem` and `GithubGit` against recorded GitHub API fixtures,
  including the truncated-tree and blame-failure paths.
- **Budget test**: a synthetic repo above every cap returns a partial report with the correct cap
  named, inside the budget.
- **Component tests** for each `Headstone` variant and for `EvidenceCard` with and without a
  repaired anchor.
- **Accessibility**: axe checks on the submit and results pages; a keyboard-only walkthrough test;
  a reduced-motion snapshot.
- **End-to-end** against the seeded haunted repo through a replay-mode cache, asserting every
  planted verdict renders with the expected variant and that resurrected cards show two quotes.
