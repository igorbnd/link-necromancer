# GitHub Action — tasks

Prerequisite: `necro-cli` tasks 1–4 complete (working scan, fix and PR writer).

- [ ] 1. Action scaffolding
- [ ] 1.1 Create `apps/action` with `action.yml` declaring every input and output, running on `node20`
  - _Requirements: 1.1, 1.2, 1.4_
- [ ] 1.2 Configure an esbuild bundle to `dist/index.js` with no install step required in consumers
  - _Requirements: 1.1, 5.4_
- [ ] 1.3 Implement input parsing and validation in `src/main.ts`, reading credentials from the environment only
  - _Requirements: 1.2, 1.3_
- [ ] 1.4 Implement `src/changed-files.ts`: resolve base and head from the event payload, defaulting `changed-only` to true on `pull_request`
  - _Requirements: 1.2, 2.1_
- [ ] 1.5 Input matrix test over `mode` × `changed-only` × event type asserting the derived options
  - _Requirements: 1.2_

- [ ] 2. Reporting surfaces
- [ ] 2.1 Implement `src/summary.ts`: verdict summary, affected-link table and evidence blocks via `@actions/core.summary`
  - _Requirements: 2.5_
- [ ] 2.2 Implement `src/annotations.ts`: one annotation per non-`ALIVE` link on the exact file and line, with the design's severity mapping and a 50-item cap noted in the summary
  - _Requirements: 2.7_
- [ ] 2.3 Implement `src/sticky-comment.ts`: find-or-create by hidden marker, update in place on re-runs
  - _Requirements: 2.2, 2.3_
- [ ] 2.4 Implement the clean-result path collapsing the comment to a one-line all-clear with no new noise
  - _Requirements: 2.4_
- [ ] 2.5 Implement the 403 fallback to job summary with a warning annotation and a succeeding job
  - _Requirements: 2.6_
- [ ] 2.6 Sticky comment tests: creates once, updates on rerun, collapses on clean, falls back on 403
  - _Requirements: 2.2, 2.4, 2.6_

- [ ] 3. Mode dispatch
- [ ] 3.1 Implement `comment` mode end to end
  - _Requirements: 2.1–2.7_
- [ ] 3.2 Implement `pr` mode delegating to the CLI PR writer, including the update-existing-PR and zero-fixes paths
  - _Requirements: 3.1, 3.2, 3.3, 3.5_
- [ ] 3.3 Implement `report` mode: summary and artifact only, no write permissions needed
  - _Requirements: 1.5_
- [ ] 3.4 Guard against committing to the default branch
  - _Requirements: 3.4_
- [ ] 3.5 Set every declared output, including per-verdict counts and `truncated`
  - _Requirements: 1.4, 4.5_

- [ ] 4. Job behaviour
- [ ] 4.1 Implement the failure policy: fail only on a `fail-on` match or a configuration error, never on unreachable links
  - _Requirements: 4.1_
- [ ] 4.2 Implement degraded mode when `NEBIUS_API_KEY` is absent, stated in both the comment and the summary
  - _Requirements: 1.6_
- [ ] 4.3 Wire `actions/cache` with the week-bucketed key and restore-key fallback
  - _Requirements: 4.3_
- [ ] 4.4 Upload the JSON and Markdown reports as a build artifact
  - _Requirements: 4.4_
- [ ] 4.5 Detect a shallow clone and emit a warning annotation naming `fetch-depth: 0`
  - _Requirements: error handling table_
- [ ] 4.6 Verify a changed-only PR scan finishes in under two minutes on `ubuntu-latest`
  - _Requirements: 4.6_

- [ ] 5. Distribution
- [ ] 5.1 Write the README with both workflow examples, the correct `permissions` blocks per mode, the concurrency group and the `fetch-depth: 0` requirement
  - _Requirements: 1.5, 4.2, 5.1_
- [ ] 5.2 Add the CI check that fails when committed `dist/` differs from a fresh build
  - _Requirements: 5.3_
- [ ] 5.3 Set up the release process publishing immutable version tags and moving the `v1` tag
  - _Requirements: 5.2_

- [ ] 6. Acceptance
- [ ] 6.1 **Acceptance:** in a scratch repo, a PR adding a dead link gets a comment with file, line, verdict and evidence within two minutes
  - _Requirements: success criteria_
- [ ] 6.2 **Acceptance:** re-running the workflow updates the same comment
  - _Requirements: success criteria_
- [ ] 6.3 **Acceptance:** a scheduled run on the haunted demo repo opens one fix PR with an evidence table
  - _Requirements: success criteria_
- [ ] 6.4 **Acceptance:** a run with no `NEBIUS_API_KEY` reports in degraded mode without failing
  - _Requirements: success criteria_
