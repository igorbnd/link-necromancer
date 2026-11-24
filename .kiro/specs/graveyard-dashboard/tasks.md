# Graveyard dashboard — tasks

Prerequisite: `core-pipeline` tasks 1–15, and the `FileSystem` / `Git` provider interfaces from core
task 15.1 being genuinely injectable.

Do task 3 (SSRF) before any task that probes a URL from visitor input. It is the only hard security
boundary in this app and retrofitting it is how it gets built wrong.

- [ ] 1. App scaffolding
- [ ] 1.1 Create `apps/web` as a Next.js App Router project wired into the pnpm workspace, depending on `packages/core`
- [ ] 1.2 Configure the Vercel function `maxDuration` and derive the scan caps from it as config constants
  - _Requirements: 2.3, 2.5_
- [ ] 1.3 Implement `lib/kv-cache.ts` as a KV backend for the core cache decorator, so provider caching is shared across invocations
  - _Requirements: 2.6_

- [ ] 2. Repository access adapters
- [ ] 2.1 Implement `lib/github-fs.ts`: recursive tree listing, extension filter, subdirectory filter, file cap, batched raw contents, no `write` method
  - _Requirements: 2.1, 6.4_
- [ ] 2.2 Handle GitHub's `truncated: true` tree response by scanning what was returned and flagging the scan partial
  - _Requirements: 2.4, 7.3_
- [ ] 2.3 Implement `lib/github-git.ts`: GraphQL blame expanded into the core's line-indexed map, requested only for files that produced links
  - _Requirements: 2.2_
- [ ] 2.4 Implement the earliest-commit fallback with dates marked approximate
  - _Requirements: 2.2_
- [ ] 2.5 Adapter tests against recorded GitHub API fixtures, including truncated-tree and blame-failure paths

- [ ] 3. SSRF guard
- [ ] 3.1 Implement `lib/ssrf.ts`: scheme check and IP-literal rejection for private, loopback, link-local, unique-local and metadata ranges
  - _Requirements: 3.3_
- [ ] 3.2 Add DNS resolution checking that rejects when any resolved address is in a blocked range
  - _Requirements: 3.3_
- [ ] 3.3 Pin the connection to the validated address with a custom undici connector, closing the rebind window
  - _Requirements: 3.3_
- [ ] 3.4 Re-run the full check on every redirect hop
  - _Requirements: 3.3_
- [ ] 3.5 Enforce the per-scan total byte cap
  - _Requirements: 3.4_
- [ ] 3.6 **Test suite:** IP-literal rejection, hostname-resolves-private rejection, redirect-to-private rejection, and a DNS rebind simulation
  - _Requirements: 3.3_

- [ ] 4. Scan API and job lifecycle
- [ ] 4.1 Implement `POST /api/scan`: parse `owner/repo` and full URLs, validate public existence, resolve ref to a commit SHA, return a jobId
  - _Requirements: 1.1, 1.2_
- [ ] 4.2 Implement `lib/ratelimit.ts`: per-IP per-minute and per-hour ceilings returning 429 with `Retry-After`
  - _Requirements: 3.2, 7.5_
- [ ] 4.3 Implement the completed-scan cache keyed by `(owner, repo, sha, options)` with a short-circuit return
  - _Requirements: 2.6_
- [ ] 4.4 Implement `lib/jobs.ts`: run `core.scan()` with the GitHub adapters and the caps, writing the report to KV incrementally as stages complete
  - _Requirements: 2.3, 2.4, 2.5_
- [ ] 4.5 Implement `GET /api/scan/:id/events` as SSE over the core progress event stream
  - _Requirements: 2.7_
- [ ] 4.6 Implement `GET /api/scan/:id` returning the current or final report, with credentials and raw file contents excluded from the payload
  - _Requirements: 3.1, 3.5_
- [ ] 4.7 Implement `GET /api/scan/:id/patch` delegating to the core unified-diff emitter
  - _Requirements: 6.1_
- [ ] 4.8 **Budget test:** a synthetic repo above every cap returns a partial report naming the cap that was hit, inside the budget
  - _Requirements: 2.4, 2.5_

- [ ] 5. Submit page
- [ ] 5.1 Implement `SubmitForm` with URL and shorthand input, optional ref and subdirectory
  - _Requirements: 1.1_
- [ ] 5.2 Add three one-click example repositories including the seeded haunted demo repo
  - _Requirements: 1.4_
- [ ] 5.3 Display the scan limits before submission
  - _Requirements: 1.5_
- [ ] 5.4 Display the data-retention statement
  - _Requirements: 3.6_
- [ ] 5.5 Implement the specific error states for private, missing and non-GitHub input, suggesting the CLI for private repos
  - _Requirements: 1.2, 7.1_

- [ ] 6. Graveyard view
- [ ] 6.1 Implement `Headstone` with one variant per verdict per the design's mapping, each carrying an icon and a text badge plus a cause badge
  - _Requirements: 4.1, 4.3, 5.3_
- [ ] 6.2 Implement `Graveyard`: grid, verdict summary with counts, verdict and cause filters, sort by file, verdict and score
  - _Requirements: 4.2_
- [ ] 6.3 Collapse `ALIVE` links by default
  - _Requirements: 4.5_
- [ ] 6.4 Implement `EvidenceCard`: archived quote with snapshot timestamp and snapshot link, replacement quote with URL, match score, model reason, deciding autopsy tier
  - _Requirements: 4.4_
- [ ] 6.5 Mark needs-a-human cards explicitly and present their suggestion as a suggestion, not a fix
  - _Requirements: 4.6_
- [ ] 6.6 Implement `DegradedNotice` and `PartialNotice`
  - _Requirements: 4.7, 7.3_
- [ ] 6.7 Implement the empty-graveyard state
  - _Requirements: 7.2_
- [ ] 6.8 Implement stage-by-stage progress display from the SSE stream, with reconnect that loses no progress
  - _Requirements: 2.7, 7.4_
- [ ] 6.9 Implement the failure state naming the stage, with a retry control
  - _Requirements: 7.4_

- [ ] 7. Theme, motion and accessibility
- [ ] 7.1 Implement `ResurrectionAnimation`: plays once on first reveal, with a visible replay control
  - _Requirements: 5.1_
- [ ] 7.2 Gate all motion on `prefers-reduced-motion`, replacing it with an instant state change and hiding the replay control
  - _Requirements: 5.2_
- [ ] 7.3 Verify WCAG AA contrast and mobile-width readability
  - _Requirements: 5.4_
- [ ] 7.4 Make every control keyboard reachable and screen-reader labelled, including cards and the replay control
  - _Requirements: 5.5_
- [ ] 7.5 Add axe checks on both pages, a keyboard-only walkthrough test and a reduced-motion snapshot
  - _Requirements: 5.2, 5.5_

- [ ] 8. Export and sharing
- [ ] 8.1 Implement `ExportBar`: patch download, Markdown report copy, PR body copy, JSON download, all server-rendered from core and CLI renderers
  - _Requirements: 6.1, 6.2, 6.3_
- [ ] 8.2 Implement the shareable permalink that reloads a completed scan from cache
  - _Requirements: 6.5_
- [ ] 8.3 Confirm no write-scoped GitHub permission is requested anywhere in the app
  - _Requirements: 6.4_

- [ ] 9. Deploy and acceptance
- [ ] 9.1 Deploy to Vercel with server-side-only environment variables
  - _Requirements: 3.1_
- [ ] 9.2 Pre-warm the cache for the seeded haunted demo repo so the demo scan returns in seconds
- [ ] 9.3 **Acceptance:** from the hosted URL with no account, scanning the haunted demo repo shows every planted verdict including both zombies, and every resurrected card shows two quotes and a snapshot timestamp
  - _Requirements: success criteria_
- [ ] 9.4 **Acceptance:** a small public repo scan completes inside the budget or returns usable partial results
  - _Requirements: success criteria_
- [ ] 9.5 **Acceptance:** the page is fully usable with reduced motion and with a keyboard only
  - _Requirements: success criteria_
