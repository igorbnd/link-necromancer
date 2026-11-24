# GitHub Action — requirements

## Introduction

`apps/action` packages the CLI as a GitHub Action so a repository can check its links on a schedule
or on every pull request. Two usage shapes matter:

- **On pull request:** scan only the links the PR touched and post a sticky review comment. Fast,
  non-blocking, no write access to code needed.
- **On schedule:** scan the whole repository and open one fix PR with the evidence table.

Depends on: [`core-pipeline`](../core-pipeline/requirements.md) and
[`necro-cli`](../necro-cli/requirements.md). The Action adds no pipeline or PR logic of its own; it
is configuration, a comment writer, and a job summary.

## Requirements

### 1. Action definition

1.1. THE Action SHALL be a Node 20 JavaScript action with its dependencies bundled into `dist/`, requiring no install step in the consuming workflow.

1.2. THE Action SHALL accept these inputs: `path` (default `.`), `mode` (`comment` | `pr` | `report`, default `comment`), `threshold`, `changed-only` (default `true` on `pull_request`, `false` otherwise), `fail-on` (space-separated verdicts, default none), `config`, `max-links`, `budget`, `code-comments`, `include`, `exclude`, and `cache-key-prefix`.

1.3. THE Action SHALL read `NEBIUS_API_KEY`, `TAVILY_API_KEY` and `GITHUB_TOKEN` from the environment only, and SHALL NOT accept them as inputs.

1.4. THE Action SHALL expose these outputs: `report-path`, `summary-json`, counts per verdict, `fixes-applied`, `needs-human`, `pr-url`, and `truncated`.

1.5. THE Action SHALL document the required `permissions` block for each mode in its README: `pull-requests: write` for `comment`, plus `contents: write` for `pr`, and read-only for `report`.

1.6. THE Action SHALL run in a degraded, heuristics-only mode when `NEBIUS_API_KEY` is absent rather than failing the job.

### 2. Pull request mode

2.1. WHEN the event is `pull_request` and `changed-only` is true, the Action SHALL scan only files changed between the base and head refs.

2.2. THE Action SHALL post a single sticky comment, identified by a hidden marker, and SHALL update that comment on subsequent runs rather than adding a new one.

2.3. THE comment SHALL contain the verdict summary, a table of affected links with file, line, verdict, cause and score, and a collapsed evidence block per proposed fix.

2.4. WHEN the PR introduces no link problems, the Action SHALL either delete or collapse the previous comment to a one-line all-clear, and SHALL NOT post noise on clean PRs.

2.5. THE Action SHALL write the same content to the job summary so the result is visible without comment permissions.

2.6. WHEN the Action lacks `pull-requests: write`, it SHALL fall back to the job summary with a warning annotation and SHALL NOT fail the job.

2.7. THE Action SHALL emit a warning annotation on the exact file and line of each problem link, so the result appears inline in the PR's Files view.

### 3. Fix PR mode

3.1. WHEN `mode` is `pr`, the Action SHALL apply fixes at or above the threshold and open one pull request via the CLI's PR writer.

3.2. THE Action SHALL update an existing open necro fix PR rather than opening a duplicate.

3.3. WHEN zero fixes clear the threshold, the Action SHALL open no PR and SHALL report the needs-a-human list in the job summary.

3.4. THE Action SHALL never commit to the default branch.

3.5. THE Action SHALL set `pr-url` as an output when a PR is created or updated.

### 4. Job behaviour

4.1. THE Action SHALL fail the job only when a verdict in `fail-on` is found, or on a configuration error, and SHALL NOT fail the job because individual links were unreachable.

4.2. THE Action SHALL use a concurrency group per repository and ref so two scheduled runs cannot race on the same fix branch.

4.3. THE Action SHALL persist the provider cache across runs with `actions/cache`, keyed by `cache-key-prefix` and a week bucket, so scheduled runs are cheap and rate-limit pressure stays low.

4.4. THE Action SHALL upload the JSON and Markdown reports as a build artifact.

4.5. WHEN the link cap or budget truncates the run, the Action SHALL set `truncated` to true, report it in the summary, and SHALL NOT fail the job.

4.6. THE Action SHALL complete a changed-only PR scan of a typical pull request in under two minutes on a standard runner.

### 5. Distribution

5.1. THE repository SHALL provide ready-to-copy workflow examples for PR mode and scheduled mode, including the correct `permissions` blocks.

5.2. THE Action SHALL be released on a moving major tag (`v1`) as well as immutable version tags.

5.3. A CI check SHALL verify that `dist/` is in sync with the source, failing the build when a release bundle is stale.

5.4. THE Action SHALL work on `ubuntu-latest` without additional system dependencies.

## Success criteria

- A PR adding a dead link gets a comment naming the file, the line and the verdict, with evidence, within two minutes.
- Re-running the workflow updates the same comment instead of adding another.
- A scheduled run on the haunted demo repo opens one fix PR with an evidence table.
- A run with no `NEBIUS_API_KEY` still reports, in degraded mode, without failing.
