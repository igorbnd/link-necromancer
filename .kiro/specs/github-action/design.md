# GitHub Action — design

## Overview

The Action is deliberately thin: it translates workflow inputs into CLI options, runs the pipeline
in-process, and renders the result into the three places GitHub shows things — a sticky comment,
inline annotations and the job summary. All PR-writing logic is reused from `apps/cli`; the Action
does not talk to the pulls API itself.

## Architecture

```
workflow inputs ──▶ @actions/core.getInput ──▶ options
                                                  │
                  event payload (pull_request?) ───┤
                  base/head refs ──────────────────┤
                                                   ▼
                                        core.scan() via cli internals
                                                   │
                 ┌─────────────────┬───────────────┼────────────────┐
                 ▼                 ▼               ▼                ▼
          StickyComment      Annotations      JobSummary      cli PrWriter
          (issues API)       (::warning)      (@actions/core)  (mode: pr)
                                                   │
                                                   ▼
                                           outputs + artifact
```

In-process rather than shelling out to the `necro` binary: the Action needs the structured report
object to build annotations and the comment, and parsing CLI stdout to get it back would be a
needless round trip. `apps/action` imports the command functions from `apps/cli` directly.

## Package layout

```
apps/action/
  action.yml
  src/
    main.ts              input parsing, mode dispatch, outputs, failure decision
    sticky-comment.ts    find-or-create by hidden marker, update, all-clear collapse
    annotations.ts       ::warning file=,line= per problem link
    summary.ts           @actions/core.summary tables
    changed-files.ts     base...head resolution from the event payload
  dist/index.js          bundled, checked in
  README.md              workflow examples with permissions blocks
  __tests__/
```

## Mode dispatch

| `mode` | Scans | Writes | Needs |
|---|---|---|---|
| `comment` | changed files on PR, all otherwise | sticky comment, annotations, summary | `pull-requests: write` |
| `pr` | all files | fix branch + PR, summary | `contents: write`, `pull-requests: write` |
| `report` | all files | summary + artifact only | read-only |

`report` mode exists so a fork PR or a locked-down repository can still get value. It is also the
safe default to recommend to someone evaluating the tool.

## Sticky comment

Identified by an HTML comment marker in the body:

```html
<!-- link-necromancer:sticky:v1 -->
```

Flow: `GET /repos/{o}/{r}/issues/{n}/comments`, find the first comment authored by the token's user
containing the marker, then `PATCH` it or `POST` a new one. Using a marker rather than storing a
comment ID keeps the Action stateless, which is the only approach that survives re-runs, forks and
cache misses.

On a clean result the comment is collapsed to a single all-clear line rather than deleted, so the
history of the check stays visible on the PR without accumulating noise. Deleting is offered as an
input only if that turns out to be the preferred behaviour during testing.

## Annotations

One `::warning file=<path>,line=<n>,title=<verdict>::` per non-`ALIVE` link, capped at 50 to stay
under GitHub's annotation display limit, with a note in the summary when the cap truncates the list.
Annotations are what put the result in front of a reviewer in the Files view; the comment is the
summary and the evidence.

Severity mapping: `UNRESOLVED`, `PARKED`, `SOFT_404` → warning; `DRIFTED` → notice; `RESURRECTED`
and `ARCHIVED` in `comment` mode → notice, since there is a proposed fix. Nothing is emitted as an
`error` unless the verdict is in `fail-on`, because an annotation at error level reads as a blocking
problem.

## Permissions and failure policy

A missing permission must not fail the job — a fork PR legitimately cannot comment. The comment
writer catches 403 on the comments API, emits a warning annotation explaining the missing
permission, and falls back to the job summary, which always works. The job's success or failure is
decided solely by `fail-on` and configuration validity, so a repo with unreachable third-party links
does not get a permanently red CI.

## Caching

`actions/cache` keyed on `<cache-key-prefix>-necro-<YYYY-WW>-<hash of config>` with a restore-key
prefix fallback. The week bucket means the cache rolls over weekly, so a stale verdict cannot
persist indefinitely while a scheduled daily run still mostly hits cache. Core's cache TTLs still
apply inside the restored directory, so a 24-hour probe TTL is respected even on a week-old cache.

Concurrency: the generated workflow examples include

```yaml
concurrency:
  group: link-necromancer-${{ github.ref }}
  cancel-in-progress: false
```

`cancel-in-progress: false`, not true: cancelling a run that has already created a branch but not
yet opened the PR would leave an orphan branch.

## Workflow examples

```yaml
# .github/workflows/link-check-pr.yml
name: Link check
on: pull_request
permissions:
  contents: read
  pull-requests: write
jobs:
  necro:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }        # blame needs history
      - uses: <owner>/link-necromancer@v1
        with:
          mode: comment
          changed-only: true
        env:
          NEBIUS_API_KEY: ${{ secrets.NEBIUS_API_KEY }}
          TAVILY_API_KEY: ${{ secrets.TAVILY_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

```yaml
# .github/workflows/link-necromancer.yml
name: Resurrect links
on:
  schedule: [{ cron: '0 6 * * 1' }]
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
concurrency:
  group: link-necromancer-${{ github.ref }}
  cancel-in-progress: false
jobs:
  necro:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: <owner>/link-necromancer@v1
        with:
          mode: pr
          threshold: '0.85'
        env:
          NEBIUS_API_KEY: ${{ secrets.NEBIUS_API_KEY }}
          TAVILY_API_KEY: ${{ secrets.TAVILY_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

`fetch-depth: 0` is required in both, because `actions/checkout` defaults to a depth-1 clone and
`git blame` on a shallow clone returns the shallow-boundary commit for every line, which would
silently poison every archive comparison. The README calls this out, and core's shallow-clone
warning (requirement 3.4) catches it at runtime when a user misses it.

## Error handling

| Case | Behaviour |
|---|---|
| Missing `pull-requests: write` | Warning annotation, fall back to job summary, job succeeds |
| Missing `contents: write` in `pr` mode | Configuration error, job fails with the required block |
| Shallow clone detected | Warning annotation naming `fetch-depth: 0`, scan continues |
| No API keys | Degraded mode, stated in the comment and summary |
| Truncated run | `truncated=true`, reported, job succeeds |
| Annotation cap exceeded | First 50 emitted, remainder noted in the summary |
| Two scheduled runs race | Concurrency group serializes; the PR writer's create-or-update handles the rest |

## Testing strategy

- **Input matrix test** over `mode` × `changed-only` × event type, asserting the derived CLI options.
- **Sticky comment tests** against a mocked API: creates once, updates on the second run, collapses
  to all-clear on a clean third run, and falls back to the summary on 403.
- **Annotation tests** for severity mapping and the 50-item cap.
- **Bundle freshness check** in CI comparing a fresh build of `dist/` against the committed one.
- **Live workflow test** in a scratch repository: a PR adding a known dead link gets the expected
  comment and annotation; a scheduled run on the haunted repo opens one fix PR.
