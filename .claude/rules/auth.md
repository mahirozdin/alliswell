---
paths:
  - "apps/api/src/routes/auth.js"
  - "apps/api/src/routes/api-keys.js"
  - "apps/api/src/routes/oauth.js"
  - "apps/api/src/plugins/auth.js"
  - "apps/api/src/db/sessions.js"
  - "apps/api/src/db/identities.js"
  - "apps/api/src/db/totp.js"
  - "apps/api/src/lib/{tokens,api-keys,crypto,totp,sign-in-factors,oauth-identity,oauth-cimd}.js"
---
# Auth, sessions, keys — critical path

A hole here is a breach, and a session bug locks people out of their data.

- **K1 extra:** `npm run verify:task -- apps/api/test/integration/auth.test.js
  apps/api/test/integration/auth-refresh.test.js apps/api/test/integration/auth-me.test.js
  apps/api/test/integration/sessions.test.js apps/api/test/integration/mfa.test.js`.
- **Invariants:** I-07 (no secrets in git; OAuth tokens encrypted — BLUEPRINT §15.3). API keys
  `awk_` plain Bearer, shown once, HMAC-SHA256 hash; `/auth/*`, account deletion, `/ai/*` and
  key management are closed to keys (ADR-0032). Each secret class has its own key
  (`AUTH_TOTP_KEY`…); a password change ends every session (ADR-0006). Errors carry stable
  `code`s and never leak internals.
- **Traps (docs/LESSONS.md `security`):**
  - `app.rejectApiKeys` is a preHandler (after authenticate); the rate limiter runs before
    identity → its `keyGenerator` reads the header; the bucket is the identity (ADR-0045).
  - `routes/oauth.js` `renderPage` escapes the title but prints the body raw, and helmet's
    CSP is off → escape every interpolation, pick a CSP, test with a payload.
  - Two OAuths face opposite ways: `routes/oauth.js` is MCP's OAuth 2.1 server,
    `lib/oauth-identity.js` checks Google/Apple ID tokens. Every sign-in door goes through
    `lib/sign-in-factors.js` before it writes (OPH-381).
  - A session is a `refresh_tokens` `family_id`; list/revoke per family.
- **Detail:** [SECURITY.md](../../SECURITY.md), ADR-0026, ADR-0032, ADR-0047, ADR-0049.
