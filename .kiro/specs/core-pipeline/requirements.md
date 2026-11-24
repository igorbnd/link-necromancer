# Core pipeline — requirements

## Introduction

`packages/core` is the engine behind every Link Necromancer surface. It takes a directory of files
and returns, for each outbound link, a verdict, the evidence behind that verdict, and (where a fix
is warranted) a byte-exact edit that replaces the URL and nothing else.

The pipeline has seven stages: **exhume** (extract links), **probe** (fetch them), **autopsy**
(detect zombies), **resurrect** (find candidate successors), **verify** (prove a candidate is the
same content), **deliver** (reports and patches), and **ward** (archive new links, stretch).

Two properties separate this from a link checker and drive most of the requirements below:

1. **No fix without grounded evidence.** Every applied fix carries a quote from the old page and a
   quote from the new page, and both quotes are verified to exist in their source text before the
   fix is emitted. A model that invents a quote gets its fix rejected.
2. **Byte-exact edits.** A fix rewrites the URL span and leaves every other byte of the file
   untouched, including line endings, trailing whitespace and the link text.

The library degrades rather than fails: with no LLM key it runs heuristics and archive comparison
only; with no search key it falls back to redirect targets and archive snapshots.

## Verdict vocabulary

Two orthogonal fields travel with every link. Keeping them separate is what lets the dashboard say
"this returned 200 OK and is a parked domain" while the fixer says "replace it with the 2019
snapshot".

### `cause` — why the link is broken

| Cause | Meaning |
|---|---|
| `OK` | Reachable and content still matches |
| `HTTP_ERROR` | 4xx or 5xx response |
| `NETWORK_ERROR` | DNS failure, TLS failure, timeout, connection reset, redirect loop |
| `PARKED` | Domain is parked or listed for sale |
| `SOFT_404` | Returns 200 but is an error page, a "not found" page, or a redirect to the site root |
| `CONTENT_DRIFT` | Reachable, not an error page, but materially different content from when the link was added |

### `verdict` — what to do about it

| Verdict | Meaning | Action |
|---|---|---|
| `ALIVE` | Reachable, content matches what it was when the link was added | none |
| `RESURRECTED` | Dead or zombie, live successor found and verified | replace the URL |
| `ARCHIVED` | Dead or zombie, no verified successor, good snapshot exists | replace with the snapshot URL |
| `DRIFTED` | Reachable but materially different content | flag for a human; suggest a successor if one was found |
| `PARKED` | Parked domain, nothing to replace it with | flag for a human |
| `SOFT_404` | Soft 404, nothing to replace it with | flag for a human |
| `UNRESOLVED` | Dead, no successor and no usable archive | flag for a human |

### Verdict precedence

The brief lists verdicts as a flat set, which leaves the parked-domain-with-a-good-snapshot case
ambiguous. This spec resolves it with a strict precedence, evaluated top to bottom:

1. Verified successor at or above the confidence threshold, and the link was dead or a zombie → `RESURRECTED`
2. Link was dead or a zombie, archive fallback enabled, good snapshot available → `ARCHIVED`
3. `cause` is `PARKED` → `PARKED`
4. `cause` is `SOFT_404` → `SOFT_404`
5. `cause` is `CONTENT_DRIFT` → `DRIFTED`
6. `cause` is `HTTP_ERROR` or `NETWORK_ERROR` → `UNRESOLVED`
7. Otherwise → `ALIVE`

So a parked domain with a good 2019 snapshot gets `verdict: ARCHIVED, cause: PARKED`. The fix is
the snapshot; the display still shows that the page was detected as parked. Setting
`archiveFallback: false` in config skips rule 2, which is how the `PARKED` and `SOFT_404` verdicts
become reachable.

---

## Requirements

### 1. Link extraction (exhume)

**User story:** As a maintainer, I want every outbound link in my docs and code found with its
exact position, so that fixes can be applied surgically and reviewed line by line.

#### Acceptance criteria

1.1. WHEN given a directory, the system SHALL discover files by extension: `.md`, `.markdown`, `.mdx`, `.html`, `.htm`, and — when code-comment mode is enabled — `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`, `.rs`, `.java`.

1.2. THE system SHALL honour `.gitignore` by default, plus user-supplied include and exclude globs.

1.3. FOR each extracted link, the system SHALL record: repo-relative file path, 1-based line, 1-based column, byte-offset start and end of the URL token, the raw URL exactly as written, the normalized URL, the fragment, the link text, and the syntactic context.

1.4. WHEN parsing Markdown and MDX, the system SHALL extract inline links, reference definitions, autolinks, bare URLs in text, and `href`/`src` attributes in embedded HTML.

1.5. WHEN parsing Markdown and MDX, the system SHALL NOT report any URL inside a fenced code block, an indented code block, or inline code as a document link, unless code-comment mode is enabled AND the enclosing file is a source file.

1.6. WHEN code-comment mode is enabled, the system SHALL extract URLs only from comment tokens, and SHALL NOT extract URLs from string literals.

1.7. THE system SHALL exclude from probing: non-HTTP schemes (`mailto:`, `tel:`, `javascript:`, `data:`, `ftp:`), `localhost` and private or loopback IP literals, and URLs containing template markers (`{`, `}`, `$`, `<`, `>`, `%s`).

1.8. THE system SHALL NOT report relative or intra-repository links. (Non-goal.)

1.9. WHEN a file cannot be parsed, the system SHALL record a per-file error and continue with the remaining files.

### 2. URL normalization

**User story:** As a developer, I want URLs normalized consistently so the same link written two
ways is probed once and cached once.

#### Acceptance criteria

2.1. THE system SHALL lowercase the scheme and host, convert internationalized hosts to punycode, drop the default port for the scheme, resolve dot segments, canonicalize percent-encoding to uppercase hex, decode percent-encoded unreserved characters, and drop an empty query or empty fragment.

2.2. THE system SHALL preserve path, query and fragment case.

2.3. THE system SHALL strip configured tracking parameters (default: `utm_*`, `fbclid`, `gclid`, `mc_cid`, `mc_eid`, `ref`) and SHALL NOT reorder the remaining query parameters.

2.4. `normalize(normalize(u))` SHALL equal `normalize(u)` for every input `u`. (Property test.)

2.5. THE system SHALL store the fragment separately from the normalized document URL, and SHALL deduplicate probe work by document URL.

2.6. WHEN a raw URL fails to parse, the system SHALL mark it unprobeable with a parse error rather than throwing.

### 3. Link age from git history

**User story:** As a maintainer, I want to know when each link was added, so the archive comparison
uses the page as it looked when someone vouched for it.

#### Acceptance criteria

3.1. THE system SHALL obtain the author date and commit SHA of the line each link sits on, using one `git blame --porcelain` pass per file indexed by line number.

3.2. WHEN the repository is not a git repository, the file is untracked, or blame fails, the system SHALL leave the added date unset and continue.

3.3. WHEN the added date is unset, the autopsy stage SHALL use the oldest available archive snapshot instead.

3.4. WHEN the clone is shallow, the system SHALL emit one warning that link dates may be truncated to the shallow boundary.

3.5. WHEN `changedOnly` is set with a base ref, the system SHALL restrict extraction to files reported by `git diff --name-only <base>...HEAD`.

### 4. Probing

**User story:** As a maintainer, I want links fetched politely and classified precisely, so a slow
server is not reported as a dead link.

#### Acceptance criteria

4.1. THE system SHALL issue a `GET` request per unique document URL, following up to a configured maximum of redirects (default 10), and SHALL record the full redirect chain and final URL.

4.2. THE system SHALL read at most a configured byte cap from each response body (default 512 KB) and SHALL abort the body stream past the cap.

4.3. THE system SHALL classify failures distinctly as `dns`, `tls`, `timeout`, `connection-reset`, `too-many-redirects`, or `other`, and SHALL NOT collapse them into a single error type.

4.4. THE system SHALL apply a per-host concurrency limit and minimum request interval (defaults: 2 concurrent, 500 ms apart) and a global concurrency limit (default 16).

4.5. WHEN a response is 429 or 5xx or the request fails at the network level, the system SHALL retry up to 3 times with exponential backoff and jitter, and SHALL honour a `Retry-After` header when present.

4.6. THE system SHALL send a descriptive `User-Agent` identifying the tool and a contact URL.

4.7. THE system SHALL cache probe results keyed by normalized URL with a configurable TTL (default 24 h).

4.8. THE system SHALL NOT follow links to other pages on the target site. (Non-goal: crawling.)

### 5. Zombie detection (autopsy)

**User story:** As a maintainer, I want pages that return 200 OK but are no longer the content I
linked to flagged, because those are the links no checker catches.

#### Acceptance criteria

5.1. THE system SHALL evaluate reachable links in escalating tiers and SHALL stop at the first tier that reaches a confident conclusion.

5.2. **Tier 1 (heuristics, no network).** THE system SHALL detect: soft-404 title and heading phrases; a redirect from a path of depth ≥ 1 to the site root; known domain-parking fingerprints; and a main-content length below a configured floor.

5.3. **Tier 2 (archive comparison).** WHEN tier 1 is inconclusive, the system SHALL fetch the archive snapshot nearest the link's added date and compute a similarity score between the snapshot's main text and the live page's main text, together with title and heading overlap.

5.4. WHEN similarity is at or above `aliveAt` (default 0.65), the system SHALL conclude `cause: OK`. WHEN similarity is at or below `driftedBelow` (default 0.35), it SHALL conclude `cause: CONTENT_DRIFT`. Between the two it SHALL escalate.

5.5. **Tier 3 (LLM classifier).** WHEN tiers 1 and 2 are inconclusive AND an LLM is configured, the system SHALL ask the classifier model to choose one of `same_content`, `different_content`, `error_page`, `parked`, `unclear`, and SHALL map `unclear` to `CONTENT_DRIFT` flagged for a human.

5.6. WHEN no LLM is configured and all cheaper tiers are inconclusive, the system SHALL assign `cause: CONTENT_DRIFT`, set `needsHuman`, and record the reason as insufficient automated confidence.

5.7. THE system SHALL record, for every autopsy, which tier decided, the similarity score, and the signals that fired.

5.8. GIVEN the same inputs, the tier-1 and tier-2 decision table SHALL be deterministic.

### 6. Candidate discovery (resurrect)

**User story:** As a maintainer, I want the tool to find where the content actually moved to, not
just hand me an archive link.

#### Acceptance criteria

6.1. FOR links that are dead or classified as zombies, the system SHALL gather candidates from: the final redirect target (when it differs from the original and is not the site root); a web search built from the archived page's title and headings; and the archive snapshot itself.

6.2. THE search query SHALL be built from the archived title and top headings, and SHALL be run first restricted to the original host and known related hosts, then unrestricted if that returns nothing usable.

6.3. THE system SHALL deduplicate candidates by normalized URL, exclude the original URL, and cap the set at a configured maximum (default 5).

6.4. THE system SHALL fetch candidate page content via the search provider's extract endpoint, falling back to a direct probe.

6.5. WHEN no search provider is configured, the system SHALL use only the redirect target and the archive snapshot, and SHALL record that discovery ran degraded.

6.6. WHEN the archived page is unavailable, the system SHALL build the query from the link text and surrounding heading in the source file instead, and SHALL mark the resulting evidence as weaker.

### 7. Verification

**User story:** As a reviewer, I want proof that a proposed replacement is the same content, in the
form of quotes I can check myself.

#### Acceptance criteria

7.1. FOR each candidate, the verifier model SHALL return structured JSON containing a match score from 0 to 1, a short reason, a quote from the old content, and a quote from the new content.

7.2. THE system SHALL verify that each returned quote occurs in its source text under whitespace-and-case-normalized comparison, and SHALL reject the candidate when either quote cannot be located.

7.3. THE system SHALL NOT emit a fix when the match score is below the confidence threshold (default 0.85), when either quote is missing, or when quote grounding fails.

7.4. THE system SHALL select the highest-scoring surviving candidate and SHALL record the scores and reasons for the rejected ones.

7.5. WHEN the original link had a fragment, the system SHALL attempt to map it to a heading on the replacement page using GitHub-compatible slug rules, SHALL attach the repaired fragment to the replacement URL on success, and SHALL drop the fragment and note the loss on failure.

7.6. WHEN the model returns malformed JSON, the system SHALL retry once with a repair instruction and SHALL treat a second failure as an unverified candidate.

7.7. WHEN no LLM is configured, the system SHALL verify by archive similarity alone, SHALL cap the resulting score at the `aliveAt` threshold so it cannot clear the default confidence threshold, and SHALL route the candidate to the "needs a human" section as a suggestion.

7.8. THE system SHALL record token usage per call so cost is visible in the report.

### 8. Patching

**User story:** As a maintainer, I want fixes applied to the URL and nothing else, so review is
trivial and nothing else in my file moves.

#### Acceptance criteria

8.1. AN edit SHALL consist of a file path, a byte span, the expected original bytes at that span, and the replacement bytes.

8.2. WHEN applying edits, the system SHALL verify the expected original bytes still occupy the span, and SHALL skip the edit with an "already applied or stale" note when they do not.

8.3. THE system SHALL apply edits per file in descending byte order, and SHALL reject an edit set containing overlapping spans.

8.4. APPLYING an edit set SHALL change only the bytes inside the edit spans. Every other byte of the file, including line endings, encoding and trailing whitespace, SHALL be preserved. (Property test.)

8.5. APPLYING the same edit set twice SHALL produce the same result as applying it once. (Property test.)

8.6. INVERTING an applied edit set SHALL restore the file byte for byte. (Property test.)

8.7. THE system SHALL be able to emit the edit set as a unified diff without touching the working tree.

8.8. A link with verdict `ALIVE` SHALL never produce an edit. Each verdict SHALL map to exactly one action. (Property test.)

### 9. Reporting

**User story:** As a maintainer, I want one machine-readable report and one report I can read, both
carrying the evidence.

#### Acceptance criteria

9.1. THE system SHALL emit a schema-versioned JSON report containing the run metadata, configuration used, per-link records with cause, verdict, evidence and edit, and a verdict count summary.

9.2. THE system SHALL emit a Markdown report with a verdict summary table, a section per actionable verdict, and an evidence block per fix quoting both pages with the archive timestamp.

9.3. THE system SHALL separate fixes at or above the threshold from items requiring a human.

9.4. THE JSON report SHALL contain no API keys and no raw page bodies beyond the quoted evidence and a bounded excerpt.

9.5. THE system SHALL report per-stage counts, elapsed time, cache hit rate and total token usage.

### 10. Configuration and providers

**User story:** As an operator, I want keys, models and thresholds configurable, and I want a clear
error when a model ID is wrong.

#### Acceptance criteria

10.1. THE system SHALL load configuration from an optional `necro.config.{ts,js,json}`, overlay environment variables, then overlay explicit call-site options, and SHALL validate the result against a schema with defaults.

10.2. THE system SHALL read credentials only from the environment (`NEBIUS_API_KEY`, `TAVILY_API_KEY`, `GITHUB_TOKEN`) and SHALL NOT accept them in a committed config file.

10.3. THE system SHALL reach the LLM through the OpenAI-compatible API at a configurable base URL defaulting to `https://api.tokenfactory.nebius.com/v1/`.

10.4. THE system SHALL take two model IDs from config — a fast classifier and a stronger verifier — and SHALL validate both against `GET /v1/models` on first use, failing with an error that names the available IDs.

10.5. WHEN `NEBIUS_API_KEY` is absent, the system SHALL run in heuristics-only mode and SHALL state so in the report.

10.6. WHEN `TAVILY_API_KEY` is absent, the system SHALL run discovery degraded and SHALL state so in the report.

10.7. THE system SHALL cache every outbound provider response in a content-addressed on-disk cache, keyed by provider, request shape and date bucket, so that reruns and demos are reproducible and cheap.

10.8. THE system SHALL expose a replay-only cache mode that fails rather than making a network call, for use in tests.

### 11. Observability and limits

11.1. THE system SHALL emit structured progress events per stage per link, suitable for a CLI progress bar or an SSE stream.

11.2. THE system SHALL accept a maximum-links cap and a wall-clock budget, and WHEN either is hit SHALL finish cleanly with the links completed so far marked as such.

11.3. THE system SHALL never write to the working tree unless explicitly asked to apply edits.

11.4. THE system SHALL redact credentials from all log output and error messages.

### 12. Ward — archive new links (stretch)

12.1. GIVEN a set of newly added links and archive credentials, the system SHALL submit each to Save Page Now and record the resulting snapshot URL.

12.2. WHEN archive credentials are absent, ward SHALL be skipped with a note and SHALL NOT fail the run.

12.3. THE system SHALL rate-limit Save Page Now submissions to the provider's documented ceiling and SHALL not retry a quota rejection.

---

## Success criteria

- On the seeded haunted demo repo, every planted case gets its expected verdict and cause.
- No fix is emitted without two grounded quotes.
- The library produces a complete run with no API keys set, with degraded mode stated in the report.
- All six properties listed in the brief are covered by passing property-based tests.
