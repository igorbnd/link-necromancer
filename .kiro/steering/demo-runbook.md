---
inclusion: manual
---

# Demo runbook

Pull this in with `#demo-runbook` when preparing or rehearsing the submission demo.
Target: three minutes or less.

## Pre-flight

- [ ] `fixtures/haunted-repo/` committed with all ten planted cases and `expected.json`
- [ ] `fixtures/cache/` recorded, so the demo never depends on a live site, a rate limit or Wi-Fi
- [ ] Dashboard deployed, with the haunted repo's scan **pre-warmed in the KV cache** so the demo scan returns in seconds
- [ ] One fix PR already open on a scratch repo, so step 4 does not depend on a live API call
- [ ] `necro doctor` passes; model IDs validated against `/v1/models`
- [ ] Terminal font large enough to read in a recording; `--no-color` off, the colour helps

## Beats

**1. The problem (20s).** A real-looking docs repo full of rotten links. Run a plain link checker;
it prints `404` and stops. Say the line: it told you what broke, not where the content went.

**2. `necro scan` (45s).** Run against the haunted repo. Land on the verdict summary, then point at
the two zombies: a parked domain and a soft 404, both returning **200 OK**. This is the beat no
other tool has. Show the `cause` badge next to the `verdict` badge.

**3. The graveyard (45s).** Dashboard, no login. Tombstones, then the resurrection animation, then
open one evidence card: the quote from the 2019 Wayback snapshot beside the quote from the live
replacement page, with the match score and the model's reason.

**4. The PR (20s).** The evidence table in the description, one collapsed evidence block per fix,
the model IDs in the footer. Say it: no fix ships without two quotes a reviewer can check.

**5. The Kiro story (40s).** The five specs under `.kiro/specs/`. A hook firing on save and running
the property tests. A property test catching a real bug — use the shrunk counterexample from the
regression test, it is more convincing than a passing suite.

**6. Close (10s).** The roadmap line: links rot, facts rot too. Stale version and pricing claims in
docs are the same problem one layer up.

## Things that will go wrong

- **Live network in the demo.** Run with `--cache prefer-cache`. Never demo in `live` mode.
- **Hooks on save do not fire in Kiro Web.** `PostFileSave` is IDE and CLI only. Record beat 5 in
  the IDE or CLI, not in a Web session.
- **A shallow clone silently poisons every archive comparison**, because `git blame` returns the
  shallow boundary for every line. Clone with full history before recording.
- **The resurrection animation under screen recording.** Check it at the recording frame rate, and
  check the `prefers-reduced-motion` path separately — a judge may have it on.

## Attribution

The product brief and its background research were drafted with Claude outside Kiro. The specs,
design and implementation were produced in Kiro from that brief. Say so in the write-up.
