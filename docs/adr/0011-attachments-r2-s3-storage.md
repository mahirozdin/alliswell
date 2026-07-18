# ADR-0011 — Attachments: S3-compatible object storage (Cloudflare R2), presigned direct transfer, pull-only sync entity

- **Status:** accepted (2026-07-18)
- **Tasks:** Epic 14 (OPH-150…157)
- **Binding plan:** [ATTACHMENTS.md](../ATTACHMENTS.md)
- **Builds on:** [ADR-0008](0008-external-calendar-events.md) (pull-only entity model),
  [ADR-0006](0006-google-oauth-token-crypto-and-mirror-queue.md) (optional-integration + queue patterns)

## Context

Feedback round 7 (2026-07-18): Mahir wants files on everything — image/video
attachments on tasks, inline images/videos in notes, a "Files" tab on project
detail that behaves like a simple file manager (upload/download/rename/delete),
any file type, backed by **Cloudflare R2**. Attachments were parked in the v2
list ("S3-compatible storage") since day 1; this pulls them forward into v0.3.0.

Binary storage is the first piece of state that does NOT live in MySQL, so the
decisions below are mostly about keeping the existing invariants (canonical
MySQL, offline-first replicas, honest UI) true next to a second store.

## Decision

1. **Speak the S3 protocol; document R2 as the primary provider.** One driver
   (`@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`, region `auto`,
   path-style) covers R2, MinIO (dev/CI) and any S3-compatible store. No
   Cloudflare-proprietary API. New dependency category → this ADR.
2. **Bytes go direct, metadata goes through the API.** Uploads are presigned
   PUTs from the client to the bucket; downloads are presigned GETs. The API
   never proxies file bodies — R2 egress is free, self-hosted VPSes are small,
   and the authorization decision is in the minting of the URL. Upload is a
   3-step handshake: `init` (row `status='uploading'`, invisible to sync) →
   client PUT → `complete` (HeadObject verifies existence + size → `ready`).
3. **`files` is one polymorphic table** (`target_type` ∈ project|task|note +
   `target_id`), storage keys are opaque (`ws/{wsId}/{fileId}` — rename is
   metadata-only), soft delete + revision like every entity.
4. **`file` is a pull-only sync entity** (ADR-0008 model): `ready` rows
   snapshot to replicas so attachment lists and the project Files tab work
   offline; pushes answer `SYNC_UNSUPPORTED_ENTITY` — an upload is inherently
   online, so no outbox lane exists to lie about. Writes are REST, followed by
   `syncNow()` to converge the replica (the archive-flow pattern).
5. **No orphaned bytes:** entity deletion (task subtree, note, project — REST
   and sync-push paths) cascades soft-deletes to the entity's files in the same
   transaction (one revision each) and enqueues object deletion on the existing
   queue runner (BullMQ/inline, `jobKey = storage_key`, 404 = done). A sweep
   reaps `uploading` rows older than 24 h. Archiving deletes nothing.
6. **The feature is optional config** (Google-integration precedent): without
   `STORAGE_S3_*` env the endpoints answer `STORAGE_NOT_CONFIGURED`, the app
   shows honest empty states, and nothing else changes.
7. **Note embeds reference files by app scheme**: Quill image/video embeds
   carry `alliswell://file/{fileId}` (ADR-0003 naming) — never a presigned URL.
   Markdown export (server `delta.js` and the app's fixture-parity converter)
   maps embeds to `![name](alliswell://file/{id})` / `[name](…)`; plain-text
   extraction keeps skipping embeds.

## Consequences

- Web browsers preflight the direct PUT/GET, so **R2 bucket CORS setup is a
  documented self-hoster requirement** (ATTACHMENTS.md §8); native platforms
  need nothing. MinIO in dev is permissive out of the box.
- Integration tests get a **MinIO service** (docker-compose + CI) and exercise
  the real presigned flow; unit tests inject a fake storage like `db`/`redis`.
- Size enforcement is complete-time (HeadObject), not signature-time — a lying
  client wastes only its own bandwidth on an object that is deleted before it
  ever becomes visible. Deliberate; revisit only with multipart (v2).
- The app gains its first binary-transfer dependency surface: `file_picker`
  (PHPicker path — no new iOS permission strings) behind a provider seam like
  `urlLauncherProvider`; dio's `onSendProgress` drives visible upload progress.
  Camera capture, inline video playback, local binary cache: parked.
- Presigned URLs expire (default 1 h) and are minted per request — replicas
  and exports never contain URLs, only ids, so nothing in a backup or another
  device goes stale.

## Alternatives considered

- **Proxy uploads/downloads through Fastify** — simplest client, no CORS, but
  doubles bandwidth on self-hosted boxes, ties the event loop to video
  streams, and buys nothing R2's free egress doesn't already give. Rejected.
- **Cloudflare-native API / Workers presign** — couples the open-source
  product to one vendor; S3 compatibility is the whole point of R2. Rejected.
- **Files as a full push/pull sync entity** — an outbox lane for uploads would
  queue metadata for binaries that don't exist anywhere; offline upload is a
  promise we cannot keep. Rejected (pull-only).
- **Local-disk storage driver for no-R2 self-hosters** — tempting, but it
  reintroduces proxied bytes, backup questions and multi-instance file
  affinity; MinIO is a one-container answer for "I want it all on my box".
  Parked, not rejected — the driver seam would allow it later.
