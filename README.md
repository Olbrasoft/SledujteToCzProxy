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
`sledujteto.aspfree.cz`).

**Webroot is `/www/`** on the FTP server, not `/`. Uploads to `/` are accepted
but not served. The FTP filesystem is case-sensitive Linux and the existing
handler filenames are lowercase (`hash.ashx`, `search.ashx`) — match that on
upload or IIS will 404.

Upload order matters when rotating secrets: push `secrets.config` first,
then the `.ashx` handlers (which read the new value), and finally
`web.config` (which points to `secrets.config` via `configSource`).

```bash
SLEDUJTETO_FTP_PASS='<from aspone-cz.md>'
cd src/SledujteToCzProxy
curl -T secrets.config --user "sledujteto.aspfree.cz:$SLEDUJTETO_FTP_PASS" \
  "ftp://web1.aspfree.cz/www/secrets.config"
curl -T Hash.ashx --user "sledujteto.aspfree.cz:$SLEDUJTETO_FTP_PASS" \
  "ftp://web1.aspfree.cz/www/hash.ashx"
curl -T Search.ashx --user "sledujteto.aspfree.cz:$SLEDUJTETO_FTP_PASS" \
  "ftp://web1.aspfree.cz/www/search.ashx"
curl -T web.config --user "sledujteto.aspfree.cz:$SLEDUJTETO_FTP_PASS" \
  "ftp://web1.aspfree.cz/www/web.config"
```

**Note on HTTPS:** aspfree.cz's 443 port has been observed timing out while
80 responds normally. Plain HTTP is currently the reliable transport — the
proxy is public-read-only by design (key enforces access, not confidentiality
of the JSON body), so this is tolerable but worth fixing upstream if they
start charging for it.

Smoke test:

```bash
# Without key → 403
curl -sI 'https://sledujteto.aspfree.cz/Hash.ashx?id=15546'
# With key → 200 + JSON
curl -s 'https://sledujteto.aspfree.cz/Hash.ashx?id=15546&key=<secret>' | jq .cdn
```

## Shared secret rotation

Secret lives in `secrets.config` (gitignored, referenced from `web.config`
via `configSource`). Never commit it to source.

1. Generate a new secret string (≥ 32 chars, alphanumeric).
2. Update `<add key="SharedSecret" value="…"/>` in local
   `src/SledujteToCzProxy/secrets.config`.
3. FTP upload the new `secrets.config` to the webroot (IIS picks it up on the
   next request — no app pool recycle needed for `configSource` changes).
4. Update `SLEDUJTETO_PROXY_KEY` in cr-web `.env` on production (Hetzner)
   and restart the container.
5. Update the `SLEDUJTETO_PROXY_KEY` GitHub Actions secret in every repo that
   uses the proxy (`Olbrasoft/sledujtetocz-to-prehrajto`, etc.).
6. Record the new value in `~/Dokumenty/přístupy/aspone-cz.md` (local-only).

Order matters on the switch second: the proxy enforces the new key as soon
as `secrets.config` lands on disk, so update cr-web's env immediately
afterwards or a handful of requests will see 403.

## Upstream quirks worth knowing

- `www.sledujteto.cz` playback is ASN-agnostic → user browsers can stream directly.
- `data{N}.sledujteto.cz` playback is blocked for datacenter ASNs (Hetzner/Oracle
  return `302 → /?flash=invalid-file`). See cr#549 for routing strategy.
- Search API `limit` is hard-capped at 50 by upstream.
- Catch-all queries (`la`, `en`, `s01e01`, …) all return the same ~71 850-upload
  ceiling, which `cr#597` uses for a full-catalog crawl.
