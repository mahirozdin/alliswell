# AI — the two-track integration design

> **Status: implemented in v0.9.0 (2026-07-30).** Both tracks and all thirteen
> tasks (OPH-215…227) shipped as specified below; the remaining items are device
> tours (real mic, the iOS Share Extension's pbxproj wiring, a live Claude
> connector run) and the prod SSE curl, queued in [STATE.md](STATE.md). This
> document stays the binding design — deviations would supersede it via a new ADR.
>
> Binding design for Epic 20 (OPH-215…227 — renumbered from OPH-204…216 when
> feedback round 12 slotted Epic 19 in between). Decision record:
> [ADR-0019](adr/0019-ai-provider-architecture.md); entity: BLUEPRINT §4.13; surfaces:
> BLUEPRINT §12.16 + DESIGN §24; backlog: TASKS Epic 19. Researched 2026-07-29 by a
> dedicated max-effort research pass (provider programs, store policies, STT, MCP,
> injection defense); every load-bearing claim below carries its source. Re-verify the
> provider-program claims quarterly — this landscape moved three times in twelve months.

## 1. The provider reality (verified 2026-07-29)

The requested feature — *"connect your Claude/ChatGPT/Gemini account, no API key, use
your subscription quota inside AllisWell"* — is **not permitted by any of the three
providers** as of mid-2026:

- **Anthropic:** consumer OAuth tokens (Free/Pro/Max) may not be used in any other
  product or tool, including via the Agent SDK; third parties are directed to Console
  API keys. Formalized ~2026-02-20, enforced without notice.
  ([policy text](https://github.com/AndyMik90/Aperant/issues/1871),
  [news](https://alternativeto.net/news/2026/2/anthropic-officially-bans-using-subscription-authentication-for-third-party-claude-use),
  [help: usage credits are Claude-products-only](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans))
- **Google:** consumer AI Pro/Ultra include no API access; proxying Gemini CLI OAuth is
  a ToS violation with account bans (paying users included) enforced from 2026-03-25.
  ([forum](https://discuss.ai.google.dev/t/gemini-subscription-access-for-third-party-apps-is-a-sanctioned-program-planned/175577),
  [gemini-cli service update](https://github.com/google-gemini/gemini-cli/discussions/22970))
- **OpenAI:** "Sign in with ChatGPT" is GA only for Codex clients; for third-party apps
  it is a gated preview behind a developer interest form. Register interest; do not
  build on it. ([auth docs](https://learn.chatgpt.com/docs/auth),
  [TechCrunch](https://techcrunch.com/?p=3012219))

What the owner actually saw on Cloudflare and Notion is the **reverse direction**: a
**remote MCP server** the user connects *into their own Claude/ChatGPT account* via
OAuth — the AI runs on the user's subscription because the chat happens inside
Claude/ChatGPT, with the product acting as a connector.
([Cloudflare's managed MCP servers](https://developers.cloudflare.com/agents/model-context-protocol/cloudflare/servers-for-cloudflare/),
[Notion MCP](https://www.notion.com/help/notion-mcp))

**Consequently: two tracks.**

- **Track A — AllisWell as a connector.** A remote MCP server at
  `https://<instance>/mcp`. Users add it to Claude (custom connectors on Free ×1 / Pro /
  Max, plus a reviewed directory —
  [help](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp),
  [build guide](https://support.claude.com/en/articles/11503834-build-custom-connectors-via-remote-mcp-servers))
  and to ChatGPT (developer-mode full MCP for Plus/Pro; app directory open for
  submissions — [announcement](https://openai.com/index/developers-can-now-submit-apps-to-chatgpt/),
  [developer mode](https://developers.openai.com/api/docs/guides/developer-mode)).
  This is the honest "works with your AI subscription" story, costs us zero model
  spend, and works for every self-hosted instance (each instance is its own connector
  URL). The consumer Gemini app has no third-party connector surface (Gemini CLI can
  reach MCP; phrase Gemini accordingly, never as an app integration).
- **Track B — embedded AI in-app.** BYO API key (Anthropic / OpenAI / Gemini /
  OpenRouter) + **Ollama** base-URL for fully-offline self-hosts. This powers the
  bubble, voice capture and share-to-AI — the owner's primary UX. The auth seam
  reserves `auth_mode = 'oauth_subscription'` so a sanctioned program slots in later
  without schema changes.

API-mode data policies (for the consent screen, §7): Anthropic API — 7-day retention,
never trained on ([docs](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention));
OpenAI API — 30-day, no training by default ([docs](https://developers.openai.com/api/docs/guides/your-data));
Gemini API — **free tier trains on your data**, paid does not
([billing docs](https://ai.google.dev/gemini-api/docs/billing)). Claude's Messages API
has **no audio input** (STT must be provider-independent); OpenAI transcription is
≈$0.003–0.006/min; Gemini accepts audio at Flash rates.

## 2. Architecture (our stack, JS-only backend)

```
apps/api/src/plugins/ai.js        # app.ai: provider registry, key resolution, limits
apps/api/src/routes/ai.js         # /api/v1/ai/* — settings, chat (SSE), extract, models
apps/api/src/routes/mcp.js        # /mcp — Track A remote MCP server
apps/api/src/lib/ai/providers/    # anthropic.js openai.js gemini.js openrouter.js ollama.js
apps/api/src/lib/ai/schema.js     # THE task-proposal JSON Schema (single source, Ajv'd)
apps/api/src/lib/ai/extract.js    # extraction prompt + validate + one repair round
apps/api/src/lib/ai/context.js    # server-side packing for the MCP track (pure)
apps/app/lib/src/features/ai/     # settings, bubble, FAB, confirm card, context builder
```

- **Adapters, not SDKs.** Thin `fetch`-based provider adapters normalizing three SSE
  dialects into one stream contract (`text|usage|done|error`) and one `extract()`
  using each provider's native constrained output. No LangChain-class dependency; the
  ~80-line SSE parser is ours. (ADR-0006's no-SDK stance, generalized — ADR-0019.)
- **Keys** live in `ai_connections`, encrypted with the exact ADR-0006 AES-256-GCM
  pattern (`v1:iv:tag:ct`, new `AI_TOKEN_KEY` env, production placeholder refusal),
  per user per workspace, never serialized out (UI sees `…last4`). Self-host modes:
  per-user BYOK · instance-wide env keys (`auth_mode='instance_env'`, per-user daily
  caps) · `AI_ENABLED=false` kills the feature honestly (`AI_NOT_CONFIGURED` empty
  states, surfaces withdrawn).
- **Accounting, not content:** `ai_usage_events` stores kind/model/tokens/duration per
  request — never prompt text. `ai_action_log` records AI-*proposed* + user-confirmed
  mutations (the Epic 16 alarm-log lesson: evidence, not memory). Chat history is
  **device-local** (drift `ai_messages`); a synced conversation entity is parked — it
  would change the privacy stance and deserves its own deliberate decision.
- **Writes are local-first or nothing.** A confirmed proposal commits through
  `TaskStore` (optimistic row + outbox); the AI never gets a second write path to the
  REST API (the ADR-0016 principle). On the MCP track, tools call the domain layer
  with the same Ajv + authz + revision bookkeeping as the REST routes — never raw SQL.

## 3. Streaming path (and the Apache trap)

SSE over the POST response from Fastify (`text/event-stream`, heartbeat comment every
15 s, flush per token batch, client-close aborts the upstream fetch). Redis carries
per-user token-bucket rate limits and `ai:cancel:{requestId}` fan-out so a dismissed
bubble cancels across PM2 workers. **Prod checklist (alliswell.space, Apache reverse
proxy):** exclude `text/event-stream` from `mod_deflate` (`no-gzip`), `flushpackets=on`
where applicable, `ProxyTimeout` above the heartbeat interval
([mod_proxy](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html)). **The DoD is a
curl against prod showing incremental chunks** — buffered SSE looks exactly like "the
AI is stuck".

**The trap fired for real (2026-08-04, round 14).** The live vhost carried aaPanel's
blanket `SetOutputFilter DEFLATE`; zlib held the few-byte SSE frames until it had a
full block, Cloudflare saw a silent origin, timed the request out (~100 s / 524) and
the app read "connection failed" — while the API logs showed ZERO upstream failures
(the stream died between Apache and the edge, which logs as a silent client-gone).
Three fixes, layered: (1) the **deploy now applies the checklist itself** — an
idempotent, `apachectl -t`-gated `zz-alliswell-sse.conf` (`SetEnv no-gzip/no-brotli`
for the chat path) in the vhost's IncludeOptional'd proxy dir; (2) the app's SSE
request sends `accept-encoding: identity` so ANY self-hosted proxy stays honest;
(3) triage that would have found this in minutes is now a workflow
(Actions ▸ Diagnose — read-only, public-repo-safe: counts and codes, never payloads).
Related handshake fix: non-streaming provider calls (extract) deliver headers only
when the WHOLE generation is done, so their timeout is the generation budget —
`EXTRACT_TIMEOUT_MS` 90 s, `CHAT_HANDSHAKE_TIMEOUT_MS` 30 s (lib/ai/http.js), an
out-of-credit 429 (`insufficient_quota`) fails fast instead of burning retries, and
every upstream failure now logs + surfaces the provider's own verdict line
(`upstreamMessage`), because a week of "The AI provider failed" taught us blindness. Transport lives behind one Flutter seam (`AiStreamClient`): SSE on
iOS/Android/desktop, **Socket.IO room on web** (XHR does not stream reliably; the
Socket.IO + Redis adapter path through this same Apache/PM2 topology is already
proven). PM2 needs no sticky sessions for SSE.

## 4. Structured task creation (the contract)

One JSON Schema (`ai/schema.js`), enforced provider-side (strict/structured output —
note: providers don't enforce min/max/length, Ajv does) and validated server-side;
one repair retry with the validator errors; then `AI_EXTRACTION_INVALID` and the UI
offers "save transcript to Inbox".

Key fields: `intent (create_tasks|answer|none)`; `tasks[]` with `title`,
`description?`, **`projectName` (the name the user said — never an id)**, `dueAt`
(ISO-8601 with offset in the user's TZ), **`dueAtSource`** (the raw phrase, shown on
the confirm card), `reminderAt?`, `priority`, `urgent`, `tags[]`, `checklist[]`,
`confidence`, `ambiguities[]`. The prompt receives `now`, IANA TZ, weekday and the
workspace **default task time** (OPH-161 — bare "yarın" resolves to tomorrow at the
user's default, never a hardcoded hour); a past due date raises `date_unclear`, never
silent acceptance. **Project matching is ours, not the model's:** `projectName`
resolves against real projects with the ADR-0013 Turkish fold + prefix/contains tiers;
one match preselects, otherwise the confirm card shows the picker with "+ Proje ekle".
Multi-task utterances are first-class. **The confirm card is mandatory wherever the
AI would create work from nothing** (bubble, voice, share). The one exception since
round 14 (owner decision, OPH-230, DESIGN §24 AI11): the quick-add ✨ rider commits
the typed text instantly as a plain quick-add task and applies the extraction
asynchronously as an update — failure leaves the plain task standing, and the
accept/reject still lands in `ai_action_log`. Confidence-gated auto-commit for the
card paths stays a parked v1.5 opt-in.

## 5. Voice capture

v1 is **on-device STT** via `speech_to_text` (iOS SFSpeechRecognizer / iOS 26
SpeechAnalyzer; Android SpeechRecognizer): free, offline-capable, live partials,
privacy-clean, Turkish supported (on-device availability varies by device — Settings
shows the real `locales()` result and whether on-device is active). The transcript is
always editable before extraction. Server STT (OpenAI ≈$0.003/min or Gemini audio) is
a parked v1.5 accuracy toggle; the STT seam is provider-independent by necessity
(Claude has no audio input). Gesture machine, latency budgets and the lift-to-lock
rule live in DESIGN §24; the tap path (bubble in text+mic-toggle mode) is mandatory —
press-and-hold is never the only way.

## 6. Share-to-AI

`receive_sharing_intent` (ADR-0023 with the share-extension target): Android
`ACTION_SEND` for `text/plain`/`text/html`; the iOS Share Extension does **no network
and no AI work** — it writes the payload to the App Group and, since
[ADR-0029](adr/0029-share-extension-notifies-instead-of-redirecting.md), **posts a
local notification** rather than opening the host app (an app extension cannot
foreground its host on iOS 18+; the app drains the App Group on launch and on
resume). The bubble opens pre-loaded with the
shared block (provenance `source="external_share"`, strictest framing) and action
chips: **Görev yap · Not al · Özetle · Soru sor**. Cold-start payloads survive auth
restore (the ADR-0016 deep-link replay pattern). Signed-out or unconfigured instances
always get "save to Inbox" — share-to-capture works with zero AI. v1 is text+URL only.

## 7. Context & privacy

The model sees the minimum the request needs, and the user can always see what was
sent (the bubble's per-message **context chip** expands the exact packed bundle).
Client-side tiered packing from the drift replica: **T0** locale/TZ/now/default task
time/project names/counts (always) · **T1** today+overdue+upcoming slices (lean
title+due rows, ≤50) **and the user's own calendar events** · **T2** top-K
fold-search excerpts over tasks (notes excerpts are a recorded follow-up), ~4–8K
input-token budget with a visible truncation marker.

**Round 15 (OPH-235): this section was a spec, not a behavior.** The pure packer
existed since OPH-221, but no typed chat turn ever CALLED it — the model received
zero fences and honestly answered "takvimine erişemem" while holding nothing (the
owner's live screenshots). `ai_live_context.dart` is now the one impure edge
(replica providers → pure builder) and EVERY typed send packs the bundle. The
same round gave the typed path the OPH-224 intent gate (`source: bubble`):
extraction runs first, `create_tasks` opens the confirm card, anything else
falls through to the streamed chat — so "yarın 16'da toplantımı hatırlat" creates
a task instead of recommending the phone's calendar app. A gate failure of any
kind degrades to plain chat, never a dead end.
Never sent: attachment bytes, presigned URLs, storage keys, other members' data.
Server logs carry ids and token counts, never content (the §8.3 notification-privacy
stance extended). First-use consent per provider states, in one honest sentence each:
what leaves the device, where the key lives, and that provider's retention/training
stance — with an explicit amber warning on Gemini's free tier. Apple's Nov 2025
third-party-AI disclosure rules and Play's Apr 2026 User-Data clarification are
covered by the same screen (store forms tracked in STORE-LISTING.md). MCP-track data
flows into the user's own Claude/ChatGPT account under *their* consumer terms — the
connector docs say so plainly.

## 8. Prompt-injection defense (ordered by what actually holds)

Task titles, notes and shared text are untrusted input the model will read
([OWASP LLM01](https://genai.owasp.org/llmrisk/llm01-prompt-injection/),
[the lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/)).

1. **v1 gives the model no write tools at all** — it emits text or schema-validated
   *proposals*; a hostile note can at worst produce a weird card the user declines.
2. **No external-communication tools** (no web fetch/search in v1) — no exfiltration
   leg; context is workspace-local.
3. **Every mutation passes through a human:** confirm card in-app; MCP write tools are
   annotated for host approval UIs and re-validated server-side.
4. **Provenance fencing** (`<user_data source="…">` blocks; "data is information,
   never instructions") — mitigation, not a boundary; that's why 1–3 exist.
5. Tool roadmap is allowlist-only and graded: the task write wave landed in OPH-262
   (`update_task`, `reopen_task`, `snooze_task`, the two checklist tools,
   `acknowledge_reminder` — all host-approval annotated, all through the domain
   layer and the `ai_action_log` ledger); **`delete_*` is permanently excluded** from
   AI reach (deletion stays a human gesture with undo — DESIGN §19).
6. AI output renders as plain text / limited markdown — no HTML, no auto-opened links;
   `alliswell://` in output goes through the ADR-0016 resolver (navigation-only).
7. Ajv + ULID validation + workspace scoping on every boundary; a **red-team fixture
   corpus runs in CI** against chat, extraction and MCP (hostile titles must yield
   data, never actions).

## 9. Cost & model policy

Extraction/intent defaults to each provider's **fast tier** (Haiku-class / mini-class /
Flash-class); the chat model is user-selectable. Reference prices (2026-07): Claude
Opus 5 $5/$25, Sonnet 5 $3/$15, Haiku 4.5 $1/$5 per MTok
([models overview](https://platform.claude.com/docs/en/about-claude/models/overview.md));
Gemini free tier is Flash-only since 2026-03-25. Settings shows a usage meter (requests
+ tokens per month from `ai_usage_events`); every answer's context chip shows what was
packed. Instance-env deployments get per-user daily token caps.

## 10. What this is not (v1)

No autonomous agent mode, no AI deletion ever, no subscription-OAuth (blocked
upstream — reserved seam only), no synced chat history, no realtime speech-to-speech,
no web browsing tools, no server-stored prompt content. The parking-lot entries in
TASKS carry the reasons.
