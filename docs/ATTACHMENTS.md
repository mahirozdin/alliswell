# ATTACHMENTS — Files on tasks, notes & projects (binding design plan)

> Plan for **Epic 14 (OPH-150…157)**. This is the source of truth for AllisWell's
> file/attachment feature, the way [WIDGETS.md](WIDGETS.md) is for widgets and
> [NOTIFICATIONS.md](NOTIFICATIONS.md) is for reminders. Architecture decision:
> [ADR-0011](adr/0011-attachments-r2-s3-storage.md). Product spec:
> [BLUEPRINT.md §4.10, §12.3–12.5](BLUEPRINT.md).
>
> Designed 2026-07-18 (feedback round 7). Primary storage target: **Cloudflare R2**
> via its S3-compatible API; dev/CI stand-in: **MinIO**. SDK: `@aws-sdk/client-s3`
> v3 + `@aws-sdk/s3-request-presigner`.

## 0a. Implementation status (2026-07-18)

| Piece | Status |
| --- | --- |
| API: storage plugin (R2/S3), MinIO dev/CI, status endpoint | ✅ done + tested (OPH-150) |
| API: upload lifecycle (init → presigned PUT → verify), GC + sweep | ✅ done + tested (OPH-151) |
| API: read surface, pull-only sync, delete cascades, rename, md embeds | ✅ done + tested (OPH-152) |
| App: replica v5, FileStore, upload machinery | ✅ done + tested (OPH-153) |
| App: task-detail Attachments section | ✅ done + tested (OPH-154) |
| App: project Files tab (manager + usage footer) | ✅ done + tested (OPH-155/157) |
| App: inline note images/videos + markdown parity | ✅ done + tested (OPH-156) |
| Manual QA matrix — devices, web CORS reality, 100 MB files | ⏳ rides the Epic 12/13 device tour (OPH-157) |

Everything below was written before implementation and then trued against it;
deviations are called out inline and in TASKS.md acceptance notes.

## 0. What the user asked for (scope)

1. **Cloudflare R2 in the backend** — binary storage for images, videos and *any*
   file type.
2. **Attachments on tasks** — image/video/file attachments listed on task detail.
3. **Inline images/videos in notes** — embedded in the rich-text editor.
4. **A "Files" tab on project detail** — a simple file manager: list, upload,
   download, rename, delete, with the project's task/note files aggregated.

Out of scope for v1 (parked, §11): multipart upload for >5 GB files, client-side
thumbnails/transcodes, camera capture, per-workspace quotas (usage *display*
ships in OPH-157; enforcement is v2), local binary cache for offline viewing.

## 1. Storage backend — R2 via the S3 protocol

**Decision: speak S3, document R2.** R2 is S3-API compatible, so one driver covers
R2 (the product target), MinIO (dev/CI) and any S3-compatible store a self-hoster
prefers (AWS S3, Backblaze B2, Garage…). No Cloudflare-proprietary API is used.

R2 facts the design leans on (verified against Cloudflare docs at design time):

- **Endpoint** `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, region **`auto`**,
  SigV4 signatures. Credentials come from an R2 API token (S3-style Access Key ID
  + Secret Access Key).
- **Path-style and virtual-hosted-style both work.** We default to
  **path-style** (`forcePathStyle: true`) because MinIO requires it — one client
  config for both.
- **Presigned URLs** are supported for PUT and GET; **maximum expiry 7 days**
  (604800 s). We use a configurable TTL, default 1 h.
- **Single PUT caps at ~5 GB** (multipart beyond that — parked, §11). Our own
  configurable cap (default 512 MB) is far below it.
- **Zero egress fees** — direct-to-client downloads cost nothing, which is why
  the API never proxies bytes (§2).
- **CORS is configured per bucket** and is REQUIRED for the web app (§8).

The API server holds the only credentials. Clients never see bucket keys — they
receive short-lived presigned URLs scoped to exactly one object and verb.

## 2. Transfer model — presigned, direct to storage

**Bytes never flow through the API.** Uploads PUT directly to storage with a
presigned URL; downloads GET directly with a presigned URL. The API stays a
metadata + authorization service.

Why not proxy through Fastify: a self-hosted API on a small VPS would pay double
bandwidth for every video, tie up the Node event loop streaming, and gain
nothing — R2 egress is free and presigned URLs carry the same authorization
decision (the API minted them). This is the industry-standard shape (Linear,
Notion, Slack all upload direct to storage).

### 2.1 Upload lifecycle (3 steps)

```txt
app                          api                              R2/S3
 │  POST /workspaces/:id/files │                                │
 │  {targetType,targetId,name, │                                │
 │   mime,sizeBytes}           │                                │
 │ ───────────────────────────▶│ validate member+target+size    │
 │                             │ INSERT files status=uploading  │
 │                             │ presign PUT (TTL 1h)           │
 │ ◀─────────────────────────── 201 {file, upload:{url,headers}}│
 │  PUT bytes (Content-Type)   │                                │
 │ ─────────────────────────────────────────────────────────────▶
 │  POST /files/:id/complete   │                                │
 │ ───────────────────────────▶│ HeadObject: exists? size ==    │
 │                             │ declared? ≤ cap?               │
 │                             │ → status=ready + sync 'create' │
 │ ◀─────────────────────────── 200 {file}                      │
```

- The **`uploading` row is invisible to sync** — no `recordSyncWrite` on init.
  Other devices only ever learn about files that actually exist (§4).
- **`complete` verifies with `HeadObject`**: object missing →
  `409 FILE_UPLOAD_INCOMPLETE` (row stays; the client may retry the PUT until
  the sweep reaps it). Size ≠ declared or > cap → best-effort `DeleteObject`,
  row hard-deleted, `409 FILE_UPLOAD_MISMATCH` (client restarts from init).
- **Size enforcement is at complete-time, deliberately.** Presigning a
  `Content-Length` header is possible but SDK-hostile (header hoisting varies);
  since nothing becomes visible before `complete` and the sweep deletes
  abandoned objects, a lying client can only waste its own upload bandwidth.
  Declared size is still pre-checked at init so honest clients fail fast.
- **Stale-upload sweep**: rows with `status='uploading'` older than **24 h** are
  hard-deleted and their objects best-effort `DeleteObject`ed, every
  `STORAGE_SWEEP_SEC` (default 1 h). No user-visible trace — they never synced.

### 2.2 Download

`GET /api/v1/files/:fileId` returns metadata plus, for `ready` files, a presigned
GET URL (TTL 1 h) with `response-content-disposition` (attachment; RFC 5987
encoded filename — Turkish filenames must round-trip) and
`response-content-type` pinned from the DB row. The app:

- renders **images/videos inline** straight from that URL (caching it in memory
  per file until expiry);
- "downloads" by launching the URL (`url_launcher`) — the browser/OS handles
  saving; on web the `Content-Disposition: attachment` triggers a download.

Presigned URLs are never stored, logged, or synced — they are minted on demand.

## 3. Data model

One table, **`files`** (migration `create_files`). Attachment = a file row whose
`target_*` names its owner. Polymorphic on purpose: one shape serves tasks,
notes and projects, and the project "Files" tab is a query, not a join table.

| column        | type                                  | notes                                   |
| ------------- | ------------------------------------- | --------------------------------------- |
| `id`          | char(26) PK                           | ULID (`src/lib/ids.js`)                 |
| `workspace_id`| char(26) FK→workspaces CASCADE        |                                         |
| `target_type` | enum('project','task','note')         |                                         |
| `target_id`   | char(26), indexed                     | no FK (polymorphic); validated at init  |
| `uploaded_by` | char(26) nullable                     | user id (no FK, like `created_by`)      |
| `name`        | varchar(255)                          | display filename; renameable            |
| `mime`        | varchar(255)                          | client-declared; default octet-stream   |
| `size_bytes`  | bigint unsigned                       | declared at init, verified at complete  |
| `storage_key` | varchar(300) unique                   | `ws/{workspaceId}/{fileId}` — **opaque**|
| `status`      | enum('uploading','ready')             | only `ready` rows sync                  |
| `revision`    | bigint                                | sync stamp (AGENTS.md §6)               |
| `created_at` / `updated_at` / `deleted_at` | datetime(3)      | soft delete like every entity           |

Indexes: `(workspace_id, target_type, target_id)` for attachment lists,
`(status, created_at)` for the sweep.

**The storage key contains no filename.** Rename is a pure metadata `PATCH`; the
object never moves. The filename reaches downloads via
`response-content-disposition` (§2.2).

**"Any file type" is literal** (user requirement): no MIME allowlist. `mime`
drives UI (image → thumbnail, video → player tile, else generic tile) and the
download's content type — it is never executed or rendered as HTML (§9).

## 4. Sync — `file` is a pull-only entity (ADR-0008 precedent)

File *metadata* syncs to every device so attachment lists render offline and the
project Files tab is a local replica query. File *writes* are REST-only — an
upload is inherently online (the bytes go to R2), so pretending it can queue in
the outbox would be a lie.

- **Pull:** `file` joins `SNAPSHOT_LOADERS` in `routes/sync.js`; `ready` rows
  snapshot as `{id, workspaceId, targetType, targetId, name, mime, sizeBytes,
  status, uploadedBy, revision, createdAt, updatedAt}` — **no URLs** (they
  expire; §2.2 mints them on demand). Soft-deleted rows tombstone as usual.
- **Push:** `file` is deliberately **absent from `ENTITIES`** → any push answers
  `SYNC_UNSUPPORTED_ENTITY`. Exactly the external-event model: *the write path
  not existing is the guarantee* (ADR-0008).
- App replica: drift schema **v5** adds `files`; the applier upserts/tombstones
  it; `FileStore` exposes watch queries. No outbox lane.

## 5. Lifecycle & cascade (no orphaned bytes)

Deleting things must not leak storage. All cleanup funnels through one helper
(`src/db/files.js`) used by REST and sync-push paths alike:

- **`DELETE /files/:id`** — `uploading`: hard-delete row + best-effort object
  delete (it never synced). `ready`: soft-delete + `recordSyncWrite('delete')`
  (tombstone) + enqueue object deletion.
- **Task deleted** (REST subtree walk *and* sync `customDelete`): every task in
  the subtree also soft-deletes its `ready` files (one revision each — replicas
  must drop them) and enqueues object deletes.
- **Note deleted:** same, for the note's files (including files behind inline
  embeds — the note owns them, §7).
- **Project deleted:** files targeted at the *project itself* are deleted.
  Tasks/notes survive project deletion today and keep their files — the cascade
  mirrors exactly what entity deletion already does, nothing more.
- **Archiving anything deletes nothing.**
- **Object deletion is a queued job** (`queue/runner.js` — BullMQ when Redis is
  up, inline otherwise): `jobKey = storage_key`, DeleteObject, 404 = success
  (idempotent). Enqueued only after the deleting transaction commits (same
  `executionPromise` pattern as `recordSyncWrite`).

Note-embed nuance: removing an image from a note's *body* does not delete the
file row (undo must stay safe). The file remains listed under the note / in the
project Files tab, where it can be deleted explicitly; deleting the note reaps
everything. Documented honestly in the UI spec (§7).

## 6. API surface (all routes `requireWorkspaceMember`; Ajv schemas per AGENTS.md)

| method & path | purpose |
| --- | --- |
| `GET  /api/v1/storage` | deployment status: `{configured, maxUploadBytes, presignTtlSec}` — the app's honest "is this feature on" probe |
| `POST /api/v1/workspaces/:workspaceId/files` | init upload (§2.1) → `201 {file, upload:{method:'PUT', url, headers, expiresAt}}` |
| `POST /api/v1/files/:fileId/complete` | verify + publish → `200 {file}` |
| `GET  /api/v1/files/:fileId` | metadata + `downloadUrl`/`downloadExpiresAt` (null unless `ready`) |
| `GET  /api/v1/workspaces/:workspaceId/files?targetType&targetId` | attachment list for one entity |
| `GET  /api/v1/workspaces/:workspaceId/files?projectId=` | **aggregate**: project files ∪ files of the project's tasks ∪ notes (each row carries `source: project\|task\|note`) |
| `PATCH /api/v1/files/:fileId` | rename `{name}` (`ready` only) → revision bump |
| `DELETE /api/v1/files/:fileId` | abort or delete (§5) → 204 |
| `GET  /api/v1/workspaces/:workspaceId/files/usage` | `{totalBytes, fileCount}` over `ready` rows (OPH-157) |

Error codes (stable, machine-readable): `STORAGE_NOT_CONFIGURED` (503),
`FILE_NOT_FOUND`, `FILE_INVALID_TARGET` (target missing/deleted/wrong
workspace), `FILE_TOO_LARGE`, `FILE_NAME_INVALID`, `FILE_UPLOAD_INCOMPLETE`,
`FILE_UPLOAD_MISMATCH`, `FILE_NOT_READY` (complete/rename on the wrong status).

Authorization: any workspace member may upload, rename, delete (files follow
task/note write semantics, not the owner/admin-only project delete). Every
mint of a download URL re-checks membership — URLs are the only bearer of
storage access and they expire.

## 7. App UX spec (DESIGN.md-conformant; every string i18n'd en+tr)

- **Task detail — "Attachments" section** (OPH-154): section header + add
  button (file picker). Rows: leading square thumbnail (images; presigned URL)
  or kind icon (video/file), filename (1 line, ellipsis), size + date subtitle.
  Uploading rows show a progress bar + cancel. Tap: image → full-screen viewer
  (InteractiveViewer), video/other → action sheet (Open/Download · Rename ·
  Delete with confirm). Empty state: none (section shows just the add button —
  attachments are optional, not a chore).
- **Project detail — "Files" tab** (OPH-155): the file manager. Aggregated
  replica query (project ∪ its tasks' ∪ its notes' files), newest first, source
  filter chips (All · Project · Tasks · Notes) — rows carry a source badge
  (task/note title) so "where is this from" is never a mystery. Upload FAB
  targets the *project*. Sort: date default; name/size toggles. Actions as
  above. Storage-not-configured → honest empty state pointing at
  `.env` (`STORAGE_S3_*`), not a spinner, not silence.
- **Notes — inline images & videos** (OPH-156): editor toolbar gains
  image/video insert → picker → upload (target = the note) → on complete an
  embed lands in the delta: standard Quill `image`/`video` embed whose source is
  **`alliswell://file/{fileId}`** (stable, offline-safe — never a presigned
  URL). Custom embed builders resolve id → cached presigned URL: images render
  inline (loading shimmer, tap = viewer), videos/others render a tile
  (filename + open action). Offline / URL fetch failed → placeholder tile with
  the filename, no crash, no broken-image glyph. A brand-new note must be
  saved (have an id) before its first upload — the editor already autosaves.
- **Uploads are explicit and visible**: per-file progress from dio's
  `onSendProgress`, cancelable; failure → inline error row with retry. No
  background/queued upload pretense (§4).
- **Downloads** launch the presigned URL (`url_launcher`, `externalApplication`)
  — browser/OS saves it; nothing is written to app storage in v1.

Markdown export (`GET /notes/:id/export`): image embeds map to
`![name](alliswell://file/{id})`, video/file embeds to `[name](alliswell://file/{id})`
— a stable app-scheme URI (ADR-0003 naming), not an expiring presigned URL. The
export documents where the bytes live; resolving them needs the API. Plain-text
extraction (`deltaToPlainText`, note search) continues to skip embeds.

## 8. CORS — the one piece of user-side R2 setup

Browsers (the Flutter *web* app) preflight the direct PUT and fetch GETs via
XHR (CanvasKit renders images through fetch), so **the bucket needs a CORS
rule**. Native platforms don't care. Documented in README + `.env.example`;
example rule (R2 dashboard → bucket → Settings → CORS policy):

```json
[
  {
    "AllowedOrigins": ["https://your-app-origin.example"],
    "AllowedMethods": ["GET", "PUT"],
    "AllowedHeaders": ["content-type"],
    "MaxAgeSeconds": 3600
  }
]
```

Dev MinIO answers permissive CORS out of the box — no setup. This is the
feature's biggest self-hoster footgun; the app's upload error state names it
("web'de yükleme CORS ister" hint in the docs link), and ATTACHMENTS.md is the
canonical guide.

## 9. Security

- **Credentials only on the server** (`STORAGE_S3_*` env; never committed —
  SECURITY.md). Clients get single-object, single-verb, expiring URLs.
- **Opaque keys** (`ws/{wsId}/{fileId}`): no filenames in URLs/keys — no path
  traversal, no PII leak in storage listings or logs.
- **Filenames** are display data: 1–255 chars, control chars rejected, path
  separators stripped at init/rename; served via RFC 5987 `filename*`.
- **No execution surface:** files are never served from the app origin (no
  stored-XSS-via-SVG on our domain), `response-content-type` is pinned from the
  DB, images render through Flutter `Image` (not WebViews/HTML).
- **Presigned URLs never logged**; download URL minting re-checks membership on
  every call; expiry ≤ `STORAGE_PRESIGN_TTL_SEC` (≤ R2's 7-day hard cap,
  enforced at config load).
- Payloads on the wire carry ids and metadata only; notification payloads are
  untouched (BLUEPRINT §8.3).

## 10. Config (env; loaded in `src/config.js`, validated at boot)

```bash
# unset endpoint/bucket/keys ⇒ feature off: endpoints answer STORAGE_NOT_CONFIGURED,
# the app hides/explains attachment UI. The API boots fine without any of it.
STORAGE_S3_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com   # or http://127.0.0.1:9000 (MinIO)
STORAGE_S3_REGION=auto
STORAGE_S3_BUCKET=alliswell
STORAGE_S3_ACCESS_KEY_ID=…
STORAGE_S3_SECRET_ACCESS_KEY=…
STORAGE_S3_FORCE_PATH_STYLE=true      # R2: works either way; MinIO: required
STORAGE_MAX_UPLOAD_MB=512             # complete-time enforced cap (§2.1)
STORAGE_PRESIGN_TTL_SEC=3600          # 60 … 604800 (R2 hard cap)
STORAGE_SWEEP_SEC=3600                # stale 'uploading' reaper cadence
```

Production guard (config.js, Google-integration precedent): if the endpoint is
set, bucket + both keys are required; TTLs validated in range. Partial config is
a boot error, not a runtime surprise.

## 11. Deliberate v1 cuts (parked)

- **Multipart upload** (>5 GB or resumable) — single presigned PUT only.
- **Thumbnails/transcodes** — originals only; image rows downscale client-side.
- **Quota enforcement** — usage endpoint + Files-tab footer only (OPH-157).
- **Local binary cache** for offline viewing — metadata offline, bytes online.
- **Camera capture** (image_picker) — file/gallery picker only (file_picker's
  PHPicker path needs no new iOS permission strings; camera does).
- **Inline video playback** (video_player) — v1 renders a tile + opens
  externally; per-platform player work is its own future task.
- **Public sharing links** — everything stays member-only.

## 12. Test strategy (per AGENTS.md §5)

- **API unit** (no infra): storage plugin injected as a fake
  (`buildApp({ storage })` like `db`/`redis`) with deterministic URLs — config
  validation, status endpoint, init/complete/mismatch/abort, sweeps, cascade
  revisions, pull snapshots, push refusal, rename, aggregate list, markdown
  embed export.
- **API integration** (MinIO in compose + CI service): the REAL flow — init →
  `fetch` PUT to the presigned URL → complete → download URL GETs the same
  bytes → delete → object 404s. Size-mismatch actually deletes the object.
- **App**: store/applier/schema-v5 tests; upload service against a fake
  transport (progress, cancel, failure→retry); widget tests for the three
  surfaces with `sync_overrides` fakes.
- **Manual matrix** (OPH-157, with the Epic 12/13 device tour): iPhone photo
  upload, Android video, desktop drag-less picker flow, web CORS happy path +
  the CORS-missing error state, 100 MB+ file, offline placeholder rendering.

## 13. Rollout

Epic 14 lands behind config: self-hosters who set nothing see an app without
attachment affordances (honest empty states where the tabs/sections live) and an
API that answers `STORAGE_NOT_CONFIGURED`. Setting four env vars turns the
feature on. Target release: **v0.3.0** (Phase 8).
