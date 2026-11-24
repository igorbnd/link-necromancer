# necro CLI — tasks

Prerequisite: `core-pipeline` tasks 1–15 complete (a working `scan()` with reports and edits).

- [ ] 1. CLI skeleton
- [ ] 1.1 Set up `apps/cli` with a `necro` bin, commander, and `bin.ts` as the only caller of `process.exit`
  - _Requirements: 1.1, 1.2_
- [ ] 1.2 Implement `flags.ts` with the shared flag group and coercions, plus the fix-only flags
  - _Requirements: 1.3, 1.4_
- [ ] 1.3 Implement `exit.ts` with the `ExitCode` enum and the precedence mapping, plus a table test
  - _Requirements: 3.1–3.6_
- [ ] 1.4 Implement `providers.ts` to build the real provider set wrapped in the core cache, honouring `--cache`
  - _Requirements: 1.3_

- [ ] 2. `necro scan`
- [ ] 2.1 Wire `scan` to `core.scan()` with no applier constructed, so writing is structurally impossible
  - _Requirements: 1.1, 6.2_
- [ ] 2.2 Implement the TTY progress renderer and the plain non-TTY renderer over the core event stream
  - _Requirements: 2.1, 2.2_
- [ ] 2.3 Implement `render/summary.ts`: verdict table plus actionable items grouped by verdict with file, line, URLs and score
  - _Requirements: 2.3_
- [ ] 2.4 Implement `render/evidence.ts`: quote pair plus archive timestamp per fix
  - _Requirements: 2.4_
- [ ] 2.5 Implement report writing for `--json` and `--markdown`, including the `-` stdout case that moves human output to stderr
  - _Requirements: 2.5, 2.6_
- [ ] 2.6 Implement the degraded-mode notice naming the missing credential and the lost capability
  - _Requirements: 2.7_
- [ ] 2.7 Implement `--fail-on` and the exit-code decision
  - _Requirements: 3.1, 3.2, 3.6_

- [ ] 3. `necro fix`
- [ ] 3.1 Implement `fix/apply.ts`: apply the core edit set to the working tree with path containment checks
  - _Requirements: 1.2, 6.2_
- [ ] 3.2 Implement the dirty-tree guard intersecting `git status --porcelain` with the files to be edited, bypassed by `--allow-dirty`
  - _Requirements: 6.1_
- [ ] 3.3 Implement `--dry-run` printing the unified diff with no writes
  - _Requirements: 1.5_
- [ ] 3.4 Implement `fix/patch.ts` for `--patch <file>`
  - _Requirements: 5.1, 5.2_
- [ ] 3.5 Test that `fix` run twice produces no second change
  - _Requirements: success criteria_

- [ ] 4. GitHub PR writer
- [ ] 4.1 Implement `github/remote.ts`: parse `origin`, resolve owner, repo and default branch; exit 2 for non-GitHub remotes
  - _Requirements: 4.2_
- [ ] 4.2 Implement token presence and scope checking with a clear exit-2 message
  - _Requirements: 4.1_
- [ ] 4.3 Implement the branch name as `necro/fix-<date>-<edit-set-hash>`, with `--branch` override and a base-branch guard
  - _Requirements: 4.3, 4.5_
- [ ] 4.4 Implement `github/pr-writer.ts` as the six-step blob → tree → commit → ref → PR sequence, producing one commit with no local push
  - _Requirements: 4.4_
- [ ] 4.5 Implement create-or-update against an existing open PR on the computed branch
  - _Requirements: 4.7_
- [ ] 4.6 Implement the new-branch-with-suffix path when the computed branch belongs to a closed or merged PR
  - _Requirements: 4.8_
- [ ] 4.7 Implement `github/pr-body.ts` per the template: summary, fix table, collapsed evidence per fix, needs-a-human section, model footer
  - _Requirements: 4.6_
- [ ] 4.8 Skip branch and PR creation entirely when zero fixes clear the threshold, printing the needs-a-human list
  - _Requirements: 4.9_
- [ ] 4.9 Print the PR URL on success
  - _Requirements: 4.10_
- [ ] 4.10 Handle the ref race and 422 retry cases
  - _Requirements: error handling table_
- [ ] 4.11 Mocked-Octokit tests asserting the exact call sequence, one commit, one PR, and zero mutating calls on an unchanged rerun
  - _Requirements: 4.4, 4.7, success criteria_

- [ ] 5. Utility commands
- [ ] 5.1 Implement `necro explain <link-id|url>` reading the last JSON report and printing the full evidence record
  - _Requirements: 1.6_
- [ ] 5.2 Implement `necro doctor`: check config validity, credential presence, model IDs against `/v1/models`, git repository and shallow state, with no scan
  - _Requirements: 1.6_

- [ ] 6. Packaging and acceptance
- [ ] 6.1 Confirm `npx necro` works with no global install; bundle with the correct `bin` field and shebang
  - _Requirements: 6.4_
- [ ] 6.2 Verify no credential appears in any output path including `--verbose` and error traces
  - _Requirements: 6.3_
- [ ] 6.3 Golden-file tests for the terminal summary and the PR body
- [ ] 6.4 **Acceptance:** `necro scan fixtures/haunted-repo` prints every planted verdict including both zombies and exits 0
  - _Requirements: success criteria_
- [ ] 6.5 **Acceptance:** `necro fix --pr` against a scratch repo opens one PR with an evidence quote pair for every applied fix
  - _Requirements: success criteria_
