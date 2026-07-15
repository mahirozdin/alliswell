# ADR-0006 — Google OAuth flow, token encryption and the mirror queue

- **Status:** accepted (2026-07-15)
- **Tasks:** OPH-070…073 (Epic 08, BLUEPRINT §7)

## Context

Connecting Google Calendar means holding long-lived OAuth refresh tokens for
self-hosted users and pushing task changes into a third-party API. Three
security/architecture choices needed writing down (AGENTS.md rule 6/10).

## Decisions

1. **OAuth state = short-lived signed JWT, callback unauthenticated.** The
   consent redirect returns to `GET /integrations/google/callback` with no
   session attached (it's a browser navigation). Identity rides in `state`: a
   JWT signed with the existing access-token secret, claims
   `{sub, wsId, purpose: 'google_oauth'}`, 10-minute expiry. The `purpose`
   claim prevents replaying a normal session token as a state (tested). CSRF
   is covered because state is unforgeable and single-purpose; replay within
   10 minutes only repeats an idempotent upsert for the same user.

2. **Tokens encrypted at rest with AES-256-GCM** (`src/lib/crypto.js`):
   random 96-bit IV per value, auth tag verified on decrypt (tamper → throw),
   versioned wire format (`v1:iv:tag:ct`) for future rotation. The key is
   `CALENDAR_TOKEN_KEY` (64 hex chars); production refuses placeholder/short
   keys whenever Google is configured — same posture as the JWT secrets.
   Serializers have no code path that could leak ciphertext or plaintext;
   disconnect revokes at Google (best effort) and NULLs the ciphertext.

3. **Google identity from the token response's `id_token`, decoded without
   signature verification.** It is received directly from Google's token
   endpoint over TLS in the same exchange — verifying its signature would
   defend against Google impersonating Google. (If the id_token ever comes
   from anywhere else, verify it.)

4. **Mirror queue: BullMQ when Redis is up, an inline runner otherwise.**
   `recordSyncWrite` publishes per-entity events post-commit; task changes
   enqueue `{taskId}` jobs. BullMQ gives durability + exponential-backoff
   retries and dedupes PENDING jobs per task (`jobId: task-<id>`); because the
   worker always re-reads current state, bursts converge regardless. The
   inline fallback (dev without Redis, in-memory unit tests) runs jobs on a
   serialized promise chain with the same converge-on-current-state semantics
   and exposes `app.mirror.idle()` for deterministic tests. Known v1 limit:
   two API instances can process jobs for the same task concurrently; the
   duplicate-create window is narrowed by the extended-property re-link check
   and fully reconciled once inbound sync lands (OPH-074…076).

5. **No Google SDK.** The needed surface is six endpoints; a fetch-based
   client with configurable base URLs keeps tests hermetic (an in-process
   fake Google) and the dependency tree flat.

## Consequences

- Reconnecting is always safe: accounts upsert on (user, provider, google id),
  and `prompt=consent` guarantees a fresh refresh token.
- A rejected refresh token flips the account to `error` with
  `CALENDAR_ACCOUNT_REAUTH_REQUIRED` surfaced to clients — no silent decay.
- Key rotation requires decrypt-with-old/encrypt-with-new tooling (the `v1:`
  prefix leaves room); out of scope for v1.
