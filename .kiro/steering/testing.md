---
inclusion: fileMatch
fileMatchPattern: ["**/*.test.ts", "**/*.prop.test.ts", "**/__tests__/**", "fixtures/**"]
---

# Testing conventions

## No test touches the network

Every test runs with the provider cache in `replay` mode, where a cache miss throws. Recorded
provider responses live in `fixtures/cache/`. A test that needs a new URL records it once in `live`
mode and commits the fixture.

A test that reaches the real internet is a flaky test and a rate-limit problem, and it will fail in
CI on a fork where no API keys exist.

## The six properties

These come from the product brief and are the project's backbone. Each lives in a `*.prop.test.ts`
file next to the code it covers, written with fast-check.

| Property | File |
|---|---|
| `normalize(normalize(u)) === normalize(u)` | `url/normalize.prop.test.ts` |
| Applying edits changes only the URL bytes; inverting restores the file byte for byte | `deliver/edits.prop.test.ts` |
| Applying the same patch twice equals applying it once | `deliver/edits.prop.test.ts` |
| A URL inside a fenced or inline code block is never reported as a doc link | `exhume/markdown.prop.test.ts` |
| Anchor slugs match how GitHub generates heading anchors | `url/anchor.prop.test.ts` |
| Each verdict maps to exactly one action; `ALIVE` never produces a change | `adjudicate/verdict.prop.test.ts` |

Rules for these:

- **Use an oracle where one exists.** The anchor property compares against `github-slugger` rather
  than asserting a hand-rolled slug function against itself.
- **Generate adversarial input.** Unicode hosts, mixed-case percent-encoding, CRLF, BOM, duplicate
  headings, punctuation runs, empty query and fragment. A property test over tame input is a unit
  test with extra steps.
- **Shrink output is the bug report.** When a property fails, put the shrunk counterexample in a
  regression unit test before fixing it.

## Tables, not examples

The autopsy tier decision table and the verdict precedence order are both covered by exhaustive
table tests over signal combinations and similarity bands. A threshold change should fail a named
row, not a vague assertion.

## The haunted repo is the definition of done

`fixtures/haunted-repo/` carries ten planted cases and `expected.json` naming the expected
`(verdict, cause)` for each. One integration test asserts the whole table in replay mode. Adding a
planted case means adding its `expected.json` row in the same change.

Two acceptance tests guard the invariants directly:

- **Negative evidence:** a fixture where the verifier returns a plausible but fabricated quote must
  produce no fix and `rejected: 'ungrounded-quote'`.
- **Degraded mode:** a full run with no API keys completes, states degraded mode in the report, and
  emits no auto-fix.

Calibrate thresholds so that no planted `DRIFTED` case is ever auto-fixed. A false positive here
costs more than a missed fix: it rewrites a URL that was fine.
