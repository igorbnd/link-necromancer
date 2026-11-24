# necro CLI — design

## Overview

A thin, mostly-declarative shell over `scan()` from `packages/core`, plus one substantial piece of
its own: the GitHub PR writer. The CLI's job is argument parsing, provider construction, progress
rendering, report writing and exit-code selection. Any logic that is not about those five things
belongs in core.

## Architecture

```
argv ──▶ commander ──▶ resolveConfig(flags, file, env)
                              │
                              ▼
                      buildProviders(config)        ──▶ real HttpClient / Wayback / Tavily / Llm
                              │                         wrapped in the core cache decorator
                              ▼
                      core.scan({ root, config, providers, onEvent })
                              │
          ┌───────────────────┼────────────────────┐
          ▼                   ▼                    ▼
    ProgressRenderer    ReportWriter          FixApplier
    (TTY or plain)      (json + md)                │
                                          ┌────────┴────────┐
                                          ▼                 ▼
                                    working tree       PrWriter (Octokit)
                                    or --patch
```

## Package layout

```
apps/cli/src/
  bin.ts                   shebang entry, top-level error handling, exit codes
  commands/
    scan.ts
    fix.ts
    explain.ts
    doctor.ts
  flags.ts                 shared flag definitions and coercions
  providers.ts             buildProviders()
  render/
    progress-tty.ts        ora/log-update based live renderer
    progress-plain.ts      line-oriented fallback
    summary.ts             verdict table + grouped actionable items
    evidence.ts            quote pair formatting
  fix/
    apply.ts               working-tree application, dirty-tree guard
    patch.ts               --patch writer
  github/
    remote.ts              origin parsing, owner/repo/default branch
    pr-writer.ts           branch, tree, commit, ref, PR create-or-update
    pr-body.ts             body template
  exit.ts                  ExitCode enum and mapping
```

## Command structure

`commander` with two primary commands sharing a flag group. `scan` and `fix` differ in exactly one
way at the core level — `scan` never constructs a `FixApplier` — which keeps the "scan cannot write"
guarantee structural rather than conditional.

### Exit code mapping

```ts
export enum ExitCode {
  Ok = 0,
  FailOnMatched = 1,
  ConfigError = 2,
  InternalError = 3,
  Truncated = 4,
}
```

`bin.ts` is the single place that calls `process.exit`. Commands return a result object; `bin.ts`
maps it. This makes exit behaviour unit-testable without spawning a process.

Precedence when several conditions apply: `ConfigError` > `InternalError` > `Truncated` >
`FailOnMatched` > `Ok`. A truncated run that also matched `failOn` exits `4`, because the truncation
is the more important fact — the `failOn` result may be incomplete.

## Progress rendering

The core emits structured events; the CLI chooses a renderer at startup based on
`process.stdout.isTTY` and `--quiet`. Both renderers consume the same event stream, so there is no
branching inside the pipeline.

When `--json -` is used, every byte of human-facing output moves to stderr so the report on stdout
stays machine-parsable. This matters for the Action, which pipes the report.

## GitHub PR writer

Octokit REST only. The sequence avoids any local push, so it works in environments with no write
credentials in the git config (CI, containers, the Action):

1. `GET /repos/{o}/{r}` → default branch; `GET /repos/{o}/{r}/git/ref/heads/{base}` → base SHA.
2. For each changed file, `POST /repos/{o}/{r}/git/blobs` with the post-fix content.
3. `POST /repos/{o}/{r}/git/trees` with `base_tree` = base commit tree and one entry per blob.
4. `POST /repos/{o}/{r}/git/commits` with that tree and the base commit as parent.
5. `POST /repos/{o}/{r}/git/refs` creating `refs/heads/{branch}`, or `PATCH .../git/refs/heads/{branch}` when it already exists.
6. `GET /repos/{o}/{r}/pulls?head={o}:{branch}&state=open` → update body via `PATCH` if found, else `POST /repos/{o}/{r}/pulls`.

One tree, one commit, one PR. Step 6's create-or-update is what delivers the idempotency
requirement; step 6 combined with a closed-PR check delivers the new-branch-on-closed-PR behaviour.

The branch name hashes the edit set, so an unchanged set of fixes reuses the same branch and the
same PR across runs, while a changed set gets a new branch. That is a cheap, stateless way to get
"running fix twice produces no second PR".

### PR body template

```markdown
## 🪦 Link Necromancer — {n} links resurrected

| Verdict | Count |
|---|---|
| RESURRECTED | 4 |
| ARCHIVED | 2 |
| DRIFTED (needs a human) | 1 |

### Applied fixes

| File | Line | Was | Now | Verdict | Cause | Score |
|---|---|---|---|---|---|---|
| docs/setup.md | 42 | `old.example.com/guide` | `docs.example.com/guide` | RESURRECTED | HTTP_ERROR | 0.94 |

<details><summary>Evidence — docs/setup.md:42</summary>

**Then** (archive snapshot, 2019-03-11)
> …quoted text from the archived page…

**Now** (docs.example.com/guide)
> …quoted text from the live page…

Match 0.94 — {model reason}
</details>

### Needs a human
…

---
Generated by Link Necromancer. Classifier `{classifierModel}`, verifier `{verifierModel}`. Run {timestamp}.
```

Every evidence block is collapsed so a PR with twenty fixes stays readable, and the summary table is
always visible. The footer names the models because a reviewer should know what produced the claim.

## Safety design

- **`scan` cannot write.** Enforced by not constructing the applier, not by a flag check.
- **Dirty-tree guard.** `fix` runs `git status --porcelain` and intersects the modified set with the
  files it intends to edit. Only an actual overlap blocks, so unrelated local work does not.
- **Path containment.** Every edit path is resolved and checked to be inside the scanned root before
  any write.
- **Base-branch guard.** `--branch` resolving to the base branch is a config error, not a warning.

## Error handling

| Failure | Behaviour |
|---|---|
| Missing or under-scoped `GITHUB_TOKEN` with `--pr` | Exit 2 naming the required scopes |
| `origin` is not GitHub | Exit 2 naming the non-goal |
| Invalid model ID | Exit 2 with the available IDs, surfaced from core |
| Blob or tree API 422 | Retry once, then exit 3 with the API message |
| Branch ref race (two runs at once) | Re-read the ref and retry the update once |
| Zero fixes above threshold with `--pr` | Exit 0, no branch created, print the needs-a-human list |
| Partial run from cap or budget | Write the partial report, exit 4 |

## Testing strategy

- **Command-level tests** drive each command in-process with a fake provider set and the core cache
  in `replay` mode, asserting rendered output and the returned exit code.
- **Exit-code table test** over the precedence rules.
- **PR writer tests** against a mocked Octokit, asserting the exact call sequence and that only one
  commit and one PR are produced. A second run with the same edit set must produce zero mutating
  calls beyond the body `PATCH`.
- **Golden-file tests** for the PR body and the terminal summary, so a formatting regression is
  visible in review.
- **End-to-end** against `fixtures/haunted-repo`: `scan` output matches a golden snapshot, `fix
  --dry-run` diff touches only URL bytes, `fix` followed by `fix` is a no-op.
