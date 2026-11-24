---
inclusion: fileMatch
fileMatchPattern: ["packages/core/src/providers/**", "packages/core/src/probe/**", "apps/web/lib/**"]
---

# Working on providers and the probe path

## Everything goes through the cache decorator

A provider is constructed, then wrapped. Never call a provider directly from a stage.

```ts
const archive = withCache(new WaybackArchive(http), { prefix: 'wayback', ttl: WEEK });
```

Cache key is a hash of `(provider, method, canonicalized args, date bucket)`. Canonicalize the args
so argument ordering cannot produce two keys for one request. Three modes: `live`, `prefer-cache`,
and `replay`, where a miss throws — `replay` is what makes the test suite offline and the demo
deterministic.

## Probe discipline

- `GET`, not `HEAD`. The brief calls for it, the autopsy needs the body, and a real share of servers
  mishandle `HEAD`.
- Cap the body read and abort the stream past the cap. A 2 GB file must not sink a scan.
- Classify failures into the six distinct categories (`dns`, `tls`, `timeout`,
  `connection-reset`, `too-many-redirects`, `other`). Never collapse them — "the domain is gone" and
  "the server was slow" lead to different verdicts.
- Rate-limit per **registrable domain**, not per hostname, so `docs.example.com` and
  `www.example.com` share one budget.
- Retry 429 and 5xx and network failures three times with exponential backoff and jitter, honouring
  `Retry-After`. Never retry a 4xx other than 429.
- Send a descriptive `User-Agent` with a contact URL. We are a polite single-URL fetcher, not a
  crawler, and we never follow links to other pages on the target site.

## SSRF guard — `apps/web` only, and non-negotiable there

The dashboard takes a repository URL from a stranger and then fetches the URLs found inside it.
A parse-time string check is not a defence. All five steps are required:

1. Reject non-`http(s)` schemes and IP literals in private, loopback, link-local, unique-local or
   metadata ranges.
2. Resolve the hostname and reject if **any** resolved address is in those ranges. This is what
   blocks a hostname pointing at `169.254.169.254`.
3. Pin the connection to the validated address with a custom undici connector, closing the DNS
   rebind window between the check and the request.
4. Re-run the whole check on **every redirect hop**. A public URL redirecting to `127.0.0.1` is the
   other half of the attack.
5. Enforce the redirect cap, the body cap and the per-scan total byte cap.

Steps 2 through 4 are the ones usually missing. Do not weaken them for convenience.

## Degraded mode

Missing credentials narrow capability; they never fail a run.

- No `NEBIUS_API_KEY`: autopsy stops at archive similarity, verification is similarity-only with
  its score capped below the confidence threshold so it cannot auto-fix, and the result is routed to
  "needs a human".
- No `TAVILY_API_KEY`: candidates come from the final redirect target and the archive snapshot only.

Both cases must be stated in the report. A silent degradation is worse than a missing feature,
because the output looks authoritative.
