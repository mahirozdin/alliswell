# ADR-0019 — AI provider architecture: two tracks, BYOK-first, adapters not SDKs

> **One dated fact below has since changed.** The context paragraph calls the app
> "self-hostable (AGPL)" because that was true when this was written in July 2026.
> AllisWell moved to **PolyForm Noncommercial 1.0.0** at v1.0.0
> ([ADR-0024](0024-license-polyform-noncommercial.md)); releases up to and
> including v0.9.0 remain AGPL-3.0 for anyone who received them. Self-hostable is
> still true, and nothing in the decision depended on which licence it was. The
> record below is kept as written; it is history, not current policy.

- **Status:** Accepted
- **Date:** 2026-07-29 (planning, request round 11 — researched by a dedicated
  max-effort pass; evidence links in [AI.md](../AI.md) §1)
- **Related task:** Epic 20 (OPH-215…OPH-227; renumbered from OPH-204…216 when
  feedback round 12 inserted Epic 19) — request round 11 #2
- **Related:** [ADR-0006](0006-google-oauth-token-crypto-and-mirror-queue.md) (token
  crypto + the no-SDK precedent this generalizes),
  [ADR-0013](0013-local-first-search.md) (the fold matching extraction reuses),
  [ADR-0016](0016-in-app-url-routing-and-widget-actions.md) (the "no second write
  path" principle), BLUEPRINT §4.13/§12.16, DESIGN §24. Follow-ups at implementation
  time: ADR-0022 (MCP server), ADR-0023 (STT + share-intent dependencies) —
  0020/0021 were claimed by round 12 (recurrence engine, calendar mirror v2).

## Context

The owner's request: connect your own Claude / ChatGPT / Gemini account **without an
API key**, chat with your workspace data, speak tasks into existence, share any text
into the AI. Verified reality (2026-07): **no provider permits third-party use of
consumer-subscription auth** — Anthropic bans it outright, Google enforces bans for
it, OpenAI gates "Sign in with ChatGPT" behind an interest form. What Cloudflare and
Notion actually ship is the reverse direction: a **remote MCP server** users connect
into their own AI account. Meanwhile the app is self-hostable (AGPL), local-first,
JS-only on the server, and privacy-led — any design must survive all of that.

## Decision

1. **Two tracks.** Track A: an AllisWell **remote MCP server** (`/mcp`) so users add
   AllisWell to their own Claude/ChatGPT — the sanctioned "works with your
   subscription" story. Track B: **embedded in-app AI with BYO API key** (Anthropic,
   OpenAI, Gemini, OpenRouter, Ollama) powering the bubble, voice capture and
   share-to-AI. Both tracks share the domain layer, the proposal schema and the
   audit log.
2. **Adapters, not SDKs.** Thin `fetch`-based provider adapters behind one contract
   (`capabilities` / `chatStream` / `extract`), normalizing the three SSE dialects
   and the three constrained-output mechanisms. No LangChain-class framework, no
   provider SDKs; the SSE parser (~80 lines) is ours. Tests run one shared contract
   suite against in-process fakes (the ADR-0006 §5 pattern).
3. **BYOK-first, future-proofed seam.** `ai_connections.auth_mode` is
   `api_key | instance_env | oauth_subscription` — the last is **reserved, unused**,
   so a sanctioned subscription program later becomes a new auth mode, not a schema
   change. Keys are encrypted with the ADR-0006 AES-256-GCM pattern under a new
   `AI_TOKEN_KEY`, never serialized out.
4. **The AI proposes; the proven write path commits.** Embedded AI has **no write
   tools in v1**: it emits schema-validated proposals (single Ajv'd JSON Schema,
   `ai/schema.js`) that a human confirms; confirmed tasks commit through
   `TaskStore`'s optimistic-row + outbox path. MCP write tools call the domain layer
   with REST-equivalent validation. Deletion is permanently outside AI reach.
5. **Accounting without content.** `ai_usage_events` (tokens/model/duration) and
   `ai_action_log` (proposal + accepted) are stored; prompt content is not. Chat
   history is device-local (drift), not a sync entity.
6. **Self-host is a first-class mode:** per-user BYOK, or instance-wide env keys
   with per-user caps, or `AI_ENABLED=false` withdrawing every AI surface honestly;
   Ollama covers fully-offline instances.

## Alternatives considered

- **Build subscription-OAuth anyway** (reverse-engineered tokens, CLI proxies).
  Rejected: explicit ToS violations; Google demonstrably bans paying users; it would
  put our users' accounts at risk for a feature we cannot support honestly.
- **Hosted "AllisWell AI" metered tier** (we hold keys, bill users). Deferred to the
  parking lot as a business decision — it is additive on this architecture (one more
  `auth_mode`), so nothing is lost by waiting.
- **Provider SDKs / LangChain.** Rejected: three heavyweight dependency trees for
  three HTTP APIs we call with a handful of shapes; the repo's precedent (ADR-0006)
  is fetch + hermetic fakes, and it has paid off in test speed and auditability.
- **Server-side context assembly for the embedded track.** Rejected for v1: the
  client already holds the full replica and the fold search (ADR-0013); packing on
  device keeps the server thin, works offline, and makes "show me what was sent"
  trivially honest. The MCP track necessarily packs server-side; that code stays
  separate and pure.
- **WebSocket-only streaming.** Rejected as the default: SSE is simpler per request
  and cache/proxy-legible; but the transport lives behind one Flutter seam and web
  uses the existing Socket.IO room path, so the decision is reversible per platform.

## Consequences

- Marketing must tell the truth: "Works with Claude / ChatGPT" means the MCP
  connector; Gemini is "API key" (no consumer-app connector surface exists). README
  claims are audited against shipped reality in OPH-216.
- A quarterly provider-policy re-check becomes standing work (STATE "waiting on
  user" carries the OpenAI interest-form registration).
- The Apache reverse proxy on prod must be configured for SSE (no-gzip,
  flushpackets, timeouts) and the deploy checklist becomes part of OPH-217's DoD —
  with a curl-against-prod proof, because buffered SSE is indistinguishable from a
  hung model. _(Editorial fix 2026-07-30: originally said "OPH-206", a pre-renumber
  id from before round 12 slotted Epic 19 in.)_
- Prompt-injection defense is architectural (no tools, no external comms, human
  confirm) rather than prompt-cosmetic; a red-team corpus lives in CI from v1.
- Five adapters is more surface than one, but the contract suite keeps them honest,
  and the seam is where a future subscription program, a sixth provider, or a local
  model lands without another redesign.
