# Self-hosting AllisWell

Run your own AllisWell in a few minutes. Two published images, your own
database, your own domain — no account with anyone, no data leaving your server.

| Image                              | What it is                                                                                                           |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `ghcr.io/mahirozdin/alliswell-api` | The Node/Fastify API. Applies its own database migrations on start.                                                  |
| `ghcr.io/mahirozdin/alliswell-web` | The Flutter web app behind nginx. Reads your API address at **container start**, so one image fits every deployment. |

Both are published on every release for `linux/amd64` and `linux/arm64`, tagged
`X.Y.Z`, `X.Y` and `latest`.

---

## 1. Quick start

```bash
# 1. Get the stack definition and the config template
curl -O https://raw.githubusercontent.com/mahirozdin/alliswell/main/docker-compose.selfhost.yml
curl -o .env https://raw.githubusercontent.com/mahirozdin/alliswell/main/.env.selfhost.example

# 2. Generate the two required secrets (they must differ)
echo "JWT_ACCESS_SECRET=$(openssl rand -hex 32)"  >> .env
echo "JWT_REFRESH_SECRET=$(openssl rand -hex 32)" >> .env

# 3. Edit .env — set your domains and database passwords
#    ALLISWELL_API_URL, CORS_ORIGIN, DATABASE_PASSWORD, MYSQL_ROOT_PASSWORD
nano .env

# 4. Start
docker compose -f docker-compose.selfhost.yml up -d
```

That is it. The API creates the schema itself on first boot; open the web app,
register the first account, and you are running.

By default both containers bind to **loopback** (`127.0.0.1:3000` for the API,
`127.0.0.1:8080` for the web app) because they speak plain HTTP — put a TLS
proxy in front (§3).

## 2. The two addresses that must match

This is the only part people get wrong:

- **`ALLISWELL_API_URL`** — where the _browser_ reaches your API, e.g.
  `https://api.alliswell.example`. It is injected into the web bundle at
  container start.
- **`CORS_ORIGIN`** — where the web app is served from, e.g.
  `https://alliswell.example`. The API rejects browser calls from anywhere else.

If the app loads but every action fails with a network error, these two are
almost always inconsistent with the domains you actually browse to.

## 3. TLS / reverse proxy

Terminate TLS in front of the containers. Any proxy works; the two rules that
matter are **WebSocket upgrade** (live sync uses Socket.IO over WebSocket only)
and forwarding the client IP.

<details>
<summary>Caddy (simplest — automatic certificates)</summary>

```caddy
alliswell.example {
    reverse_proxy 127.0.0.1:8080
}

api.alliswell.example {
    reverse_proxy 127.0.0.1:3000
}
```

Caddy proxies WebSockets and sets `X-Forwarded-*` on its own.
</details>

<details>
<summary>Nginx</summary>

```nginx
server {
    server_name api.alliswell.example;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;   # WebSocket
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    server_name alliswell.example;
    location / { proxy_pass http://127.0.0.1:8080; }
}
```

</details>

<details>
<summary>Apache</summary>

Needs `mod_proxy`, `mod_proxy_http`, `mod_proxy_wstunnel` and `mod_rewrite`.

```apache
ProxyPreserveHost On
RewriteEngine On
RewriteCond %{HTTP:Upgrade} =websocket [NC]
RewriteRule ^/?(.*) ws://127.0.0.1:3000/$1 [P,L]
# AI chat streams as Server-Sent Events (docs/AI.md §3): the stream must reach
# the client UNBUFFERED, or "thinking…" and "broken" become indistinguishable.
# 1) keep mod_deflate away from event streams, 2) flush proxy packets as they
# arrive, 3) keep the idle timeout ABOVE the 15 s heartbeat (AI_HEARTBEAT_MS).
SetEnvIf Request_URI "/ai/chat$" no-gzip=1
ProxyPass        / http://127.0.0.1:3000/ flushpackets=on
ProxyPassReverse / http://127.0.0.1:3000/
ProxyTimeout 120
```

After changing the conf, prove it with a curl — buffered SSE looks exactly like
a hung model, so the proof is non-negotiable (the OPH-217 checklist): a POST to
`/api/v1/workspaces/…/ai/chat` with `curl -N` must print `event:` frames
INCREMENTALLY, not in one burst at the end.

</details>

Keep `TRUST_PROXY=true` (the default in the compose file) so the API reads the
real client IP from `X-Forwarded-For`. Without it every request looks like it
came from the proxy and the per-IP rate limits collapse into one shared bucket.

## 4. Upgrading — your data stays

```bash
docker compose -f docker-compose.selfhost.yml pull
docker compose -f docker-compose.selfhost.yml up -d
```

The API applies any new migrations on start. Migrations are **append-only**:
they add to the schema, never rewrite your rows. Your data lives in the named
volumes (`mysql_data`, `redis_data`) which survive `pull`, `up`, `down` and
image changes — only `docker compose down -v` destroys them.

Pin a version instead of following `latest` by setting `ALLISWELL_VERSION=0.4.0`
in `.env`.

**Back up before upgrading** (recommended):

```bash
docker compose -f docker-compose.selfhost.yml exec -T mysql \
  mysqldump -ualliswell -p"$DATABASE_PASSWORD" --single-transaction alliswell \
  | gzip > alliswell-backup-$(date +%F).sql.gz
```

## 5. Optional: file attachments (Cloudflare R2 / any S3)

Attachments are off until you configure a bucket; the app says so honestly
rather than failing. Bytes never pass through the API — it hands out
short-lived presigned URLs and the browser talks to the bucket directly, so
your server pays no bandwidth.

1. Create a bucket (R2, MinIO, B2, S3 — anything S3-compatible) and an API
   token scoped to it.
2. **Keep the bucket private.** Do not enable public access: the only way in is
   a presigned URL the API mints for an authenticated member.
3. Add a CORS rule so browsers may upload/download:
   ```json
   [
     {
       "AllowedOrigins": ["https://alliswell.example"],
       "AllowedMethods": ["GET", "PUT"],
       "AllowedHeaders": ["content-type"],
       "MaxAgeSeconds": 3600
     }
   ]
   ```
4. Fill `STORAGE_S3_*` in `.env` and restart. `STORAGE_MAX_UPLOAD_MB` (default 10) is enforced _before_ an upload starts, and an upload that lies about its
   size has its object deleted.

Details: [ATTACHMENTS.md](ATTACHMENTS.md).

## 6. Optional: Google Calendar two-way sync

1. Google Cloud Console → create an **OAuth client (Web application)**.
2. Add the redirect URI `https://api.alliswell.example/api/v1/integrations/google/callback`.
3. Set `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` and
   `CALENDAR_TOKEN_KEY` (`openssl rand -hex 32` — it encrypts the stored OAuth
   tokens) in `.env`, then restart.

Setting `GOOGLE_WEBHOOK_URL` additionally asks Google to push changes the moment
they happen. Google only pushes to a domain it has verified (Search Console →
Google Cloud domain verification); until then AllisWell polls every few minutes
on its own, so sync works either way.

## 6b. AI (on by default — BYOK)

The embedded AI track (Epic 20, [AI.md](AI.md)) is **bring-your-own-key**: users
add their own Anthropic / OpenAI / Gemini / OpenRouter key (or an Ollama base
URL) in Settings, so the instance needs no AI credentials of its own. What the
instance owner controls:

- **`AI_TOKEN_KEY`** (`openssl rand -hex 32`) encrypts stored user keys at rest.
  **Required in production while AI is enabled (the default)** — upgrading to
  v0.9.0 means either generating this key or setting `AI_ENABLED=false`.
- **`AI_ENABLED=false`** withdraws the feature honestly: every `/ai/*` endpoint
  answers 404 and the app hides every AI surface.
- Optional **instance-wide keys** (`AI_ANTHROPIC_API_KEY`, `AI_OPENAI_API_KEY`,
  `AI_GEMINI_API_KEY`, `AI_OPENROUTER_API_KEY`, `AI_OLLAMA_BASE_URL`) let
  members use the instance's provider account (`instance_env` connections);
  `AI_DAILY_TOKEN_CAP` bounds each user's daily spend on those.

## 6c. AI in Claude / ChatGPT (the MCP connector)

Users can add AllisWell to their own Claude or ChatGPT account so the AI works
against their workspace on their subscription — AllisWell spends no model money.
Set **`API_PUBLIC_URL`** to your instance's public origin (HTTPS in production);
it is the OAuth issuer and MCP resource identity. **`MCP_ENABLED=false`**
withdraws the connector (every `/mcp` and `/oauth/*` route answers 404). This
switch is **independent of `AI_ENABLED`**. Full setup and the tool list:
[MCP.md](MCP.md).

## 7. Using your own database or Redis

Point the API at them and drop the bundled services: set `DATABASE_HOST`,
`DATABASE_PORT`, `REDIS_URL` in `.env`. **MySQL 8.0+ and MariaDB 10.11+** are
both supported — the schema picks a compatible collation per server on its own.

## 8. Troubleshooting

| Symptom                                                       | Cause                                                                                                                           |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| App loads, everything fails with a network error              | `ALLISWELL_API_URL` / `CORS_ORIGIN` do not match your real domains (§2).                                                        |
| Changes do not appear on other devices until reload           | WebSocket upgrade is not passing through the proxy (§3).                                                                        |
| Everyone gets rate-limited at once                            | `TRUST_PROXY` is off behind a proxy (§3).                                                                                       |
| `Unknown collation` on first start                            | The database is older than MySQL 8.0 / MariaDB 10.11.                                                                           |
| Uploads fail only in the browser                              | The bucket has no CORS rule for your web origin (§5).                                                                           |
| `rsync`/`scp` to the server fails with "is your shell clean?" | A login script or MOTD prints to stdout on every SSH session; silence it (`>/dev/null 2>&1`) or copy with `tar \| ssh` instead. |

Check what the API thinks of itself at any time:

```bash
curl https://api.alliswell.example/health/ready
# {"status":"ok","checks":{"mysql":{"status":"up"},"redis":{"status":"up"}}}
```

`"status":"degraded"` names the failing dependency in the same response.
