# SledujteToCzProxy

ASP.NET 4.5 CZ-IP proxy for [sledujteto.cz](https://www.sledujteto.cz), deployed on
`sledujteto.aspfree.cz` (AS43541 aspone.cz webhosting). Used by
[ceskarepublika.wiki](https://ceskarepublika.wiki) (`cr-web`) to reach endpoints that
are rate-limited or ASN-blocked for non-CZ datacenter IPs (Hetzner AS24940, Oracle
AS31898).

Separate from [`CeskaRepublika.CzProxy`](https://github.com/Olbrasoft/CeskaRepublika.CzProxy)
(prehraj.to / nova.cz) — isolated rate limits, isolated monitoring, isolated
incidents. See `cr/CLAUDE.md` and tracker [Olbrasoft/cr#543](https://github.com/Olbrasoft/cr/issues/543).

## Endpoints

All endpoints require `?key=<shared-secret>`. Missing or wrong key → `403`.

| Endpoint | Purpose |
|---|---|
| `GET /Hash.ashx?id=<file_id>&key=…` | Calls `POST https://www.sledujteto.cz/services/add-file-link` and parses the response to detect the CDN host (`www` vs `data{N}`). Returns `{cdn, streamable, upstream}`. The hash is short-lived (~minutes) and cross-IP-portable only on the `www` CDN. |
| `GET /Search.ashx?q=<query>&page=<n>&limit=<n>&key=…` | Passes through `GET https://www.sledujteto.cz/api/web/videos?query=…`. Cached 10 min per `(q, page, limit)` tuple. Hetzner / Oracle return empty `files:[]` for this endpoint — aspone AS43541 goes through. |

### Example

```bash
# Resolve file_id=15546 (Matrix 1) — www CDN, streamable
curl -s 'https://sledujteto.aspfree.cz/Hash.ashx?id=15546&key=<secret>' | jq

# Search (20-50 results for "matrix")
curl -s 'https://sledujteto.aspfree.cz/Search.ashx?q=matrix&key=<secret>' | jq '.data.files | length'
```

## Layout

```
SledujteToCzProxy/
├── .gitignore
├── README.md
└── src/
    └── SledujteToCzProxy/
        ├── Default.aspx    # landing page — status + endpoint table
        ├── Hash.ashx       # POST add-file-link + CDN detection
        ├── Search.ashx     # /api/web/videos passthrough + 10-min cache
        └── web.config      # UTF-8 globalization, debug=off
```

No code-behind, no build step — deploy is a plain file copy.

## Deploy

FTP creds: `~/Dokumenty/přístupy/aspone-cz.md` (`web1.aspfree.cz`, login
`sledujteto.aspfree.cz`). Upload `src/SledujteToCzProxy/*` to the webroot.

```bash
# Using curl (ephemeral; no lftp config file)
SLEDUJTETO_FTP_PASS='<from aspone-cz.md>'
cd src/SledujteToCzProxy
for f in Default.aspx Hash.ashx Search.ashx web.config; do
  curl -T "$f" --user "sledujteto.aspfree.cz:$SLEDUJTETO_FTP_PASS" \
    "ftp://web1.aspfree.cz/$f"
done
```

Smoke test:

```bash
# Without key → 403
curl -sI 'https://sledujteto.aspfree.cz/Hash.ashx?id=15546'
# With key → 200 + JSON
curl -s 'https://sledujteto.aspfree.cz/Hash.ashx?id=15546&key=<secret>' | jq .cdn
```

## Shared secret rotation

1. Generate a new secret string.
2. Update `SharedSecret` constant in both `Hash.ashx` and `Search.ashx`, redeploy.
3. Update `SLEDUJTETO_PROXY_KEY` in cr-web `.env` on production, restart container.

Order matters only on the switch second: the proxy enforces the new key as soon
as it lands on disk, so update cr-web's env immediately afterwards or a handful
of requests will see 403.

## Upstream quirks worth knowing

- `www.sledujteto.cz` playback is ASN-agnostic → user browsers can stream directly.
- `data{N}.sledujteto.cz` playback is blocked for datacenter ASNs (Hetzner/Oracle
  return `302 → /?flash=invalid-file`). See cr#549 for routing strategy.
- Search API `limit` is hard-capped at 50 by upstream.
- Catch-all queries (`la`, `en`, `s01e01`, …) all return the same ~71 850-upload
  ceiling, which `cr#597` uses for a full-catalog crawl.
