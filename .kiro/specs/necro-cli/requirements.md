# necro CLI — requirements

## Introduction

`apps/cli` is the primary human interface and the binary the GitHub Action shells into. It exposes
the core pipeline as `necro scan` (read-only) and `necro fix` (writes files, optionally opens a PR),
plus small utility commands.

The CLI owns one piece of logic the core library does not: creating the GitHub pull request. That
lives here rather than in core because it is the only stage that writes outside the working tree,
and keeping it out of core means the dashboard and MCP server cannot accidentally open a PR.

Depends on: [`core-pipeline`](../core-pipeline/requirements.md). The verdict vocabulary is defined
there and is not redefined here.

## Requirements

### 1. Commands and arguments

**User story:** As a maintainer, I want one obvious read-only command and one obvious write command,
so I never change files by accident.

1.1. THE CLI SHALL provide `necro scan <path>`, which SHALL NOT modify any file in the working tree under any flag combination.

1.2. THE CLI SHALL provide `necro fix <path>`, which SHALL apply fixes at or above the confidence threshold to the working tree.

1.3. THE CLI SHALL support these flags on both commands: `--config <file>`, `--threshold <0..1>`, `--changed-only [base-ref]`, `--max-links <n>`, `--budget <seconds>`, `--include <glob...>`, `--exclude <glob...>`, `--code-comments`, `--cache <live|prefer-cache|replay|off>`, `--concurrency <n>`, `--json [file]`, `--markdown [file]`, `--quiet`, `--verbose`, `--no-color`.

1.4. THE CLI SHALL support on `fix` only: `--dry-run`, `--pr`, `--branch <name>`, `--base <ref>`, `--pr-title <text>`, `--patch <file>`.

1.5. WHEN `--dry-run` is passed to `fix`, the CLI SHALL print the unified diff and SHALL NOT write any file.

1.6. THE CLI SHALL provide `necro explain <link-id|url>` to print the full evidence record for one link from the last report, and `necro doctor` to check configuration, credentials, model IDs and git state without scanning.

1.7. WHEN no path is given, the CLI SHALL default to the current working directory.

### 2. Output

**User story:** As a maintainer running this in a terminal, I want to see progress and then a
summary I can act on.

2.1. WHEN stdout is a TTY and `--quiet` is not set, the CLI SHALL render live progress showing the current stage and completed-over-total link counts.

2.2. WHEN stdout is not a TTY, the CLI SHALL emit plain line-oriented progress with no ANSI control sequences.

2.3. THE CLI SHALL print a verdict summary table, then the actionable items grouped by verdict, with file, line, old URL, new URL and the match score.

2.4. FOR each proposed fix, the CLI SHALL print both evidence quotes and the archive timestamp.

2.5. WHEN `--json` is given without a path, the CLI SHALL write `necro-report.json` in the working directory; WHEN given a path it SHALL write there; WHEN the path is `-` it SHALL write the report to stdout and send all progress and human output to stderr.

2.6. WHEN `--markdown` is given, the CLI SHALL write `GRAVEYARD.md` by the same path rules.

2.7. WHEN running in degraded mode, the CLI SHALL print a prominent notice naming the missing credential and the capability lost.

### 3. Exit codes

**User story:** As a CI author, I want exit codes I can branch on.

3.1. THE CLI SHALL exit `0` when the run completed and no verdict in the configured `failOn` set was found.

3.2. THE CLI SHALL exit `1` when the run completed and at least one verdict in `failOn` was found. The default `failOn` set SHALL be empty for `scan` and empty for `fix`.

3.3. THE CLI SHALL exit `2` on a configuration or credential error, including an invalid model ID.

3.4. THE CLI SHALL exit `3` on an unexpected internal error, printing a stack trace only under `--verbose`.

3.5. THE CLI SHALL exit `4` when the link cap or wall-clock budget cut the run short, after writing a partial report.

3.6. THE CLI SHALL support `--fail-on <verdict...>` to override the `failOn` set.

### 4. Pull request creation

**User story:** As a maintainer, I want one PR with all the fixes and an evidence table in the
description, so review is a single pass.

4.1. WHEN `--pr` is given, the CLI SHALL require a `GITHUB_TOKEN` with `contents: write` and `pull-requests: write`, and SHALL exit `2` with a clear message when it is missing or lacks scope.

4.2. THE CLI SHALL determine owner, repo and default branch from the `origin` remote and the GitHub API, and SHALL exit `2` when `origin` is not a GitHub remote. (Non-goal: other git hosts.)

4.3. THE CLI SHALL create a single commit containing all applied fixes, on a new branch named `necro/fix-<YYYY-MM-DD>-<short-hash-of-edit-set>` unless `--branch` overrides it.

4.4. THE CLI SHALL create the commit via the GitHub tree and commit APIs rather than one commit per file, and SHALL NOT require a local push.

4.5. THE CLI SHALL NOT commit to the base branch, and SHALL exit `2` if `--branch` resolves to the base branch.

4.6. THE PR body SHALL contain: a verdict summary, a table of every applied fix with file, line, old URL, new URL, verdict, cause and score, a collapsed evidence block per fix with both quotes and the archive timestamp, a "needs a human" section for sub-threshold items, and a footer naming the tool, the model IDs used and the run timestamp.

4.7. WHEN an open PR already exists on the computed branch, the CLI SHALL update that branch and PR body instead of creating a duplicate.

4.8. WHEN the computed branch exists on a closed or merged PR, the CLI SHALL create a new branch with a disambiguating suffix and open a new PR.

4.9. WHEN zero fixes clear the threshold, the CLI SHALL NOT create a branch or PR, and SHALL print the "needs a human" list instead.

4.10. THE CLI SHALL print the PR URL on success.

### 5. Patch output

5.1. WHEN `--patch <file>` is given, the CLI SHALL write a unified diff applicable with `git apply` and SHALL NOT modify the working tree.

5.2. THE emitted patch SHALL apply cleanly to the exact tree it was generated from, and SHALL fail rather than apply partially to a changed tree.

### 6. Safety

6.1. WHEN the working tree has uncommitted changes to files the CLI would edit, `fix` SHALL refuse to proceed unless `--allow-dirty` is passed.

6.2. THE CLI SHALL never write outside the scanned path.

6.3. THE CLI SHALL never print credentials, including in verbose mode and in error output.

6.4. THE CLI SHALL be installable and runnable via `npx necro` with no global install.

## Success criteria

- `necro scan fixtures/haunted-repo` prints the planted verdicts, including both zombies, and exits 0.
- `necro fix --dry-run` on the same repo prints a diff touching only URL bytes.
- `necro fix --pr` against a scratch repo opens one PR whose body contains an evidence quote pair for every applied fix.
- Running `fix` twice produces no second change and no second PR.
