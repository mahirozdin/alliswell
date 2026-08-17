# The AllisWell REST API

Everything the app does, your own scripts can do. This page is for people
writing a cron job, a Home Assistant automation, a migration script or a small
integration against **their own instance**.

- **Base URL:** `https://api.your-instance.example` (whatever `API_PUBLIC_URL`
  is on your server; `http://localhost:3000` in development).
- **Auth:** a personal API key — see below. Everything under `/api/v1` speaks
  JSON, in and out.
- Want your AI assistant to do this instead of a script? That is the
  connector: [MCP.md](MCP.md).

## 1. Get a key

In the app: **Settings → Integrations → API access → Create key**. Give it a
name you will recognise and pick how long it should last (30 / 90 / 365 days,
or no expiry).

**The key is shown once.** Copy it then; the server only keeps a digest, so
nobody — including you — can read it back. Lost it? Revoke it and make another.

```bash
export ALLISWELL_URL="https://api.your-instance.example"
export ALLISWELL_KEY="awk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

curl -s "$ALLISWELL_URL/api/v1/me" \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

### What a key can and cannot do

A key acts as **you**, in **one workspace** — the one it was created in. There
are no scopes in v1 ([ADR-0032](adr/0032-api-keys.md)).

Three things it can never do, whatever it holds:

| Refused | Why |
| --- | --- |
| Delete your account (`DELETE /me`, `/me/deletion/cancel`) | A leaked key must not be able to erase the account it leaked from |
| Anything under `/ai/*` | Those hold your AI provider keys and spend your model budget |
| Create or revoke API keys | Otherwise one leaked key becomes permanent: the holder simply issues another |

Those answer `403 AUTH_APIKEY_FORBIDDEN`. Using a key against a **different**
workspace answers `403 AUTH_APIKEY_WORKSPACE`.

## 2. Find your workspace id

Almost every collection lives under a workspace. `GET /me` tells you which ones
you are in — a key will only work with its own:

```bash
curl -s "$ALLISWELL_URL/api/v1/me" -H "Authorization: Bearer $ALLISWELL_KEY" \
  | jq -r '.workspaces[] | "\(.id)  \(.name)"'
```

```json
{
  "user": { "id": "01J…", "email": "you@example.com", "timezone": "Europe/Istanbul" },
  "workspaces": [{ "id": "01WS…", "name": "My Space", "role": "owner" }]
}
```

## 3. Recipes

`WS` below is your workspace id. Every id in AllisWell is a 26-character ULID.

### Create a task

```bash
curl -s -X POST "$ALLISWELL_URL/api/v1/workspaces/$WS/tasks" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
        "title": "Pay the electricity bill",
        "dueAt": "2026-09-01T17:00:00+03:00",
        "priority": "high",
        "isUrgent": true
      }'
```

`isUrgent` with a `dueAt` (or a `remindAt`) is what produces a real alarm —
the same one the app would create. Times are ISO-8601 **with an offset**;
`timezone` on the task decides its wall clock.

### Complete, reopen, snooze

```bash
curl -s -X POST "$ALLISWELL_URL/api/v1/tasks/$TASK_ID/complete" \
  -H "Authorization: Bearer $ALLISWELL_KEY"

curl -s -X POST "$ALLISWELL_URL/api/v1/tasks/$TASK_ID/snooze" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"preset": "tomorrow_morning"}'
```

Completing an already-completed task is a quiet no-op — safe to retry.

### Create a note and attach it to a task

```bash
NOTE=$(curl -s -X POST "$ALLISWELL_URL/api/v1/workspaces/$WS/notes" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
        "title": "Meeting notes",
        "contentFormat": "markdown",
        "contentMarkdown": "# Decisions\n\n- ship it\n"
      }' | jq -r .id)

curl -s -X POST "$ALLISWELL_URL/api/v1/notes/$NOTE/links" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d "{\"entityType\": \"task\", \"entityId\": \"$TASK_ID\"}"
```

`contentFormat` decides which field is canonical
([ADR-0028](adr/0028-markdown-document-model-and-renderer.md)): send
`"markdown"` with `contentMarkdown` and the note is a markdown document
everywhere — in search, in export, in the editor.

### Export a note as markdown

```bash
curl -s "$ALLISWELL_URL/api/v1/notes/$NOTE/export?format=md" \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

### Search your tasks

```bash
curl -s -G "$ALLISWELL_URL/api/v1/workspaces/$WS/tasks" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  --data-urlencode 'q=fatura' --data-urlencode 'status=open' --data-urlencode 'limit=20'
```

### Take all your notes out

```bash
curl -s -G "$ALLISWELL_URL/api/v1/workspaces/$WS/export/notes" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  --data-urlencode 'limit=200' > notes-page-1.json
```

Each note comes out whole: title, `contentFormat` and **both** body fields,
plain text, project, tags, links, pin/archive flags and timestamps. Archived
notes are included (pass `includeArchived=false` if you really want them out).
Page with `cursor` until `nextCursor` is `null`:

```bash
CURSOR=$(jq -r '.nextCursor' notes-page-1.json)
[ "$CURSOR" != "null" ] && curl -s -G "$ALLISWELL_URL/api/v1/workspaces/$WS/export/notes" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  --data-urlencode 'limit=200' --data-urlencode "cursor=$CURSOR" > notes-page-2.json
```

There is no zip archive in v1: this is JSON, and one note at a time already
exports as markdown at `/notes/:id/export`.

### Bring notes or tasks in

Up to **500 items per request**. Imported notes are markdown documents, and
imported tasks go through the same code path the app uses — an urgent task
with a due time gets a real alarm.

```bash
curl -s -X POST "$ALLISWELL_URL/api/v1/workspaces/$WS/import/notes" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"notes": [
        {"title": "From my old app", "contentMarkdown": "# Heading\n\nbody"},
        {"title": "Pinned one", "contentMarkdown": "…", "isPinned": true}
      ]}'
```

```json
{ "created": ["01J…", "01J…"], "errors": [] }
```

**Partial success is normal and reported.** If item #37 names a project that
does not exist, the other 499 are still imported and the response says which
one failed and why — fix that line and retry it alone:

```json
{ "created": ["01J…"],
  "errors": [{ "index": 37, "code": "NOTE_INVALID_PROJECT",
               "message": "projectId does not reference a project in this workspace" }] }
```

Tasks work the same way:

```bash
curl -s -X POST "$ALLISWELL_URL/api/v1/workspaces/$WS/import/tasks" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"tasks": [
        {"title": "Renew the domain", "dueAt": "2026-11-01T09:00:00+03:00", "isUrgent": true},
        {"title": "Water the plants", "priority": "low"}
      ]}'
```

Your devices converge on their own afterwards — imported rows are ordinary
rows, so the usual sync brings them down with no import-aware client code.

## 4. Endpoint reference

Everything below is under `/api/v1` and needs the `Authorization` header. Lists
are newest-first and cursor-paginated (`limit`, `cursor`, `nextCursor`).

### Account

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/me` | Account + the workspaces you belong to |
| PATCH | `/me` | `{ locale }` |

### Tasks

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/workspaces/:ws/tasks` | Filters: `status[]`, `projectId`, `parentTaskId`, `tagId`, `dueFrom`, `dueTo`, `urgent`, `q` |
| POST | `/workspaces/:ws/tasks` | `title` required; `tagIds[]` attaches tags |
| GET | `/tasks/:id` | Detail with `tagIds` and `checklist` |
| PATCH | `/tasks/:id` | Any writable field; `seriesScope` for a recurring occurrence |
| DELETE | `/tasks/:id` | Soft delete, cascades to subtasks and attachments |
| POST | `/tasks/:id/complete` · `/reopen` | Idempotent transitions |
| POST | `/tasks/:id/snooze` | `{ preset }` (`5_min`/`30_min`/`1_hour`/`tomorrow_morning`) or `{ snoozeUntil }` |
| PUT | `/tasks/:id/tags` | Replace-set: `{ tagIds: [...] }` |
| POST · PATCH · DELETE | `/tasks/:id/checklist[/:itemId]` | Checklist items |
| POST | `/tasks/:id/notes` | Turn a task into a linked note |

### Notes

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/workspaces/:ws/notes` | `pinned`, `archived`, `includeArchived`, `projectId`, `taskId`, `q` |
| POST | `/workspaces/:ws/notes` | `title` required; `contentFormat` + body |
| GET · PATCH · DELETE | `/notes/:id` | |
| GET | `/notes/:id/export` | `?format=md` (the default) |
| POST · DELETE | `/notes/:id/links[/:linkId]` | Attach to a task or project |
| PUT | `/notes/:id/tags` | Replace-set |
| GET | `/projects/:id/notes` | Attached + linked notes |

### Projects, tags, recurrence

| Method | Path | Notes |
| --- | --- | --- |
| GET · POST | `/workspaces/:ws/projects` | |
| GET · PATCH · DELETE | `/projects/:id` | |
| POST | `/projects/:id/archive` · `/unarchive` | Cascades over the project's tasks and notes |
| GET · POST | `/workspaces/:ws/tags` | |
| GET · PATCH · DELETE | `/tags/:id` | |
| GET · POST | `/workspaces/:ws/task-series` | Recurrence rules ([ADR-0020](adr/0020-recurring-tasks-and-materialization.md)) |
| GET · PATCH · DELETE | `/task-series/:id` | |

### Files and folders

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/workspaces/:ws/files` | Starts an upload, returns a presigned PUT |
| POST | `/files/:id/complete` | Marks it ready — bytes never pass through the API |
| GET | `/files/:id` | Metadata + a short-lived download URL |
| GET | `/workspaces/:ws/files` · `/files/usage` | Listing and total bytes |
| PATCH · DELETE | `/files/:id` | Rename, soft delete |
| GET · POST | `/workspaces/:ws/folders` | |
| PATCH · DELETE | `/folders/:id` | |

### Note history

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/notes/:id/versions` | Metadata only: origin, size, when, which device |
| GET | `/notes/:id/versions/:versionId` | One version's full body |
| GET | `/notes/:id/versions/:versionId/diff` | Word-level segments against the note as it is now |
| POST | `/notes/:id/versions/:versionId/restore` | `{ mode: "replace" \| "copy" }` |

Every content-changing write leaves a version, wherever it came from — the app,
a script with a key, an assistant, an import. A typing session collapses into
one row and an identical body writes none ([ADR-0031](adr/0031-note-versioning.md)).
`restore` with `replace` applies the old body as a **new** write, so the state
you are leaving is captured too and the restore is itself undoable.

### Bulk import / export

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/workspaces/:ws/export/notes` | `limit` (≤200), `cursor`, `includeArchived` (default true) |
| POST | `/workspaces/:ws/import/notes` | ≤500 items; `{ created, errors }` — partial success is reported |
| POST | `/workspaces/:ws/import/tasks` | ≤500 items; goes through the normal task create (alarms included) |

### Reminders and shortcuts

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/reminders/:id/acknowledge` | Answer an urgent alarm |
| GET · POST | `/workspaces/:ws/quick-links` | |
| PATCH · DELETE | `/quick-links/:id` | |
| PUT | `/workspaces/:ws/quick-links/order` | |

### Keys (JWT only — a key cannot manage keys)

| Method | Path | Notes |
| --- | --- | --- |
| GET · POST | `/workspaces/:ws/api-keys` | The secret is in the 201 body, once |
| POST | `/api-keys/:id/revoke` | Immediate; idempotent |

### Sync

`GET /sync/pull` and `POST /sync/push` are the app's replication protocol
(BLUEPRINT §6). They are available to a key, but they are not the integration
surface: use the REST endpoints above unless you are building another client.

## 5. Errors

Every failure is JSON with a stable machine-readable `code` — match on that,
never on the message:

```json
{ "statusCode": 403, "code": "AUTH_APIKEY_WORKSPACE",
  "error": "Forbidden", "message": "This API key is bound to a different workspace" }
```

| Status | Code | Meaning |
| --- | --- | --- |
| 401 | `AUTH_INVALID_API_KEY` | No such key (or the account is gone) |
| 401 | `AUTH_API_KEY_REVOKED` | You revoked it |
| 401 | `AUTH_API_KEY_EXPIRED` | Its lifetime ran out |
| 403 | `AUTH_APIKEY_WORKSPACE` | Right key, wrong workspace |
| 403 | `AUTH_APIKEY_FORBIDDEN` | One of the three closed doors above |
| 403 | `AUTH_WORKSPACE_FORBIDDEN` | You are not a member there |
| 404 | `TASK_NOT_FOUND`, `NOTE_NOT_FOUND`, … | Also what you get for someone else's row |
| 409 | `TASK_ARCHIVED`, `TASK_INVALID_TRANSITION` | The state refuses this write |
| 429 | — | Rate limited; see below |

## 6. Rate limits

Key-authenticated requests are counted **per key** (default 300/minute,
`API_KEY_RATE_LIMIT_MAX`), not per IP — your script cannot exhaust your
browser's budget, and one busy key cannot throttle the instance's other
clients. A limited request answers `429` with a `retry-after` header.

## 7. Key lifecycle

- **Create** in the app; the secret is shown once and stored only as a digest.
- **Watch** — the list shows each key's last use (updated at most once a
  minute), which is how you tell a live key from a forgotten one.
- **Revoke** in the app. The next request with that key is a 401, immediately.
  Revoking is permanent; create a new key rather than un-revoking.
- **Rotate** by creating the new key, switching your script over, then revoking
  the old one. There is no automatic rotation in v1.
- **Leaked?** Revoke it. Nothing else needs rotating — a key authenticates
  nothing but itself. Keep keys in environment variables, never in a committed
  file; the `awk_` prefix exists partly so secret scanners can spot one.

Self-hosting notes, threat model and reporting: [SECURITY.md](../SECURITY.md).
