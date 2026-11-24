---
inclusion: always
---

# Link Necromancer

Finds dead and zombie links in docs and repos, finds where the content went, proves the
replacement is the same content, and opens a PR with the evidence.

What makes it different from `lychee`, `notfoundbot` or an SEO tool: it finds the **live** new home
rather than only an archive copy, it catches **zombie** links that return 200 OK but are now a
parked domain or a soft 404, and it **proves** every replacement with quotes a reviewer can check.

## Two invariants

These are not preferences. A change that breaks either one is wrong, regardless of how it reads.

1. **No fix without grounded evidence.** Every applied fix carries a quote from the old page and a
   quote from the new page, and both quotes are verified to occur in their source text before the
   fix is emitted. A model that invents a quote gets its candidate rejected outright, not scored
   lower.
2. **Byte-exact edits.** A fix rewrites the URL span and leaves every other byte of the file
   untouched — line endings, trailing whitespace, encoding, link text. Edits are carried as byte
   spans with an `expected`-bytes guard, never as line and column.

## Verdict vocabulary

Two fields travel together everywhere: `cause` says why the link is broken, `verdict` says what to
do about it. Never collapse them, and never invent a new value in one surface.

| `cause` | Meaning |
|---|---|
| `OK` | Reachable, content still matches |
| `HTTP_ERROR` | 4xx or 5xx |
| `NETWORK_ERROR` | DNS, TLS, timeout, reset, redirect loop |
| `PARKED` | Domain parked or for sale |
| `SOFT_404` | 200 OK but an error page, a not-found page, or a redirect to the site root |
| `CONTENT_DRIFT` | Reachable, not an error page, materially different content |

| `verdict` | Action |
|---|---|
| `ALIVE` | none — never produces an edit |
| `RESURRECTED` | replace the URL with the verified successor |
| `ARCHIVED` | replace the URL with the snapshot |
| `DRIFTED` | flag for a human; suggest only |
| `PARKED` | flag for a human |
| `SOFT_404` | flag for a human |
| `UNRESOLVED` | flag for a human |

Verdict precedence (strict, top to bottom): verified successor → `RESURRECTED`; dead or zombie with
a good snapshot and `archiveFallback` on → `ARCHIVED`; then `PARKED`, `SOFT_404`, `DRIFTED` by
cause; dead with nothing → `UNRESOLVED`; otherwise `ALIVE`. A parked domain with a good 2019
snapshot is therefore `verdict: ARCHIVED, cause: PARKED`.

Full definitions live in `.kiro/specs/core-pipeline/requirements.md`. That file is the source of
truth; this is the summary.
