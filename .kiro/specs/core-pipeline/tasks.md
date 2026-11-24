# Core pipeline — tasks

Order matters: the cache layer (task 3) comes before any provider work so that every later task can
record fixtures as it goes, and the seeded haunted repo (task 5) comes before the stages it
validates so each stage has a target to hit.

- [ ] 1. Workspace scaffolding
  - pnpm workspace with `packages/core`, `apps/cli`, `apps/web`, `apps/action`, `apps/mcp`
  - TypeScript project references, strict mode, `node20` target, ESM
  - Vitest + fast-check, ESLint, Prettier, MIT license, `.kiro/` committed
  - CI workflow: typecheck, lint, test on push and PR
  - _Requirements: all (foundation)_

- [ ] 2. Types, verdict vocabulary and config
- [ ] 2.1 Write `model/types.ts` and `model/verdict.ts` with `Cause`, `Verdict`, `Action`, `ACTION_FOR`
  - _Requirements: verdict vocabulary, 8.8_
- [ ] 2.2 Write the Zod config schema with every default from the requirements, and the file → env → options loader
  - Credentials read from env only; reject keys found in a config file
  - _Requirements: 10.1, 10.2_
- [ ] 2.3 Write the credential redactor and wire it into a shared logger
  - _Requirements: 11.4_

- [ ] 3. Content-addressed provider cache
- [ ] 3.1 Implement `providers/cache.ts` as a decorator: key = hash(provider, method, canonical args, date bucket); JSON under `.necro-cache/`
  - _Requirements: 10.7_
- [ ] 3.2 Add `live`, `prefer-cache` and `replay` modes, where `replay` throws on a miss
  - _Requirements: 10.8_
- [ ] 3.3 Unit tests for key stability across argument ordering and for replay-miss failure

- [ ] 4. URL normalization and anchors
- [ ] 4.1 Implement `url/normalize.ts` per requirement 2.1–2.3, splitting fragment from document URL
  - _Requirements: 2.1, 2.2, 2.3, 2.5, 2.6_
- [ ] 4.2 **Property test: idempotence.** `normalize(normalize(u)) === normalize(u)` over generated URLs including unicode hosts, mixed-case percent-encoding, default ports, empty query and fragment
  - _Requirements: 2.4_
- [ ] 4.3 Implement `url/anchor.ts` over `github-slugger`, plus heading-slug extraction from `PageContent`
  - _Requirements: 7.5_
- [ ] 4.4 **Property test: anchor slugs match GitHub.** Oracle-compare against `github-slugger` over generated headings with unicode, punctuation and duplicates
  - _Requirements: 7.5_

- [ ] 5. Seeded haunted demo repo
- [ ] 5.1 Build `fixtures/haunted-repo/` as a realistic docs tree covering all ten planted cases in the design's table, with real git history so blame dates are meaningful
  - _Requirements: success criteria_
- [ ] 5.2 Write `fixtures/haunted-repo/expected.json` with the expected `(verdict, cause)` per link
- [ ] 5.3 Record provider fixtures for every URL in the repo into `fixtures/cache/`

- [ ] 6. Exhume
- [ ] 6.1 Implement `exhume/discover.ts`: extension-based walk, gitignore, include and exclude globs
  - _Requirements: 1.1, 1.2_
- [ ] 6.2 Implement the UTF-16-offset-to-byte-offset index, with tests for CRLF, BOM and multi-byte characters
  - _Requirements: 1.3_
- [ ] 6.3 Implement `exhume/markdown.ts` on remark + remark-gfm + remark-mdx; precise destination spans for inline, reference, autolink and bare URLs
  - _Requirements: 1.3, 1.4_
- [ ] 6.4 **Property test: no link inside a fenced or inline code block** is reported as a doc link
  - _Requirements: 1.5_
- [ ] 6.5 Implement `exhume/html.ts` on htmlparser2 with attribute indices
  - _Requirements: 1.4_
- [ ] 6.6 Implement `exhume/comments.ts`: state-machine tokenizer for C-like, Python and generic `#` families; harvest URLs only in comment state
  - _Requirements: 1.6_
- [ ] 6.7 Implement `exhume/filter.ts`: scheme, local-host, private-IP, template-marker and relative-link exclusions
  - _Requirements: 1.7, 1.8_
- [ ] 6.8 Per-file error isolation
  - _Requirements: 1.9_
- [ ] 6.9 Implement `exhume/blame.ts`: one `git blame --porcelain` pass per file, line-indexed; shallow-clone warning; `changedOnly` via `git diff --name-only`
  - _Requirements: 3.1, 3.2, 3.4, 3.5_
- [ ] 6.10 Verify extraction against the haunted repo: correct count, correct spans, code-block and code-comment cases behaving per config

- [ ] 7. Probe
- [ ] 7.1 Implement `probe/client.ts` on undici: GET, redirect chain capture, body cap with stream abort, main-content parse
  - _Requirements: 4.1, 4.2_
- [ ] 7.2 Implement the error classifier mapping Node and undici codes to the six categories, with a table test
  - _Requirements: 4.3_
- [ ] 7.3 Implement `probe/limiter.ts`: per-registrable-domain token bucket plus global semaphore
  - _Requirements: 4.4_
- [ ] 7.4 Implement `probe/retry.ts`: exponential backoff with jitter, `Retry-After` support, 3 attempts
  - _Requirements: 4.5_
- [ ] 7.5 Set the descriptive User-Agent; wrap the client in the cache with a 24 h TTL
  - _Requirements: 4.6, 4.7_
- [ ] 7.6 Implement `text/extract-main.ts`: title, h1–h3, boilerplate-stripped main text capped at 20k chars

- [ ] 8. Wayback archive provider
- [ ] 8.1 Implement `providers/archive-wayback.ts`: CDX query filtered to status 200 and HTML, nearest-timestamp selection relative to the link's added date, availability-API fallback
  - _Requirements: 5.3, 3.3_
- [ ] 8.2 Fetch snapshot content through the `id_` modifier so archive chrome is excluded from comparison
  - _Requirements: 5.3_
- [ ] 8.3 Implement the "good snapshot" predicate: 200, HTML, above the thin-content floor, passes tier-1 heuristics
  - _Requirements: verdict precedence rule 2_

- [ ] 9. Autopsy
- [ ] 9.1 Implement the six tier-1 signal detectors in `autopsy/heuristics.ts`, each a pure function
  - _Requirements: 5.2_
- [ ] 9.2 Implement `autopsy/similarity.ts`: 5-gram shingle Jaccard, title token overlap, heading set overlap, composite with configurable weights
  - _Requirements: 5.3_
- [ ] 9.3 Implement the tier escalation and decision table in `autopsy/index.ts`, recording `decidedBy`, `signals` and `similarity`
  - _Requirements: 5.1, 5.4, 5.7, 5.8_
- [ ] 9.4 Exhaustive decision-table test over signal combinations and similarity bands
  - _Requirements: 5.8_
- [ ] 9.5 Implement the degraded path: no LLM and inconclusive → `CONTENT_DRIFT` with `needsHuman`
  - _Requirements: 5.6, 10.5_

- [ ] 10. LLM provider
- [ ] 10.1 Implement `providers/llm-openai.ts` against the OpenAI SDK with base URL `https://api.tokenfactory.nebius.com/v1/`
  - _Requirements: 10.3_
- [ ] 10.2 Validate both model IDs against `GET /v1/models` on first use; on mismatch fail with the available IDs listed
  - _Requirements: 10.4_
- [ ] 10.3 Implement structured output with `json_schema`, falling back to `json_object` plus Zod and one repair retry
  - _Requirements: 7.1, 7.6_
- [ ] 10.4 Implement `classify()` with the small model and the five-label output
  - _Requirements: 5.5_
- [ ] 10.5 Record per-call token usage
  - _Requirements: 7.8, 9.5_

- [ ] 11. Resurrect
- [ ] 11.1 Implement `providers/search-tavily.ts`: search with domain restriction and extract, both cached
  - _Requirements: 6.2, 6.4_
- [ ] 11.2 Implement `resurrect/query.ts`: query from archived title and headings, falling back to link text and enclosing heading
  - _Requirements: 6.2, 6.6_
- [ ] 11.3 Implement `resurrect/candidates.ts`: three sources, host-restricted then unrestricted search, dedupe, exclude original, cap at 5
  - _Requirements: 6.1, 6.3_
- [ ] 11.4 Implement the degraded path when no search key is present
  - _Requirements: 6.5, 10.6_

- [ ] 12. Verify
- [ ] 12.1 Write the adversarial verifier prompt and its JSON schema
  - _Requirements: 7.1_
- [ ] 12.2 Implement `verify/ground.ts`: normalized quote lookup in both source texts
  - _Requirements: 7.2_
- [ ] 12.3 Implement candidate scoring and selection with the threshold and rejection reasons
  - _Requirements: 7.3, 7.4_
- [ ] 12.4 Implement anchor repair: exact slug, then case-insensitive, then validated model suggestion, else drop and flag as lost
  - _Requirements: 7.5_
- [ ] 12.5 Implement the no-LLM path: similarity-only score capped below the confidence threshold, routed to "needs a human"
  - _Requirements: 7.7_
- [ ] 12.6 **Negative evidence test:** a fabricated quote produces no fix and `rejected: 'ungrounded-quote'`
  - _Requirements: 7.2, 7.3, success criteria_

- [ ] 13. Adjudicate
- [ ] 13.1 Implement the pure precedence function, including the `archiveFallback` switch
  - _Requirements: verdict precedence_
- [ ] 13.2 **Property test: totality and `ALIVE` never produces a change.** Every `(Condition, Verification)` pair yields exactly one verdict and one action; `ALIVE` implies no edit
  - _Requirements: 8.8_

- [ ] 14. Deliver
- [ ] 14.1 Implement `deliver/edits.ts`: edit construction from `LinkResult`, descending-order splice, `expected`-bytes staleness guard, overlap rejection
  - _Requirements: 8.1, 8.2, 8.3_
- [ ] 14.2 **Property tests:** only URL bytes change; inverting restores the file byte for byte; applying twice equals applying once
  - _Requirements: 8.4, 8.5, 8.6_
- [ ] 14.3 Implement `deliver/diff.ts`: unified diff from in-memory buffers, no working-tree writes
  - _Requirements: 8.7, 11.3_
- [ ] 14.4 Implement the schema-versioned JSON report, with secrets and raw bodies excluded
  - _Requirements: 9.1, 9.4_
- [ ] 14.5 Implement the Markdown report: summary table, section per verdict, evidence block per fix with both quotes and the archive timestamp, separate "needs a human" section
  - _Requirements: 9.2, 9.3_
- [ ] 14.6 Add per-stage counts, elapsed time, cache hit rate and token totals to both reports
  - _Requirements: 9.5_

- [ ] 15. Orchestration
- [ ] 15.1 Implement `scan()`: stage sequencing, bounded per-link concurrency, provider injection
  - _Requirements: all_
- [ ] 15.2 Emit structured progress events per stage per link
  - _Requirements: 11.1_
- [ ] 15.3 Enforce the max-links cap and wall-clock budget with a clean partial finish
  - _Requirements: 11.2_

- [ ] 16. Calibration and acceptance
- [ ] 16.1 Calibrate similarity weights, `aliveAt`, `driftedBelow` and the confidence threshold against the haunted repo until no planted `DRIFTED` case is auto-fixed
  - _Requirements: open calibration items_
- [ ] 16.2 Refresh the parking-provider fingerprint list against live examples
- [ ] 16.3 **Acceptance test:** full pipeline in replay mode over the haunted repo matches `expected.json` for every planted case
  - _Requirements: success criteria_
- [ ] 16.4 **Degraded-mode acceptance test:** full run with no API keys completes, states degraded mode in the report, and emits no auto-fix

- [ ] 17. Ward (stretch)
- [ ] 17.1 Implement `Archive.save()` against Save Page Now with the documented rate ceiling and no retry on quota rejection
  - _Requirements: 12.1, 12.3_
- [ ] 17.2 Skip cleanly with a note when archive credentials are absent
  - _Requirements: 12.2_
