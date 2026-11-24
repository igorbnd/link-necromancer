# MCP server — requirements

> **Stretch scope.** Build this only after `core-pipeline`, `necro-cli` and `graveyard-dashboard`
> are demo-ready. Nothing in the MVP depends on it.

## Introduction

`apps/mcp` exposes the pipeline over the Model Context Protocol so a coding agent — Kiro, Claude or
anything else speaking MCP — can check and repair links while it is already editing docs. This is
the "agent as audience" deliverable from the brief.

The design principle that drives every requirement below: **the server returns edits, it does not
make them.** An agent editing a file needs to own its own writes, and a tool that silently rewrites
files underneath an agent produces conflicts and surprises. The server is a read-and-reason service.

Depends on: [`core-pipeline`](../core-pipeline/requirements.md).

## Requirements

### 1. Transport and lifecycle

1.1. THE server SHALL implement MCP over stdio, startable with `npx necro-mcp`.

1.2. THE server SHALL declare its tools with JSON Schema input and output definitions derived from the same Zod schemas the library uses, so the contract cannot drift from the implementation.

1.3. THE server SHALL read credentials from the environment only and SHALL report which capabilities are available given the credentials present.

1.4. THE server SHALL operate within a configured root directory and SHALL reject any path argument resolving outside it.

### 2. `check_links`

**User story:** As an agent editing a doc, I want to know which links in it are broken before I
hand the file back.

2.1. THE tool SHALL accept a file path, a directory path, or inline content with a notional path, plus optional scan options.

2.2. THE tool SHALL return, per link, the file, line, column, raw URL, verdict, cause, and — where one exists — a suggested replacement with its match score.

2.3. THE tool SHALL return a compact summary first and full per-link detail second, so an agent can decide whether to read the detail.

2.4. THE tool SHALL accept a `maxLinks` bound and SHALL return a partial result marked as such when it is hit.

2.5. THE tool SHALL NOT write to any file.

### 3. `resurrect_link`

**User story:** As an agent, I want to ask where one specific dead URL went.

3.1. THE tool SHALL accept a single URL and optional context: the link text, the surrounding heading, and the date the link was added.

3.2. THE tool SHALL return the verdict, the ranked candidate list with scores, the evidence quote pair for the best candidate, and the archive snapshot URL when one exists.

3.3. THE tool SHALL return candidates that failed verification along with their rejection reason, so an agent can see what was considered and discarded.

3.4. THE tool SHALL NOT write to any file.

### 4. `verify_replacement`

**User story:** As an agent, I have a replacement URL in mind and I want it checked before I commit
to it.

4.1. THE tool SHALL accept an old URL and a proposed new URL, with an optional reference date.

4.2. THE tool SHALL return the match score, the model's reason, the grounded evidence quote pair, and a boolean verdict against the configured threshold.

4.3. THE tool SHALL reject a verification whose quotes cannot be grounded in their source text, and SHALL say so explicitly rather than returning a low score.

4.4. WHEN the old URL is unreachable, the tool SHALL compare the proposed URL against the archive snapshot nearest the reference date.

### 5. `propose_edits`

**User story:** As an agent, I want the exact byte edit to apply, so my own writer applies it.

5.1. THE tool SHALL accept the result of a `check_links` call or a file path, and SHALL return the edit set: file, byte span, expected original bytes, and replacement bytes.

5.2. THE tool SHALL also return the edits as a unified diff.

5.3. THE tool SHALL NOT apply the edits.

5.4. THE returned edits SHALL carry the same `expected`-bytes staleness guard the CLI uses, so an agent applying them late can detect a changed file.

### 6. Agent ergonomics

6.1. EVERY tool SHALL return structured JSON content, and SHALL keep the default response under a configured token budget by truncating evidence quotes and candidate lists before truncating verdicts.

6.2. EVERY tool error SHALL be a structured error naming the stage that failed and whether a retry could succeed.

6.3. THE server SHALL stream or report progress for calls expected to exceed a few seconds, where the client supports it.

6.4. THE server SHALL cache provider responses across calls within a session, so an agent iterating on one document does not re-probe the same URLs.

6.5. THE tool descriptions SHALL state plainly that no tool writes files, so an agent does not plan around a write that will not happen.

## Success criteria

- Kiro, configured with this server, can be asked to fix the links in a document and does so using `check_links` then `propose_edits`, applying the edits with its own file writer.
- No tool call modifies a file under any arguments.
- A path argument escaping the configured root is rejected.
- An ungrounded verification is reported as ungrounded, not as a low score.
