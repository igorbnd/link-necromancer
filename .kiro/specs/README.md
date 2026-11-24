# Link Necromancer — spec index

Five specs, ordered by dependency. `core-pipeline` is the engine; everything else is a surface on top of it.

| Spec | Package | MVP? | Depends on |
|---|---|---|---|
| [`core-pipeline`](./core-pipeline/) | `packages/core` | yes | — |
| [`necro-cli`](./necro-cli/) | `apps/cli` | yes | core-pipeline |
| [`graveyard-dashboard`](./graveyard-dashboard/) | `apps/web` | yes | core-pipeline |
| [`github-action`](./github-action/) | `apps/action` | yes | core-pipeline, necro-cli |
| [`mcp-server`](./mcp-server/) | `apps/mcp` | stretch | core-pipeline |

Build order for the hackathon: core-pipeline → necro-cli → graveyard-dashboard → github-action, then mcp-server if time allows.

## Shared vocabulary

Every spec uses the verdict and cause vocabulary defined in
[`core-pipeline/requirements.md`](./core-pipeline/requirements.md#verdict-vocabulary). Do not
redefine it elsewhere. Two fields travel together through the whole system:

- **`cause`** — why the link is broken: `OK`, `HTTP_ERROR`, `NETWORK_ERROR`, `PARKED`, `SOFT_404`, `CONTENT_DRIFT`.
- **`verdict`** — what to do about it: `ALIVE`, `RESURRECTED`, `ARCHIVED`, `DRIFTED`, `PARKED`, `SOFT_404`, `UNRESOLVED`.

## Other `.kiro/` configuration

- [`.kiro/steering/`](../steering/) — six steering files. `product.md`, `structure.md` and `tech.md`
  load on every turn; `testing.md` and `providers.md` load when the matching files are open;
  `demo-runbook.md` is pulled in on demand with `#demo-runbook`.
- [`.kiro/hooks/`](../hooks/) — six agent hooks, with the logic in `scripts/hooks/`. See
  [the hooks README](../hooks/README.md) for which triggers fire on which surface; the
  `PostFileSave` ones do not fire in Kiro Web.

## Provenance

The product brief these specs were written from, and the background research behind it, were
drafted with Claude outside Kiro. The specs, design and implementation in this repository were
produced in Kiro from that brief. Carry this attribution into the submission write-up.
