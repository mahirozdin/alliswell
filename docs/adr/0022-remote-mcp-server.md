# ADR-0022 — Remote MCP server: hand-rolled Streamable HTTP behind our own OAuth 2.1

- **Status:** Accepted
- **Date:** 2026-07-30
- **Related task:** OPH-218 (Epic 20, Track A)
- **Related:** [ADR-0019](0019-ai-provider-architecture.md) (the two tracks + the
  no-SDK stance this extends to the server side), [ADR-0013](0013-local-first-search.md)
  (the fold the `search` tool reuses), [ADR-0016](0016-in-app-url-routing-and-widget-actions.md)
  (the "no second write path" principle), [ADR-0006](0006-google-oauth-token-crypto-and-mirror-queue.md)
  (fetch-not-SDK + hash-only token storage precedents), [AI.md](../AI.md) §1–2/§8.

## Context

Claude custom connectors and ChatGPT's developer mode both speak MCP over
**Streamable HTTP**, and both authenticate against the server's **own OAuth 2.1
authorization server** with dynamic client registration (MCP authorization spec
2025-06-18: RFC 8414 + RFC 9728 discovery, RFC 7591 DCR, PKCE mandatory). The
API is self-hostable, JS-only, Fastify 5, JWT-bearer auth with no cookies, no
session store, and no OAuth-server infrastructure; every instance must be its
own connector at `https://<instance>/mcp` with zero external services. AI.md §2
and §8 bind the tool surface: MCP is a client of the domain layer — never raw
SQL; every write goes through the same Ajv + authz + revision path as REST;
hostile titles are data, never instructions.

## Decision

1. **Hand-rolled MCP server, no SDK.** Protocol pinned to `2025-06-18`
   (`2025-03-26` accepted at negotiation, minus its batching): stateless
   Streamable HTTP — `POST /mcp` carries one JSON-RPC 2.0 message and answers
   JSON; `GET`/`DELETE /mcp` answer 405; no `Mcp-Session-Id` is ever issued
   (legal when the server assigns none — there are no server-initiated
   messages in v1). This extends ADR-0019's adapters-not-SDKs stance: the
   method set is small and fixed, and `@modelcontextprotocol/sdk` would add a
   zod-sized dependency tree plus a transport model that wants raw req/res
   outside Fastify's schema/rate-limit lifecycle.
2. **Our API becomes a minimal OAuth 2.1 authorization server** for the single
   audience "this instance's MCP endpoint": RFC 8414/9728 discovery documents,
   open dynamic client registration, a PKCE-S256-only authorization-code flow
   with a server-rendered login+consent page (argon2 verify against the
   existing `users` table, the timing-safe-dummy pattern), **opaque
   HMAC-hashed tokens** in new `oauth_*` tables (the `refresh_tokens` pattern
   with domain separators), refresh rotation with family-wide revocation on
   reuse, and an RFC 7009 revocation endpoint. The existing JWT/refresh app
   auth is untouched.
3. **Tool surface v1 (allowlist; no delete, permanently):** `search`,
   `list_tasks`, `get_task`, `get_note`, `get_project`, `create_task`,
   `complete_task`; resources `alliswell://views/today` and
   `alliswell://views/overdue`. Write tools carry MCP annotations for host
   approval UIs and are re-validated server-side (Ajv, workspace scoping, row
   caps). `create_task` consumes **OPH-219's proposal item schema** — the
   single source — and resolves `projectName` with the shared fold matcher;
   an ambiguous or unknown project **declines to create** and returns
   candidates instead (the honest MCP twin of the confirm-card picker).
   Loosening the no-delete invariant requires a new ADR (the Epic 20 closing
   rule).
4. **Writes commit through the domain layer.** `createTask`/`completeTask`/
   `getTaskDetail` are extracted to `src/db/tasks.js` and REST delegates to
   them, so MCP and REST are one implementation (recordSyncWrite + revision
   stamp + reminder reconcile in one transaction). Every MCP write records
   `ai_action_log (source='mcp')` and an idempotency row in `mcp_mutations`
   (its own table — `client_mutations` is `char(26)`-keyed and belongs to the
   sync push protocol).
5. **Independent gate:** `MCP_ENABLED` (default true) + `API_PUBLIC_URL`.
   `AI_ENABLED` governs only `/ai/*` — the MCP track spends no model money,
   stores no provider keys, and moves data only into a client the user
   personally connected, so coupling the switches would force admins into
   all-or-nothing. Unconfigured (no public URL in production) → every
   MCP/OAuth route answers 404 `MCP_NOT_CONFIGURED`; **never a boot failure**
   (upgraded deployments must not brick).
6. **Search is fold-guaranteed on titles/names** (a JS `foldSearchText` pass
   over workspace titles — closing the documented `ı` gap of the FULLTEXT
   path for the fields that matter most), engine-matched on bodies
   (FULLTEXT), merged by tier. The gap that remains on bodies is documented
   in the tool description of honesty.

## Alternatives considered

- **`@modelcontextprotocol/sdk`** — protocol correctness for free, but a new
  dependency category for one fixed method set, and its transports bypass
  Fastify's validation/rate-limit hooks. The Inspector run is the standing
  conformance canary instead.
- **JWT access tokens for MCP** — stateless, but "I removed the connector"
  must actually revoke; opaque hashed rows match the proven refresh-token
  pattern and make audience/scope a stored column. One indexed SELECT per
  request is our normal cost.
- **Reusing app JWTs at `/mcp`** — wrong audience, no consent step, no
  per-connector revocation; tokens would outlive the connector relationship.
- **Gating MCP under `AI_ENABLED`** — rejected; argued in Decision 5.
- **Sessions + GET/SSE server push** — no server-initiated messages exist in
  v1; stateless is simpler across PM2 workers and avoids the Apache
  SSE-buffering trap entirely on this path.
- **Reusing `client_mutations` for idempotency** — its key columns are sync
  ULIDs; a free-form `idempotencyKey` gets its own `mcp_mutations` ledger.

## Consequences

- Every instance ships an OAuth AS: the login form lives on the API origin and
  carries the same per-IP rate limits as `/auth/login`; open DCR is
  rate-limited, and stale-client pruning is future gc work (account-gc
  precedent).
- Protocol conformance is ours to maintain: pinned versions, an MCP Inspector
  runbook, and the quarterly provider re-check (already standing) cover drift.
- ChatGPT's connector *directory* surfaces may additionally require a fixed
  `search`/`fetch` result contract; our `search` output already carries
  `type/id/title`, and a spec-shaped `fetch` alias is deferred to OPH-227's
  directory applications.
- v1.5 write tools (`reschedule_task`, …) slot into the same dispatch +
  annotation + audit path; `delete_*` never does.
