# Core pipeline — design

## Overview

`packages/core` is a dependency-free-at-the-edges TypeScript library: all I/O goes through injected
provider interfaces, so the CLI, the web app, the Action and the tests all drive the same pipeline
with different adapters. There is one public entry point.

```ts
const run = await scan({ root, config, providers, onEvent });
```

`scan()` is pure orchestration. Each stage is a separate module with a narrow signature, no shared
mutable state, and no knowledge of where its inputs came from. That is what makes the stages
individually property-testable and what lets the web app run the same code in a serverless function
with a GitHub-API-backed file reader instead of a filesystem one.

## Architecture

```
                   ┌──────────────┐
   root dir ──────▶│  1 EXHUME    │  remark/parse5/comment scanner  ──▶ LinkRef[] (byte spans)
                   └──────┬───────┘
                          │  + git blame (added date per line)
                   ┌──────▼───────┐
                   │  2 PROBE     │  HttpClient, per-host limiter, retry  ──▶ ProbeResult
                   └──────┬───────┘
                          │
                   ┌──────▼───────┐    tier 1 heuristics  (free)
                   │  3 AUTOPSY   │    tier 2 archive similarity (Archive)
                   └──────┬───────┘    tier 3 classifier model (Llm, small)
                          │  ──▶ Condition { cause, signals, similarity, decidedBy }
                   ┌──────▼───────┐
                   │ 4 RESURRECT  │  redirect target | Search | Archive  ──▶ Candidate[]
                   └──────┬───────┘
                          │
                   ┌──────▼───────┐
                   │  5 VERIFY    │  verifier model + quote grounding + anchor repair
                   └──────┬───────┘
                          │  ──▶ Verification { score, reason, evidence }
                   ┌──────▼───────┐
                   │ 6 ADJUDICATE │  verdict precedence  ──▶ LinkResult { verdict, action, edit? }
                   └──────┬───────┘
                          │
                   ┌──────▼───────┐
                   │  7 DELIVER   │  JSON report, Markdown report, EditSet, unified diff
                   └──────────────┘
```

Stages 2–5 run per link with bounded concurrency. Stages 1, 6 and 7 are whole-run.

### Why these boundaries

- **Adjudication is its own stage**, separate from autopsy and verify. The verdict precedence table
  in the requirements is a pure function of `(cause, bestVerification, archiveSnapshot, config)`.
  Keeping it pure makes the "each verdict maps to exactly one action" property a unit-level
  property test with no I/O and no mocks.
- **Byte spans, not line/column, are the edit currency.** Line/column are for display. Carrying
  `[byteStart, byteEnd)` from the parser all the way to the patcher is the only way to guarantee the
  "only the URL bytes change" property for files with CRLF endings, BOMs, or multi-byte characters
  earlier in the line.
- **Every provider call goes through the cache.** The cache is not an optimization bolted on at the
  end; it is the test fixture store and the demo determinism mechanism. Writing it first costs a day
  and saves the hackathon.

## Package layout

```
packages/core/src/
  index.ts                 scan(), types re-export
  config/
    schema.ts              Zod schema + defaults
    load.ts                file → env → options overlay
  model/
    types.ts               LinkRef, ProbeResult, Condition, Candidate, Verification, LinkResult
    verdict.ts             Cause, Verdict, Action enums + precedence table
  exhume/
    discover.ts            file walk, gitignore, globs
    markdown.ts            remark + remark-gfm + remark-mdx extractor
    html.ts                htmlparser2 with location info
    comments.ts            per-language comment tokenizer
    filter.ts              scheme/host/template exclusion rules
    blame.ts               git blame --porcelain per file
  url/
    normalize.ts           idempotent normalization
    anchor.ts              github-slugger wrapper + anchor repair
  probe/
    client.ts              fetch wrapper: redirects, body cap, error classification
    limiter.ts             per-host token bucket + global semaphore
    retry.ts               backoff with jitter, Retry-After
  autopsy/
    heuristics.ts          tier 1 signal detectors
    similarity.ts          shingle Jaccard + title/heading overlap
    classify.ts            tier 3 LLM classifier
    index.ts               tier escalation + decision table
  resurrect/
    candidates.ts          candidate generation from three sources
    query.ts               search query construction
  verify/
    prompt.ts              verifier prompt + JSON schema
    ground.ts              quote grounding check
    index.ts               candidate scoring and selection
  adjudicate/
    index.ts               pure verdict precedence
  deliver/
    edits.ts               EditSet construction and application
    diff.ts                unified diff emitter
    report-json.ts
    report-md.ts
  providers/
    types.ts               HttpClient, Archive, Search, Llm, FileSystem, Git interfaces
    http.ts                undici-based HttpClient
    archive-wayback.ts     CDX + availability + id_ snapshot fetch
    search-tavily.ts       search + extract
    llm-openai.ts          OpenAI SDK against Nebius base URL
    cache.ts               content-addressed cache wrapper
  text/
    extract-main.ts        HTML → title, headings, main text
```

## Data models

```ts
// model/verdict.ts
export type Cause =
  | 'OK' | 'HTTP_ERROR' | 'NETWORK_ERROR' | 'PARKED' | 'SOFT_404' | 'CONTENT_DRIFT';

export type Verdict =
  | 'ALIVE' | 'RESURRECTED' | 'ARCHIVED' | 'DRIFTED' | 'PARKED' | 'SOFT_404' | 'UNRESOLVED';

export type Action = 'none' | 'replace' | 'flag';

/** Single source of truth. Property-tested for totality and for ALIVE ⇒ 'none'. */
export const ACTION_FOR: Record<Verdict, Action> = {
  ALIVE: 'none',
  RESURRECTED: 'replace',
  ARCHIVED: 'replace',
  DRIFTED: 'flag',
  PARKED: 'flag',
  SOFT_404: 'flag',
  UNRESOLVED: 'flag',
};
```

```ts
// model/types.ts
export interface LinkRef {
  id: string;                  // sha256(file + byteStart + rawUrl), stable across runs
  file: string;                // repo-relative, posix separators
  line: number;                // 1-based, for display
  column: number;              // 1-based character column, for display
  byteStart: number;           // inclusive, the edit currency
  byteEnd: number;             // exclusive
  rawUrl: string;              // exactly the bytes between byteStart and byteEnd
  docUrl: string;              // normalized, fragment removed
  fragment?: string;           // without the leading '#'
  linkText?: string;
  context: 'md-inline' | 'md-reference' | 'md-autolink' | 'md-bare' | 'html-attr' | 'code-comment';
  addedAt?: string;            // ISO 8601 from git blame
  addedCommit?: string;
}

export interface ProbeResult {
  docUrl: string;
  ok: boolean;                 // 2xx after redirects
  status?: number;
  redirectChain: string[];
  finalUrl?: string;
  contentType?: string;
  bodyTruncated: boolean;
  page?: PageContent;          // parsed, not raw HTML
  networkError?: 'dns' | 'tls' | 'timeout' | 'connection-reset' | 'too-many-redirects' | 'other';
  elapsedMs: number;
  fromCache: boolean;
}

export interface PageContent {
  title?: string;
  headings: string[];          // in document order, h1–h3
  mainText: string;            // boilerplate-stripped, capped at 20k chars
  textLength: number;
}

export interface Condition {
  cause: Cause;
  decidedBy: 'status' | 'network' | 'heuristics' | 'similarity' | 'classifier' | 'degraded';
  signals: string[];           // e.g. ['soft404-title', 'redirect-to-root']
  similarity?: number;         // 0..1, present when tier 2 ran
  snapshot?: ArchiveSnapshot;
  needsHuman: boolean;
}

export interface ArchiveSnapshot {
  url: string;                 // https://web.archive.org/web/<ts>/<original>
  rawUrl: string;              // ...<ts>id_/<original>, used for content comparison
  timestamp: string;           // ISO 8601
  status: number;
  page?: PageContent;
}

export interface Candidate {
  url: string;                 // normalized
  source: 'redirect' | 'search' | 'archive';
  searchRank?: number;
  page?: PageContent;
}

export interface Evidence {
  oldQuote: string;
  newQuote: string;
  oldSource: { kind: 'archive' | 'source-file'; url?: string; timestamp?: string };
  newSource: { url: string };
  grounded: boolean;           // both quotes located in their source text
}

export interface Verification {
  candidate: Candidate;
  score: number;               // 0..1
  reason: string;
  evidence?: Evidence;
  rejected?: 'below-threshold' | 'ungrounded-quote' | 'malformed-response' | 'no-evidence';
  anchor?: { original: string; repaired?: string; lost: boolean };
  tokens?: { prompt: number; completion: number };
}

export interface Edit {
  file: string;
  byteStart: number;
  byteEnd: number;
  expected: string;            // original URL bytes; the staleness guard
  replacement: string;
}

export interface LinkResult {
  link: LinkRef;
  probe?: ProbeResult;
  condition: Condition;
  candidates: Candidate[];
  verifications: Verification[];
  best?: Verification;
  verdict: Verdict;
  action: Action;
  edit?: Edit;                 // present iff action === 'replace'
  needsHuman: boolean;
}
```

## Stage designs

### 1. Exhume

**Markdown and MDX** go through `unified` with `remark-parse`, `remark-gfm` and (for `.mdx`)
`remark-mdx`. The mdast visitor collects `link`, `linkReference`/`definition`, and text nodes for
bare URLs. Every node carries `position.start.offset` / `position.end.offset`, which is where the
byte spans come from — and because `code` and `inlineCode` are distinct node types that the visitor
simply does not visit, requirement 1.5 ("never report a link inside a fenced code block") holds by
construction rather than by regex gymnastics. That is the main reason to use an AST here instead of
line-based regex.

One subtlety: mdast offsets are UTF-16 character offsets, not byte offsets. The extractor converts
by keeping a precomputed prefix-sum index of byte lengths per line for each file. This conversion is
where the CRLF and emoji cases get handled, so it gets its own unit tests.

For an inline link `[text](https://example.com/a#b "title")`, the span must cover only the URL —
not the brackets, not the title. The extractor re-scans the node's raw slice to locate the
destination precisely, because mdast gives the destination as a decoded string, not a span.

**HTML** uses `htmlparser2` with `withStartIndices`/`withEndIndices` to capture attribute
positions, extracting `a[href]`, `link[href]`, `img[src]`, `script[src]`, `iframe[src]`.

**Code comments** use a small per-language tokenizer rather than a full parser. The tokenizer walks
the file tracking three states — code, string literal, comment — with per-language delimiters:
C-like (`//`, `/* */`, `"`, `'`, backtick), Python (`#`, `"""`, `'''`), Go and Rust and Java (C-like),
and a generic `#`-comment fallback. URLs are harvested only in the comment state, which satisfies
requirement 1.6. This will mis-handle exotic cases (raw strings, nested block comments in Rust); the
limitation is documented and the mode is off by default.

### 2. Probe

`GET`, not `HEAD`: the brief calls for it and the autopsy needs the body anyway, and a meaningful
minority of servers mishandle `HEAD`. The body stream is read through a counting transform that
aborts past the cap, so a 2 GB file does not sink a scan.

Error classification maps `undici` and Node error codes onto the six categories:
`ENOTFOUND`/`EAI_AGAIN` → `dns`; `CERT_*`/`ERR_TLS_*`/`EPROTO` → `tls`; `UND_ERR_HEADERS_TIMEOUT`
/`UND_ERR_BODY_TIMEOUT`/`ETIMEDOUT` → `timeout`; `ECONNRESET`/`ECONNREFUSED` → `connection-reset`;
redirect cap → `too-many-redirects`; everything else → `other`.

The limiter is a per-host token bucket plus a global semaphore. Hosts are keyed by registrable
domain, not full hostname, so `docs.example.com` and `www.example.com` share a budget.

### 3. Autopsy

Tier 1 signal detectors, each a pure `(ProbeResult, LinkRef) => boolean`:

| Signal | Detection |
|---|---|
| `soft404-title` | Title or first h1 matches a phrase set: not found, 404, page doesn't exist, no longer available, has moved, gone |
| `soft404-status-text` | Body contains an error-page marker near the top of main text |
| `redirect-to-root` | Original path depth ≥ 1, final URL path is `/` or empty, same host |
| `parked-provider` | Final URL host or page markup matches a parking fingerprint list: sedoparking, bodis, afternic, dan.com, hugedomains, parkingcrew, above.com, "this domain is for sale", "buy this domain" |
| `thin-content` | `page.textLength` below floor (default 200 chars) |
| `ad-only` | Main text is ≥ 80% link text and under 500 chars |

Tier 1 concludes confidently only in two directions: a parking signal → `PARKED`; a soft-404 or
redirect-to-root signal combined with thin or ad-only content → `SOFT_404`. A single weak signal
escalates rather than deciding, because a legitimate short page that happens to say "404" in its
changelog should not be condemned.

Tier 2 picks the snapshot via the CDX server, then fetches it with the `id_` modifier
(`https://web.archive.org/web/<timestamp>id_/<url>`) so the comparison sees the original bytes
without the Wayback toolbar injected into the DOM. Using the plain snapshot URL here would compare
archive chrome against live page chrome and skew every score — this detail matters more than it
looks.

Similarity is a composite:

```
similarity = 0.6 * jaccard(shingles(oldText, 5), shingles(newText, 5))
           + 0.25 * tokenOverlap(oldTitle, newTitle)
           + 0.15 * setOverlap(oldHeadings, newHeadings)
```

Weights and the two thresholds live in config because they need calibrating against the seeded
demo repo. Calibration is an explicit task, not an afterthought.

Tier 3 sends title, headings and a 1500-character excerpt of each side to the classifier model and
asks for one label. It is called only in the ambiguous band, which is what keeps per-scan cost in
the cents.

### 4. Resurrect

Query construction, in priority order: archived `title`, then the first two archived headings, then
the link text. The host is tried first via the search provider's domain restriction, then the
registrable domain, then unrestricted. Known-migration heuristics add a candidate for free: if the
host has a documented successor pattern in a small built-in table (e.g. a `docs.` subdomain move, a
GitHub org rename surfaced by the redirect chain), it is added as a `redirect`-source candidate.

Candidates are capped at 5 and fetched via Tavily extract, falling back to the normal probe path.

### 5. Verify

The prompt is deliberately adversarial: the model is told that its job is to find a reason to
*reject* the candidate, and that it must quote verbatim from both texts. Structured output uses
`response_format: { type: 'json_schema' }` with a strict schema; on a provider that rejects it, the
client falls back to `json_object` plus Zod validation and one repair retry.

```ts
const VerifySchema = z.object({
  match_score: z.number().min(0).max(1),
  reason: z.string().max(400),
  old_quote: z.string().min(20).max(300),
  new_quote: z.string().min(20).max(300),
  same_topic_different_content: z.boolean(),
  anchor_suggestion: z.string().optional(),
});
```

**Quote grounding** is the gate that makes the evidence claim real. Both quotes are normalized
(collapse whitespace, casefold, strip punctuation runs) and searched in their normalized source
text. A miss sets `rejected: 'ungrounded-quote'` and the candidate is discarded regardless of score.
Grounding runs locally, costs nothing, and catches the exact failure mode that makes AI link-fixing
untrustworthy.

Anchor repair uses `github-slugger` as the oracle — the same library GitHub's own tooling behaviour
is modelled on — rather than a hand-rolled slug function. The repair tries: exact slug match on the
new page's headings; then case-insensitive match; then the model's `anchor_suggestion` validated
against the real heading slugs. Anything else drops the fragment and sets `anchor.lost`.

### 6. Adjudicate

A pure function implementing the precedence table, with no I/O:

```ts
export function adjudicate(
  condition: Condition,
  best: Verification | undefined,
  config: ResolvedConfig,
): { verdict: Verdict; action: Action } 
```

"Dead or zombie" means `cause !== 'OK'`. Rule 2's "good snapshot" requires: status 200, HTML mime
type, text length above the thin-content floor, and the snapshot itself passing tier-1 heuristics —
an archived 404 is not an archive.

### 7. Deliver

Edits are applied by sorting per file in descending `byteStart` and splicing buffers. The `expected`
field is the idempotency and safety mechanism: before splicing, the applier compares the bytes
currently at the span against `expected`. Equal → apply. Equal to `replacement` instead → already
applied, skip silently. Neither → stale, skip with a warning. That single check delivers
requirements 8.2, 8.5 and most of 8.4 without any file-level hashing.

Overlap detection runs before any write and rejects the whole set for that file, because a partial
apply is worse than no apply.

The unified diff emitter works off the same in-memory buffers, so `--dry-run` and the dashboard's
patch download share one code path with `fix`.

## Provider interfaces

```ts
export interface HttpClient {
  get(url: string, opts?: { timeoutMs?: number; maxBytes?: number }): Promise<ProbeResult>;
}

export interface Archive {
  nearest(url: string, when?: Date): Promise<ArchiveSnapshot | null>;
  fetchSnapshot(snapshot: ArchiveSnapshot): Promise<PageContent | null>;
  save?(url: string): Promise<{ snapshotUrl: string } | null>;   // ward
}

export interface Search {
  search(q: string, opts: { includeDomains?: string[]; maxResults: number }): Promise<SearchHit[]>;
  extract(urls: string[]): Promise<Record<string, PageContent>>;
}

export interface Llm {
  classify(input: ClassifyInput): Promise<ClassifyOutput>;
  verify(input: VerifyInput): Promise<VerifyOutput>;
  listModels(): Promise<string[]>;
}

export interface FileSystem {            // lets the web app read from the GitHub API
  list(globs: string[]): Promise<string[]>;
  read(path: string): Promise<Buffer>;
  write?(path: string, data: Buffer): Promise<void>;
}

export interface Git {                   // lets the web app use the GraphQL blame API
  blame(path: string): Promise<Map<number, { date: string; sha: string }>>;
  changedFiles(base: string): Promise<string[]>;
  isShallow(): Promise<boolean>;
}
```

`Archive`, `Search` and `Llm` are each wrapped by `cache.ts`, a decorator that hashes
`(providerName, method, canonicalized args, dateBucket)` into a cache key and stores JSON under
`.necro-cache/<prefix>/<hash>.json`. In `replay` mode a miss throws, which is how the test suite runs
the full pipeline offline against recorded fixtures.

## Error handling

| Failure | Response |
|---|---|
| One file fails to parse | Record `fileErrors[]`, continue |
| One link fails at any stage | Record stage error on that `LinkResult`, verdict `UNRESOLVED`, `needsHuman`, continue |
| Provider 5xx / 429 | Retry with backoff; on exhaustion, degrade that stage for that link |
| Invalid model ID | Fail the run at startup with the available ID list |
| Missing `NEBIUS_API_KEY` | Degraded mode, stated in report |
| Missing `TAVILY_API_KEY` | Degraded discovery, stated in report |
| Budget or link cap reached | Clean finish, remaining links marked `skipped` |
| Overlapping edits in a file | Reject that file's edits, report it, apply other files |

A single link can never abort a run. Every error is attached to the record it belongs to and
surfaces in both reports. All errors pass through a redactor that strips anything matching the
configured key patterns.

## Testing strategy

**Property-based (fast-check)** — the six properties from the brief, each mapped to a test file:

| Property | File | Generator |
|---|---|---|
| `normalize(normalize(u)) === normalize(u)` | `url/normalize.prop.test.ts` | arbitrary URL parts incl. unicode hosts, odd percent-encoding, empty query/fragment |
| Applying edits changes only URL bytes; inverting restores the file | `deliver/edits.prop.test.ts` | arbitrary file buffer + non-overlapping spans |
| Applying a patch twice === once | `deliver/edits.prop.test.ts` | same |
| No link reported inside a fenced code block | `exhume/markdown.prop.test.ts` | arbitrary markdown assembled from prose/link/fence fragments |
| Anchor slugs match GitHub's | `url/anchor.prop.test.ts` | arbitrary headings incl. unicode, duplicates, punctuation; oracle = `github-slugger` |
| Each verdict maps to one action; `ALIVE` never yields a change | `adjudicate/verdict.prop.test.ts` | arbitrary `Condition` × `Verification` |

**Decision-table tests.** The tier-1 and tier-2 autopsy table and the adjudication precedence are
both covered by exhaustive table tests, not examples, so a threshold change shows up as a specific
failed row.

**Fixture replay.** Recorded provider responses in `fixtures/cache/` drive the full pipeline in
`replay` cache mode. No test touches the network.

**Seeded haunted repo.** `fixtures/haunted-repo/` contains a realistic docs tree with planted cases
and `expected.json` listing the expected `(verdict, cause)` per link:

| Planted case | Expected |
|---|---|
| Healthy link, unchanged since added | `ALIVE` / `OK` |
| Hard 404 with a findable successor on the same host | `RESURRECTED` / `HTTP_ERROR` |
| Dead host, DNS failure, good 2019 snapshot | `ARCHIVED` / `NETWORK_ERROR` |
| 200 OK parked domain | `ARCHIVED` / `PARKED` (and `PARKED` with `archiveFallback: false`) |
| 200 OK soft 404 | `ARCHIVED` / `SOFT_404` |
| 200 OK, same URL, now a marketing page | `DRIFTED` / `CONTENT_DRIFT` |
| Dead, nothing in the archive, no search hit | `UNRESOLVED` / `HTTP_ERROR` |
| Link with a `#section` that was renamed on the successor | `RESURRECTED` with repaired anchor |
| URL inside a fenced code block | not extracted |
| URL in a `//` comment in a `.ts` file | extracted only with code-comment mode on |

One integration test asserts the whole table. That test is the project's definition of done and
directly covers the brief's first success criterion.

**Negative evidence test.** A fixture where the verifier returns a plausible but fabricated quote
must produce no fix and `rejected: 'ungrounded-quote'`. This covers the second success criterion.

## Open calibration items

These need real data and are deliberately left as config, not constants:

- Similarity weights and the `aliveAt` / `driftedBelow` thresholds.
- The parking-provider fingerprint list, which decays and needs a refresh pass before the demo.
- The default confidence threshold of 0.85, to be tuned against the planted cases so that no planted
  `DRIFTED` case is auto-fixed.
