# MCP server — tasks

> Stretch scope. Start only once core, CLI and dashboard are demo-ready.

Prerequisite: `core-pipeline` tasks 1–15.

- [ ] 1. Server scaffolding
- [ ] 1.1 Create `apps/mcp` with a `necro-mcp` bin on `@modelcontextprotocol/sdk` over stdio
  - _Requirements: 1.1_
- [ ] 1.2 Build the tool registry that generates MCP declarations from the tools' Zod schemas, so declaration and validation share one source
  - _Requirements: 1.2_
- [ ] 1.3 Construct the core `FileSystem` provider with no `write` implementation, making writes structurally impossible
  - _Requirements: 2.5, 3.4, 5.3_
- [ ] 1.4 Implement the root jail: resolve and `realpath`-check every path argument against `--root`
  - _Requirements: 1.4_
- [ ] 1.5 Implement capability reporting based on which credentials are present
  - _Requirements: 1.3_
- [ ] 1.6 Construct the session cache: in-memory LRU in front of the core on-disk cache
  - _Requirements: 6.4_

- [ ] 2. Tools
- [ ] 2.1 Implement `check_links` accepting a file path, directory or inline content, returning summary then per-link detail
  - _Requirements: 2.1, 2.2, 2.3_
- [ ] 2.2 Implement the `maxLinks` bound with a partial result marker
  - _Requirements: 2.4_
- [ ] 2.3 Implement `resurrect_link` returning verdict, ranked candidates, evidence and snapshot URL
  - _Requirements: 3.1, 3.2_
- [ ] 2.4 Include rejected candidates with their rejection reasons
  - _Requirements: 3.3_
- [ ] 2.5 Implement `verify_replacement` returning score, reason, grounded evidence and a threshold pass or fail
  - _Requirements: 4.1, 4.2_
- [ ] 2.6 Report an ungrounded quote explicitly rather than as a low score
  - _Requirements: 4.3_
- [ ] 2.7 Implement the archive-comparison path for an unreachable old URL
  - _Requirements: 4.4_
- [ ] 2.8 Implement `propose_edits` returning the edit set with the `expected`-bytes guard, plus a unified diff
  - _Requirements: 5.1, 5.2, 5.4_

- [ ] 3. Agent ergonomics
- [ ] 3.1 Implement layered response shaping with bottom-up truncation and a `truncated` report
  - _Requirements: 6.1_
- [ ] 3.2 Implement structured errors naming the failed stage and a `retryable` flag
  - _Requirements: 6.2_
- [ ] 3.3 Implement progress reporting for long calls where the client supports it
  - _Requirements: 6.3_
- [ ] 3.4 Write tool descriptions that state plainly that no tool writes files
  - _Requirements: 6.5_

- [ ] 4. Testing and acceptance
- [ ] 4.1 Protocol tests over an in-memory transport: tool listing and one call per tool, asserting declared schema matches actual response shape
- [ ] 4.2 Root jail tests: `../` traversal, absolute outside path, symlink escape
  - _Requirements: 1.4_
- [ ] 4.3 **No-write assertion:** byte-identical filesystem snapshot across an exhaustive tool-call sweep
  - _Requirements: success criteria_
- [ ] 4.4 Truncation tests preserving layers 1 and 2
  - _Requirements: 6.1_
- [ ] 4.5 Ungrounded-quote test
  - _Requirements: 4.3, success criteria_
- [ ] 4.6 Document the Kiro MCP configuration block in the README
- [ ] 4.7 **Acceptance:** Kiro configured against the server fixes the links in a haunted fixture document using `check_links` then `propose_edits`, applying edits with its own writer
  - _Requirements: success criteria_
