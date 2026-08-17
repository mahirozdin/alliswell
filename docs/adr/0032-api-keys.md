# ADR-0032 — API keys: plain Bearer, one workspace, no scopes in v1

- **Status:** Accepted
- **Date:** 2026-08-17
- **Related task:** OPH-264 (Epic 25, P3; gate for OPH-265 and OPH-266)
- **Related:** [ADR-0022](0022-remote-mcp-server.md) (the OAuth 2.1 server this
  deliberately does NOT reuse, and whose hash-only token storage it does),
  [ADR-0006](0006-google-oauth-token-crypto-and-mirror-queue.md) (hash-only
  storage precedent), [SECURITY.md](../SECURITY.md),
  [issue #3](https://github.com/mahirozdin/alliswell/issues/3)

## Context

Issue #3: *"Allow user to create API keys and expose REST API to
applications."* Someone self-hosting AllisWell wants a shell script, a Home
Assistant automation or a cron job to file a task — with no browser, no
consent screen and no token refresh.

The API already has two ways in, and neither fits:

- **JWT access tokens** live 15 minutes and are refreshed by an opaque rotating
  refresh token. A script would have to implement the refresh dance, store a
  rotating secret, and handle family revocation. That is a client library, not
  a curl line.
- **The MCP OAuth server** (ADR-0022) is exactly right for Claude and ChatGPT —
  dynamic registration, PKCE, a consent page — and exactly wrong for a cron
  job, which has no browser to consent in.

Meanwhile the API surface it would authenticate is already uniform: **every one
of the 78 routes** goes through `onRequest: [app.authenticate]` and reads
`request.user`. Whatever mints `request.user` mints access to all of it.

## Decision

1. **A plain Bearer secret, no OAuth.** An API key is `awk_` +
   `newOpaqueToken(32)` (43 base64url chars), sent as
   `Authorization: Bearer awk_…`. No grant, no refresh, no expiry unless the
   user picks one. The prefix is what makes the whole design cheap: the
   authenticator can tell key from JWT before doing any work, and a leaked key
   is greppable in logs and in GitHub's secret scanning.
2. **Hash-only at rest, shown once.** Storage is `HMAC-SHA256(secret,
   "api-key:" + token)` — the `refresh_tokens` / `oauth_tokens` pattern with
   its own domain separator, so a database dump can neither read nor forge a
   key. The plaintext exists in exactly one HTTP response, ever. A `key_prefix`
   (first 12 characters) is stored in the clear so the list screen can say
   *which* key without being able to use it.
   *Deviation from the task sketch, recorded:* it calls
   `hashApiKey(token, secret)`, not `hashMcpToken('api_key', …)`. Same pattern,
   same file, same secret — but an API key is not an MCP token, and a digest
   domain-separated as `mcp-api_key:` would tell every future reader something
   untrue about where these keys come from.
3. **No scopes in v1.** A key carries its owner's full authority over ONE
   workspace. Scopes that nobody has asked for yet would be a permission model
   invented in advance, and a half-enforced one is worse than none. The
   workspace binding is the real boundary and it is checked on every
   workspace-scoped route (`requireWorkspaceMember` compares the key's
   workspace to the target and answers 403 `AUTH_APIKEY_WORKSPACE`).
   Adding scopes later is an additive column plus a revision of this ADR.
4. **Three doors stay shut to keys** (defence in depth, not paranoia):
   - **Account deletion** (`DELETE /me`, `/me/deletion/cancel`) — a leaked key
     must not be able to erase the account it leaked from.
   - **`/ai/*`** — those routes hold BYOK provider secrets and spend the user's
     model money; a key is for the user's own data, not their wallet.
   - **Key management itself** — a key cannot mint or revoke keys. Otherwise
     one leaked key is permanent: the attacker issues a second one, and
     revoking the first changes nothing.
   Everything else — tasks, notes, projects, tags, files, sync, calendar — is
   open to a key, because that is the point.
5. **Per-key rate limiting.** Key-authenticated requests are bucketed by the
   key's digest rather than by IP (`API_KEY_RATE_LIMIT_MAX`, default 300/min —
   the same ceiling as the global per-IP limit). A script behind the same NAT
   as its user must not consume that user's budget, and one runaway key must
   not throttle every other client of the instance.
6. **`last_used_at`, throttled to ~1/minute.** The list screen answers "is this
   key still in use, can I revoke it?", which is what makes revocation
   something a person will actually do. Stamping it on every request would
   double the write load of a scripted client for no extra truth — the MCP
   token pattern (ADR-0022) verbatim.

## Alternatives considered

- **Reuse the MCP OAuth server with a client-credentials grant** — a real OAuth
  answer, and it moves the secret problem instead of solving it: the client
  secret is still a static string in a cron job, plus an extra round trip per
  run and a second token store. The consent page, the part that makes OAuth
  worth it, is precisely what a headless script cannot use.
- **JWT API keys (long-lived, signed, stateless)** — no database lookup, but
  "I revoked that key" would be a lie until expiry, and there is no per-key
  `last_used_at`. Revocation is the entire point of a key list.
- **Scopes in v1** (`tasks:read`, `notes:write`, …) — deferred, argued in
  Decision 3.
- **Keys bound to the account rather than a workspace** — simpler to mint,
  but then a key handed to a household automation reaches every workspace the
  user is in. The workspace binding IS the blast radius.
- **A separate `/api/v2` surface for key auth** — the alternative to dual-mode
  `authenticate`. It would double every route for one authentication detail;
  the whole reason dual-mode is cheap is that all 78 routes already read
  `request.user` and nothing else.

## Consequences

- `authenticate` gains a branch, so it is now the single most security-critical
  function in the codebase: it decides `request.user` for every route. Its two
  modes are tested separately, and the JWT path is byte-for-byte unchanged
  (the existing suites are the regression proof).
- A key is as powerful as its owner. The UI (OPH-265) must say so plainly at
  creation time, and SECURITY.md documents the model.
- `revoked_at` and `expires_at` are checked on every request, which costs one
  indexed lookup per call — the same cost the MCP path already pays.
- Self-hosters get a documented REST surface in OPH-265 (`docs/API.md`);
  without it, keys would authenticate an API nobody can read.
- Rotation is manual in v1: create the new key, switch the client, revoke the
  old one. Automatic rotation needs a client that can be told about it, which
  is the same missing piece as scopes.
