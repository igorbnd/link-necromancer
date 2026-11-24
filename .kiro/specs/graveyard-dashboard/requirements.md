# Graveyard dashboard — requirements

## Introduction

`apps/web` is the public, no-login face of Link Necromancer and the primary demo artifact. A visitor
pastes a public GitHub repository URL, the server scans it, and the results render as a graveyard:
dead links are tombstones, resurrected links rise as ghosts, and every card opens to the evidence
behind the verdict.

Two constraints shape the whole design. First, the scan runs server-side in a serverless function,
so it has a hard time budget and cannot clone a repository. Second, judges must be able to use it
with no setup, which means no login, server-held API keys, and abuse limits that a stranger cannot
trip by accident.

Depends on: [`core-pipeline`](../core-pipeline/requirements.md). This spec reuses the core pipeline
through the `FileSystem` and `Git` provider interfaces rather than reimplementing any stage.

## Requirements

### 1. Scan submission

**User story:** As a judge with no account, I want to paste a repo URL and see results.

1.1. THE app SHALL accept a public GitHub repository URL or `owner/repo` shorthand, with an optional branch or ref and an optional subdirectory path.

1.2. THE app SHALL validate the input server-side, SHALL confirm the repository exists and is public, and SHALL reject private, nonexistent and non-GitHub inputs with a specific message.

1.3. THE app SHALL require no authentication to run a scan.

1.4. THE app SHALL offer at least three one-click example repositories, one of which SHALL be the seeded haunted demo repo, so a judge can see a full graveyard without choosing a repo.

1.5. THE app SHALL show the scan limits before the scan starts: the maximum files, the maximum links and the time budget.

### 2. Server-side scanning within serverless limits

**User story:** As the operator, I need a scan to finish inside the function time limit without
cloning anything.

2.1. THE server SHALL read repository files through the GitHub REST tree and contents APIs, and SHALL NOT clone the repository.

2.2. THE server SHALL obtain per-line link dates through the GitHub GraphQL blame API, and WHEN blame is unavailable SHALL fall back to the earliest commit touching the file, marking the date as approximate.

2.3. THE server SHALL enforce a hard cap on files scanned (default 200) and unique links probed (default 50), chosen so a scan completes within the function time budget.

2.4. WHEN a cap is reached, the server SHALL return the completed results marked as partial and SHALL state which cap was hit.

2.5. THE server SHALL enforce a wall-clock budget below the platform function limit and SHALL return partial results rather than timing out.

2.6. THE server SHALL cache completed scans keyed by `(owner, repo, commit SHA, scan options)` and SHALL serve a repeat request for the same commit from cache.

2.7. THE server SHALL stream progress to the client so the UI shows stage-by-stage activity rather than a blank wait.

### 3. Security and abuse limits

**User story:** As the operator, I want a public endpoint I can leave running without it becoming
someone's free scanning proxy.

3.1. ALL provider credentials SHALL live server-side only and SHALL never be sent to the client or appear in any API response.

3.2. THE server SHALL rate-limit by IP, with a per-minute and a per-hour ceiling, returning 429 with a retry hint.

3.3. THE server SHALL refuse to probe URLs resolving to private, loopback, link-local or metadata addresses, enforced at request time and not only at parse time, to prevent server-side request forgery through a crafted repository.

3.4. THE server SHALL cap total bytes fetched per scan.

3.5. THE server SHALL NOT echo repository file contents back to the client beyond the extracted link rows and the bounded evidence quotes.

3.6. THE app SHALL state in the UI that scans are logged in aggregate only and that no repository content is retained beyond the cache TTL.

### 4. The graveyard

**User story:** As a visitor, I want to understand the state of a repo's links in one glance, and
then be able to drill into any one of them.

4.1. THE results view SHALL render one card per link, styled by verdict: a tombstone for `UNRESOLVED`, `PARKED` and `SOFT_404`; a ghost for `RESURRECTED`; a sealed crypt for `ARCHIVED`; a cracked tombstone for `DRIFTED`; and living ground for `ALIVE`.

4.2. THE view SHALL show a verdict summary with counts, and SHALL support filtering by verdict and by cause, and sorting by file, verdict and score.

4.3. EACH card SHALL show the file, line, link text, original URL, verdict badge and cause badge.

4.4. WHEN a card is opened, it SHALL show the evidence: the quote from the archived page with its snapshot timestamp and a link to the snapshot, the quote from the replacement page with its URL, the match score, the model's stated reason, and which autopsy tier decided the verdict.

4.5. THE view SHALL display `ALIVE` links collapsed by default so the graveyard is not dominated by healthy links.

4.6. WHEN a link's verdict required a human, the card SHALL say so and SHALL NOT present the suggestion as a fix.

4.7. THE view SHALL show the degraded-mode notice when the scan ran without an LLM or search provider.

### 5. Theme and motion

**User story:** As a judge watching a demo, I want the graveyard conceit to carry the information,
not obscure it.

5.1. THE resurrection animation SHALL play once per resurrected card on first reveal and SHALL be replayable by a visible control.

5.2. THE app SHALL honour `prefers-reduced-motion` by replacing all animation with an instant state change.

5.3. EVERY verdict SHALL be distinguishable without relying on colour alone, through its icon and its text badge.

5.4. THE results SHALL be readable at mobile width and SHALL meet WCAG AA contrast.

5.5. ALL interactive controls SHALL be keyboard reachable and screen-reader labelled, including the cards and the animation replay control.

### 6. Output a visitor can take away

**User story:** As a maintainer who found this through a demo, I want to apply the fixes to my repo.

6.1. THE app SHALL offer a download of the fixes as a unified diff applicable with `git apply`.

6.2. THE app SHALL offer a copy of the Markdown report and a copy of the PR body.

6.3. THE app SHALL offer a download of the raw JSON report.

6.4. THE app SHALL NOT open a pull request on the visitor's behalf and SHALL NOT request write access to any repository.

6.5. THE app SHALL provide a shareable permalink that reloads a completed scan from cache.

### 7. Failure states

7.1. WHEN the repository is private or missing, the app SHALL say which, and SHALL suggest the CLI for private repositories.

7.2. WHEN the repository contains no scannable links, the app SHALL show an empty-graveyard state rather than an error.

7.3. WHEN the scan returns partial results, the app SHALL show what was completed and which cap was hit, with the completed verdicts fully usable.

7.4. WHEN a scan fails outright, the app SHALL show the stage it failed at and a retry control, and SHALL NOT lose the progress already streamed.

7.5. WHEN rate-limited, the app SHALL show the retry-after time rather than a generic error.

## Success criteria

- A judge with no account scans the seeded haunted demo repo from the hosted URL and sees every planted verdict, including both zombies.
- Every resurrected card shows two quotes and a snapshot timestamp.
- A scan of a small public repo completes inside the function budget, or returns usable partial results.
- The page is fully usable with `prefers-reduced-motion` set and with a keyboard only.
