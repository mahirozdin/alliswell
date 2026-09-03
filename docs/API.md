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

In the app: **Settings → API access and management → API access → Create key**.
Give it a name you will recognise and pick how long it should last
(30 / 90 / 365 days, or no expiry).

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

Four things it can never do, whatever it holds — **25 endpoints in total**,
each marked "Session JWT only" in the reference below:

| Refused | Why |
| --- | --- |
| Delete your account (`DELETE /me`, `/me/deletion/cancel`) | A leaked key must not be able to erase the account it leaked from |
| Anything under `/ai/*` | Those hold your AI provider keys and spend your model budget |
| Create or revoke API keys | Otherwise one leaked key becomes permanent: the holder simply issues another |
| Change your own credentials — password, two-factor, sessions (`/auth/password`, `/auth/mfa/*`, `/auth/sessions*`) | A key is for reaching your data, never for taking the account over. A holder who could rotate your password or close your sessions would own the account, not borrow it |

Those answer `403 AUTH_APIKEY_FORBIDDEN`. Using a key against a **different**
workspace answers `403 AUTH_APIKEY_WORKSPACE`.

The fourth row arrived with two-factor auth and session management (OPH-283,
OPH-284) and went undocumented until OPH-294 — which is why the list of closed
doors is now derived from the routes themselves rather than kept by hand.

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
        "contentMarkdown": "- ship it\n"
      }' | jq -r .id)

curl -s -X POST "$ALLISWELL_URL/api/v1/notes/$NOTE/links" \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d "{\"entityType\": \"task\", \"entityId\": \"$TASK_ID\"}"
```

A note IS markdown ([ADR-0033](adr/0033-markdown-is-the-only-note-format.md)):
`contentMarkdown` is the whole body, and it is what search, export and the
editor all read.

The title lives in `title` and the stored body never repeats it — the `.md`
export adds the `# heading` back, because a file that stands on its own needs
one. `contentFormat` and `contentDelta` are **deprecated**: a Quill Delta is
still accepted (the mobile app sends one until everyone has updated) and is
converted on the way in, but it is never stored and responses always return
`"contentDelta": null`, `"contentFormat": "markdown"`.

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

Each note comes out whole: title, `contentMarkdown`, plain text, project,
tags, links, pin/archive flags and timestamps. (`contentDelta` is `null` and
`contentFormat` is `"markdown"` on every row — the export carries the
document, not a second copy nothing maintains.) Archived
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

### Editing a note two places at once

`PATCH /notes/:id` accepts an optional **`baseRevision`** — the note revision
your copy started from. Send it and the server does a three-way merge instead
of overwriting: if the two sets of changes do not touch, you get 200 with both
merged in; if they genuinely overlap you get `409 NOTE_CONTENT_CONFLICT`, and
**your body is kept** as a version you can go back to. Omit it and the
endpoint behaves exactly as it always has.

> The refused body is stored as a note version with origin `conflict`, so
> nothing you wrote is lost — but the 409 **body does not tell you its id**.
> Fastify serializes errors as `{statusCode, code, error, message}` and drops
> anything else, so find it with `GET /notes/:id/versions` (it is the newest
> row with `"origin": "conflict"`). `POST /sync/push` does return
> `conflictVersionId` in its per-mutation results — that is the replication
> protocol, not this one. This page claimed otherwise until OPH-294.

Every note is markdown, so every conflict is mergeable. Until 2026-08-18 a
note written in the app's rich editor took the conflict path instead — its
body was a JSON op array, and line-merging one does not produce a document.
[ADR-0033](adr/0033-markdown-is-the-only-note-format.md) removed that case
along with the second format, and a Delta arriving from an older client is
converted before the merge rather than refused.

### What every write leaves behind

Every content-changing write leaves a note version, wherever it came from —
the app, a script with a key, an assistant, an import. A typing session
collapses into one row and an identical body writes none
([ADR-0031](adr/0031-note-versioning.md)). `restore` with `mode: "replace"`
applies the old body as a **new** write, so the state you are leaving is
captured too and the restore is itself undoable.

Writes made with an API key are recorded with origin `api`, so a note's
history distinguishes what you typed from what your cron job did.

### Sync is not the integration surface

`GET /sync/pull` and `POST /sync/push` are the app's replication protocol
(BLUEPRINT §6). They are open to a key and they are documented below for
completeness, but they are not what you want unless you are building another
client: use the ordinary REST endpoints, which is what the recipes above do.

## 4. Endpoint reference

<!-- BEGIN GENERATED REFERENCE -->

_113 operations across 81 paths, generated from
[`openapi.json`](openapi.json) — which is itself generated from the server's own
route schemas. Do not edit this section by hand; run `npm run api:docs`._

**Contents**

- **AI** — [`POST /api/v1/ai/actions/{actionId}/decision`](#post-api-v1-ai-actions-actionid-decision) · [`PATCH /api/v1/ai/connections/{connectionId}`](#patch-api-v1-ai-connections-connectionid) · [`DELETE /api/v1/ai/connections/{connectionId}`](#delete-api-v1-ai-connections-connectionid) · [`POST /api/v1/ai/connections/{connectionId}/test`](#post-api-v1-ai-connections-connectionid-test) · [`POST /api/v1/workspaces/{workspaceId}/ai/chat`](#post-api-v1-workspaces-workspaceid-ai-chat) · [`POST /api/v1/workspaces/{workspaceId}/ai/chat/{requestId}/cancel`](#post-api-v1-workspaces-workspaceid-ai-chat-requestid-cancel) · [`GET /api/v1/workspaces/{workspaceId}/ai/connections`](#get-api-v1-workspaces-workspaceid-ai-connections) · [`POST /api/v1/workspaces/{workspaceId}/ai/connections`](#post-api-v1-workspaces-workspaceid-ai-connections) · [`POST /api/v1/workspaces/{workspaceId}/ai/extract`](#post-api-v1-workspaces-workspaceid-ai-extract) · [`GET /api/v1/workspaces/{workspaceId}/ai/models`](#get-api-v1-workspaces-workspaceid-ai-models) · [`GET /api/v1/workspaces/{workspaceId}/ai/status`](#get-api-v1-workspaces-workspaceid-ai-status)
- **API keys** — [`POST /api/v1/api-keys/{keyId}/revoke`](#post-api-v1-api-keys-keyid-revoke) · [`GET /api/v1/workspaces/{workspaceId}/api-keys`](#get-api-v1-workspaces-workspaceid-api-keys) · [`POST /api/v1/workspaces/{workspaceId}/api-keys`](#post-api-v1-workspaces-workspaceid-api-keys)
- **Account** — [`GET /api/v1/me`](#get-api-v1-me) · [`PATCH /api/v1/me`](#patch-api-v1-me) · [`DELETE /api/v1/me`](#delete-api-v1-me) · [`POST /api/v1/me/deletion/cancel`](#post-api-v1-me-deletion-cancel)
- **Authentication** — [`POST /api/v1/auth/login`](#post-api-v1-auth-login) · [`POST /api/v1/auth/logout`](#post-api-v1-auth-logout) · [`GET /api/v1/auth/mfa/totp`](#get-api-v1-auth-mfa-totp) · [`POST /api/v1/auth/mfa/totp`](#post-api-v1-auth-mfa-totp) · [`DELETE /api/v1/auth/mfa/totp`](#delete-api-v1-auth-mfa-totp) · [`POST /api/v1/auth/mfa/totp/confirm`](#post-api-v1-auth-mfa-totp-confirm) · [`POST /api/v1/auth/mfa/totp/recovery-codes`](#post-api-v1-auth-mfa-totp-recovery-codes) · [`POST /api/v1/auth/oauth`](#post-api-v1-auth-oauth) · [`POST /api/v1/auth/password`](#post-api-v1-auth-password) · [`POST /api/v1/auth/refresh`](#post-api-v1-auth-refresh) · [`POST /api/v1/auth/register`](#post-api-v1-auth-register) · [`GET /api/v1/auth/sessions`](#get-api-v1-auth-sessions) · [`DELETE /api/v1/auth/sessions/{id}`](#delete-api-v1-auth-sessions-id) · [`POST /api/v1/auth/sessions/revoke-others`](#post-api-v1-auth-sessions-revoke-others)
- **Capabilities** — [`GET /api/v1/ee/status`](#get-api-v1-ee-status)
- **Devices** — [`GET /api/v1/notification-devices`](#get-api-v1-notification-devices) · [`PUT /api/v1/notification-devices/{deviceId}`](#put-api-v1-notification-devices-deviceid) · [`DELETE /api/v1/notification-devices/{deviceId}`](#delete-api-v1-notification-devices-deviceid)
- **Files** — [`GET /api/v1/files/{fileId}`](#get-api-v1-files-fileid) · [`PATCH /api/v1/files/{fileId}`](#patch-api-v1-files-fileid) · [`DELETE /api/v1/files/{fileId}`](#delete-api-v1-files-fileid) · [`POST /api/v1/files/{fileId}/complete`](#post-api-v1-files-fileid-complete) · [`PATCH /api/v1/folders/{folderId}`](#patch-api-v1-folders-folderid) · [`DELETE /api/v1/folders/{folderId}`](#delete-api-v1-folders-folderid) · [`GET /api/v1/storage`](#get-api-v1-storage) · [`GET /api/v1/workspaces/{workspaceId}/files`](#get-api-v1-workspaces-workspaceid-files) · [`POST /api/v1/workspaces/{workspaceId}/files`](#post-api-v1-workspaces-workspaceid-files) · [`GET /api/v1/workspaces/{workspaceId}/files/usage`](#get-api-v1-workspaces-workspaceid-files-usage) · [`GET /api/v1/workspaces/{workspaceId}/folders`](#get-api-v1-workspaces-workspaceid-folders) · [`POST /api/v1/workspaces/{workspaceId}/folders`](#post-api-v1-workspaces-workspaceid-folders)
- **Google Calendar** — [`PATCH /api/v1/integrations/google/accounts/{accountId}`](#patch-api-v1-integrations-google-accounts-accountid) · [`DELETE /api/v1/integrations/google/accounts/{accountId}`](#delete-api-v1-integrations-google-accounts-accountid) · [`GET /api/v1/integrations/google/accounts/{accountId}/calendars`](#get-api-v1-integrations-google-accounts-accountid-calendars) · [`GET /api/v1/integrations/google/callback`](#get-api-v1-integrations-google-callback) · [`POST /api/v1/integrations/google/webhook`](#post-api-v1-integrations-google-webhook) · [`GET /api/v1/workspaces/{workspaceId}/integrations/google`](#get-api-v1-workspaces-workspaceid-integrations-google) · [`POST /api/v1/workspaces/{workspaceId}/integrations/google/connect`](#post-api-v1-workspaces-workspaceid-integrations-google-connect)
- **Health** — [`GET /health/live`](#get-health-live) · [`GET /health/ready`](#get-health-ready)
- **Notes** — [`GET /api/v1/notes/{noteId}`](#get-api-v1-notes-noteid) · [`PATCH /api/v1/notes/{noteId}`](#patch-api-v1-notes-noteid) · [`DELETE /api/v1/notes/{noteId}`](#delete-api-v1-notes-noteid) · [`GET /api/v1/notes/{noteId}/export`](#get-api-v1-notes-noteid-export) · [`POST /api/v1/notes/{noteId}/links`](#post-api-v1-notes-noteid-links) · [`DELETE /api/v1/notes/{noteId}/links/{linkId}`](#delete-api-v1-notes-noteid-links-linkid) · [`PUT /api/v1/notes/{noteId}/tags`](#put-api-v1-notes-noteid-tags) · [`GET /api/v1/notes/{noteId}/versions`](#get-api-v1-notes-noteid-versions) · [`GET /api/v1/notes/{noteId}/versions/{versionId}`](#get-api-v1-notes-noteid-versions-versionid) · [`GET /api/v1/notes/{noteId}/versions/{versionId}/diff`](#get-api-v1-notes-noteid-versions-versionid-diff) · [`POST /api/v1/notes/{noteId}/versions/{versionId}/restore`](#post-api-v1-notes-noteid-versions-versionid-restore) · [`GET /api/v1/projects/{projectId}/notes`](#get-api-v1-projects-projectid-notes) · [`GET /api/v1/workspaces/{workspaceId}/export/notes`](#get-api-v1-workspaces-workspaceid-export-notes) · [`POST /api/v1/workspaces/{workspaceId}/import/notes`](#post-api-v1-workspaces-workspaceid-import-notes) · [`GET /api/v1/workspaces/{workspaceId}/notes`](#get-api-v1-workspaces-workspaceid-notes) · [`POST /api/v1/workspaces/{workspaceId}/notes`](#post-api-v1-workspaces-workspaceid-notes)
- **Projects** — [`GET /api/v1/projects/{projectId}`](#get-api-v1-projects-projectid) · [`PATCH /api/v1/projects/{projectId}`](#patch-api-v1-projects-projectid) · [`DELETE /api/v1/projects/{projectId}`](#delete-api-v1-projects-projectid) · [`POST /api/v1/projects/{projectId}/archive`](#post-api-v1-projects-projectid-archive) · [`POST /api/v1/projects/{projectId}/unarchive`](#post-api-v1-projects-projectid-unarchive) · [`GET /api/v1/workspaces/{workspaceId}/projects`](#get-api-v1-workspaces-workspaceid-projects) · [`POST /api/v1/workspaces/{workspaceId}/projects`](#post-api-v1-workspaces-workspaceid-projects)
- **Quick links** — [`PATCH /api/v1/quick-links/{quickLinkId}`](#patch-api-v1-quick-links-quicklinkid) · [`DELETE /api/v1/quick-links/{quickLinkId}`](#delete-api-v1-quick-links-quicklinkid) · [`GET /api/v1/workspaces/{workspaceId}/quick-links`](#get-api-v1-workspaces-workspaceid-quick-links) · [`POST /api/v1/workspaces/{workspaceId}/quick-links`](#post-api-v1-workspaces-workspaceid-quick-links) · [`PUT /api/v1/workspaces/{workspaceId}/quick-links/order`](#put-api-v1-workspaces-workspaceid-quick-links-order)
- **Recurrence** — [`GET /api/v1/task-series/{seriesId}`](#get-api-v1-task-series-seriesid) · [`PATCH /api/v1/task-series/{seriesId}`](#patch-api-v1-task-series-seriesid) · [`DELETE /api/v1/task-series/{seriesId}`](#delete-api-v1-task-series-seriesid) · [`GET /api/v1/workspaces/{workspaceId}/task-series`](#get-api-v1-workspaces-workspaceid-task-series) · [`POST /api/v1/workspaces/{workspaceId}/task-series`](#post-api-v1-workspaces-workspaceid-task-series)
- **Reminders** — [`POST /api/v1/reminders/{reminderId}/acknowledge`](#post-api-v1-reminders-reminderid-acknowledge)
- **Service** — [`GET /`](#get)
- **Sync** — [`GET /api/v1/sync/pull`](#get-api-v1-sync-pull) · [`POST /api/v1/sync/push`](#post-api-v1-sync-push)
- **Tags** — [`GET /api/v1/tags/{tagId}`](#get-api-v1-tags-tagid) · [`PATCH /api/v1/tags/{tagId}`](#patch-api-v1-tags-tagid) · [`DELETE /api/v1/tags/{tagId}`](#delete-api-v1-tags-tagid) · [`GET /api/v1/workspaces/{workspaceId}/tags`](#get-api-v1-workspaces-workspaceid-tags) · [`POST /api/v1/workspaces/{workspaceId}/tags`](#post-api-v1-workspaces-workspaceid-tags)
- **Tasks** — [`GET /api/v1/tasks/{taskId}`](#get-api-v1-tasks-taskid) · [`PATCH /api/v1/tasks/{taskId}`](#patch-api-v1-tasks-taskid) · [`DELETE /api/v1/tasks/{taskId}`](#delete-api-v1-tasks-taskid) · [`POST /api/v1/tasks/{taskId}/checklist`](#post-api-v1-tasks-taskid-checklist) · [`PATCH /api/v1/tasks/{taskId}/checklist/{itemId}`](#patch-api-v1-tasks-taskid-checklist-itemid) · [`DELETE /api/v1/tasks/{taskId}/checklist/{itemId}`](#delete-api-v1-tasks-taskid-checklist-itemid) · [`POST /api/v1/tasks/{taskId}/complete`](#post-api-v1-tasks-taskid-complete) · [`POST /api/v1/tasks/{taskId}/notes`](#post-api-v1-tasks-taskid-notes) · [`POST /api/v1/tasks/{taskId}/reopen`](#post-api-v1-tasks-taskid-reopen) · [`POST /api/v1/tasks/{taskId}/snooze`](#post-api-v1-tasks-taskid-snooze) · [`PUT /api/v1/tasks/{taskId}/tags`](#put-api-v1-tasks-taskid-tags) · [`POST /api/v1/workspaces/{workspaceId}/import/tasks`](#post-api-v1-workspaces-workspaceid-import-tasks) · [`GET /api/v1/workspaces/{workspaceId}/tasks`](#get-api-v1-workspaces-workspaceid-tasks) · [`POST /api/v1/workspaces/{workspaceId}/tasks`](#post-api-v1-workspaces-workspaceid-tasks)

### AI

#### `POST /api/v1/ai/actions/{actionId}/decision`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `actionId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `accepted` | boolean | **yes** | — |
| `entityRefs` | array of object | no | up to 20 items |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/ai/actions/:actionId/decision' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"accepted":false}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "source": "string",
  "requestId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "proposal": {},
  "accepted": false,
  "entityRefs": [
    {
      "type": "string",
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
    }
  ],
  "createdAt": "2026-09-04T14:30:00.000Z",
  "decidedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `PATCH /api/v1/ai/connections/{connectionId}`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `connectionId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `apiKey` | string | no | length 8–512 |
| `baseUrl` | string or null | no | length 0–2048, pattern `^https?://` |
| `defaultChatModel` | string or null | no | length 1–128 |
| `defaultFastModel` | string or null | no | length 1–128 |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/ai/connections/:connectionId' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"apiKey":"string","baseUrl":"string","defaultChatModel":"string","defaultFastModel":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "provider": "string",
  "authMode": "string",
  "keyLast4": "string",
  "baseUrl": "string",
  "defaultChatModel": "string",
  "defaultFastModel": "string",
  "status": "string",
  "lastUsedAt": "2026-09-04T14:30:00.000Z",
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/ai/connections/{connectionId}`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `connectionId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/ai/connections/:connectionId' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `POST /api/v1/ai/connections/{connectionId}/test`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `connectionId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/ai/connections/:connectionId/test' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "ok": false,
  "latencyMs": 1,
  "code": "string",
  "message": "string"
}
```


#### `POST /api/v1/workspaces/{workspaceId}/ai/chat`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `requestId` | ULID | **yes** | 26-character identifier |
| `connectionId` | ULID | no | 26-character identifier |
| `model` | string | no | length 1–128 |
| `messages` | array of object | **yes** | up to 40 items |
| `context` | object | no | — |
| `transport` | `sse` · `socket` | no | — |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/ai/chat' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"requestId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","messages":[{"role":"user","content":"string"}]}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `429` | Rate limited. See `retry-after`. |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "requestId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "transport": "string"
}
```


#### `POST /api/v1/workspaces/{workspaceId}/ai/chat/{requestId}/cancel`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |
| `requestId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/ai/chat/:requestId/cancel' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |


#### `GET /api/v1/workspaces/{workspaceId}/ai/connections`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/ai/connections' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "provider": "string",
      "authMode": "string",
      "keyLast4": "string",
      "baseUrl": "string",
      "defaultChatModel": "string",
      "defaultFastModel": "string",
      "status": "string",
      "lastUsedAt": "2026-09-04T14:30:00.000Z",
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/ai/connections`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `provider` | `anthropic` · `openai` · `gemini` · `openrouter` · `ollama` | **yes** | — |
| `authMode` | `api_key` · `instance_env` | no | — |
| `apiKey` | string | no | length 8–512 |
| `baseUrl` | string | no | length 0–2048, pattern `^https?://` |
| `defaultChatModel` | string | no | length 1–128 |
| `defaultFastModel` | string | no | length 1–128 |
| `consentAcknowledged` | `true` | **yes** | — |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/ai/connections' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"provider":"anthropic","consentAcknowledged":true}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |
| `422` | Well-formed, but refused by a business rule. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "provider": "string",
  "authMode": "string",
  "keyLast4": "string",
  "baseUrl": "string",
  "defaultChatModel": "string",
  "defaultFastModel": "string",
  "status": "string",
  "lastUsedAt": "2026-09-04T14:30:00.000Z",
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `POST /api/v1/workspaces/{workspaceId}/ai/extract`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `text` | string | **yes** | length 1–8000 |
| `source` | `bubble` · `share` · `quick_add` · `voice` | **yes** | — |
| `connectionId` | ULID | no | 26-character identifier |
| `locale` | string | no | length 0–16 |
| `timezone` | string | no | length 0–64 |
| `defaultTaskTime` | string | no | pattern `^([01][0-9]|2[0-3]):[0-5][0-9]$` |
| `projectNames` | array of string | no | up to 100 items |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/ai/extract' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"text":"string","source":"bubble"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `422` | Well-formed, but refused by a business rule. |
| `429` | Rate limited. See `retry-after`. |
| `502` | An upstream service failed. |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "requestId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "actionId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "repaired": false,
  "proposal": {}
}
```


#### `GET /api/v1/workspaces/{workspaceId}/ai/models`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `connectionId` | ULID | no | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/ai/models' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `502` | An upstream service failed. |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "provider": "string",
  "connectionId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "source": "catalog",
  "models": {
    "chat": [
      {
        "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
        "label": "string"
      }
    ],
    "fast": [
      {
        "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
        "label": "string"
      }
    ]
  },
  "defaults": {
    "chat": "2026-09-04T14:30:00.000Z",
    "fast": "string"
  }
}
```


#### `GET /api/v1/workspaces/{workspaceId}/ai/status`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/ai/status' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "configured": false,
  "providers": [
    "string"
  ],
  "instanceProviders": [
    "string"
  ]
}
```


### API keys

#### `POST /api/v1/api-keys/{keyId}/revoke`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `keyId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/api-keys/:keyId/revoke' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "keyPrefix": "string",
  "createdAt": "2026-09-04T14:30:00.000Z",
  "expiresAt": "2026-09-04T14:30:00.000Z",
  "lastUsedAt": "2026-09-04T14:30:00.000Z",
  "revokedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `GET /api/v1/workspaces/{workspaceId}/api-keys`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/api-keys' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "name": "Pay the electricity bill",
      "keyPrefix": "string",
      "createdAt": "2026-09-04T14:30:00.000Z",
      "expiresAt": "2026-09-04T14:30:00.000Z",
      "lastUsedAt": "2026-09-04T14:30:00.000Z",
      "revokedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/api-keys`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | **yes** | length 1–100 |
| `expiresInDays` | `30` · `90` · `365` | no | — |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/api-keys' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "keyPrefix": "string",
  "createdAt": "2026-09-04T14:30:00.000Z",
  "expiresAt": "2026-09-04T14:30:00.000Z",
  "lastUsedAt": "2026-09-04T14:30:00.000Z",
  "revokedAt": "2026-09-04T14:30:00.000Z",
  "key": "string"
}
```


### Account

#### `GET /api/v1/me`

**Auth:** Personal API key **or** session JWT.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/me' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "user": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "email": "you@example.com",
    "displayName": "string",
    "avatarUrl": "string",
    "timezone": "Europe/Istanbul",
    "locale": "tr",
    "createdAt": "2026-09-04T14:30:00.000Z",
    "deletionScheduledAt": "2026-09-04T14:30:00.000Z"
  },
  "workspaces": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "name": "Pay the electricity bill",
      "slug": "pay-the-electricity-bill",
      "colorRgb": "string",
      "icon": "string",
      "role": "owner"
    }
  ]
}
```


#### `PATCH /api/v1/me`

**Auth:** Personal API key **or** session JWT.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `locale` | string | **yes** | length 0–16, pattern `^[a-z]{2}(-[A-Za-z]{2,4})?$` |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/me' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"locale":"tr"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "user": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "email": "you@example.com",
    "displayName": "string",
    "avatarUrl": "string",
    "timezone": "Europe/Istanbul",
    "locale": "tr",
    "createdAt": "2026-09-04T14:30:00.000Z",
    "deletionScheduledAt": "2026-09-04T14:30:00.000Z"
  },
  "workspaces": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "name": "Pay the electricity bill",
      "slug": "pay-the-electricity-bill",
      "colorRgb": "string",
      "icon": "string",
      "role": "owner"
    }
  ]
}
```


#### `DELETE /api/v1/me`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/me' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `401` | No credential, or one that is expired, revoked or unknown. |

**Example response** (`200`)

```json
{
  "deletionScheduledAt": "2026-09-04T14:30:00.000Z",
  "graceDays": 1
}
```


#### `POST /api/v1/me/deletion/cancel`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/me/deletion/cancel' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `401` | No credential, or one that is expired, revoked or unknown. |

**Example response** (`200`)

```json
{
  "deletionScheduledAt": "2026-09-04T14:30:00.000Z",
  "graceDays": 1
}
```


### Authentication

#### `POST /api/v1/auth/login`

**Auth:** None — this endpoint is public.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `email` | string (email) | **yes** | length 0–255 |
| `password` | string | **yes** | length 1–128 |
| `totpCode` | string | no | length 6–32 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/login' \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `401` | No credential, or one that is expired, revoked or unknown. |

**Example response** (`200`)

```json
{
  "user": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "email": "you@example.com",
    "displayName": "string"
  },
  "tokens": {
    "accessToken": "string",
    "accessTokenExpiresInSec": 1,
    "refreshToken": "string",
    "refreshTokenExpiresAt": "2026-09-04T14:30:00.000Z"
  }
}
```


#### `POST /api/v1/auth/logout`

**Auth:** None — this endpoint is public.

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `all` | boolean | no | default `false` |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `refreshToken` | string | **yes** | length 20–512 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/logout' \
  -H 'Content-Type: application/json' \
  -d '{"refreshToken":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |


#### `GET /api/v1/auth/mfa/totp`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/auth/mfa/totp' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "enrolled": false,
  "staged": false,
  "recoveryCodesLeft": 1
}
```


#### `POST /api/v1/auth/mfa/totp`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/mfa/totp' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |

**Example response** (`201`)

```json
{
  "secret": "string",
  "uri": "string"
}
```


#### `DELETE /api/v1/auth/mfa/totp`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `code` | string | **yes** | length 6–32 |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/auth/mfa/totp' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"code":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |


#### `POST /api/v1/auth/mfa/totp/confirm`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `code` | string | **yes** | length 6–10 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/mfa/totp/confirm' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"code":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "enrolled": false,
  "recoveryCodes": [
    "string"
  ]
}
```


#### `POST /api/v1/auth/mfa/totp/recovery-codes`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `code` | string | **yes** | length 6–32 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/mfa/totp/recovery-codes' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"code":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "recoveryCodes": [
    "string"
  ]
}
```


#### `POST /api/v1/auth/oauth`

**Auth:** None — this endpoint is public.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `provider` | `google` · `apple` | **yes** | — |
| `idToken` | string | **yes** | length 16–8192 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/oauth' \
  -H 'Content-Type: application/json' \
  -d '{"provider":"google","idToken":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `401` | No credential, or one that is expired, revoked or unknown. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "user": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "email": "you@example.com",
    "displayName": "string"
  },
  "created": false,
  "tokens": {
    "accessToken": "string",
    "accessTokenExpiresInSec": 1,
    "refreshToken": "string",
    "refreshTokenExpiresAt": "2026-09-04T14:30:00.000Z"
  }
}
```


#### `POST /api/v1/auth/password`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `currentPassword` | string | **yes** | length 1–128 |
| `newPassword` | string | **yes** | length 8–128 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/password' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"currentPassword":"string","newPassword":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |


#### `POST /api/v1/auth/refresh`

**Auth:** None — this endpoint is public.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `refreshToken` | string | **yes** | length 20–512 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/refresh' \
  -H 'Content-Type: application/json' \
  -d '{"refreshToken":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `401` | No credential, or one that is expired, revoked or unknown. |

**Example response** (`200`)

```json
{
  "user": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "email": "you@example.com",
    "displayName": "string"
  },
  "tokens": {
    "accessToken": "string",
    "accessTokenExpiresInSec": 1,
    "refreshToken": "string",
    "refreshTokenExpiresAt": "2026-09-04T14:30:00.000Z"
  }
}
```


#### `POST /api/v1/auth/register`

**Auth:** None — this endpoint is public.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `email` | string (email) | **yes** | length 0–255 |
| `password` | string | **yes** | length 8–128 |
| `displayName` | string | no | length 1–255 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/register' \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`201`)

```json
{
  "user": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "email": "you@example.com",
    "displayName": "string"
  },
  "workspace": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "name": "Pay the electricity bill",
    "slug": "pay-the-electricity-bill"
  },
  "tokens": {
    "accessToken": "string",
    "accessTokenExpiresInSec": 1,
    "refreshToken": "string",
    "refreshTokenExpiresAt": "2026-09-04T14:30:00.000Z"
  }
}
```


#### `GET /api/v1/auth/sessions`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `refreshToken` | string | no | length 20–512 |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/auth/sessions' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
[
  {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "deviceName": "string",
    "createdIp": "string",
    "lastIp": "string",
    "createdAt": "2026-09-04T14:30:00.000Z",
    "lastSeenAt": "2026-09-04T14:30:00.000Z",
    "expiresAt": "2026-09-04T14:30:00.000Z",
    "revokedAt": "2026-09-04T14:30:00.000Z",
    "current": false
  }
]
```


#### `DELETE /api/v1/auth/sessions/{id}`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `id` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/auth/sessions/:id' \
  -H "Authorization: Bearer $ALLISWELL_JWT"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |


#### `POST /api/v1/auth/sessions/revoke-others`

**Auth:** Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `refreshToken` | string | no | length 20–512 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/auth/sessions/revoke-others' \
  -H "Authorization: Bearer $ALLISWELL_JWT" \
  -H 'Content-Type: application/json' \
  -d '{"refreshToken":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "revoked": 1
}
```


### Capabilities

#### `GET /api/v1/ee/status`

**Auth:** Personal API key **or** session JWT.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/ee/status' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "state": "none",
  "features": [
    "string"
  ],
  "expiresAt": "2026-09-04T14:30:00.000Z",
  "overlay": "disabled",
  "baseDomain": "string"
}
```


### Devices

#### `GET /api/v1/notification-devices`

**Auth:** Personal API key **or** session JWT.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/notification-devices' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "platform": "ios",
      "pushToken": "string",
      "deviceName": "string",
      "appVersion": "string",
      "lastSeenAt": "2026-09-04T14:30:00.000Z",
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `PUT /api/v1/notification-devices/{deviceId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `deviceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `platform` | `ios` · `android` · `macos` · `windows` · `linux` · `web` | **yes** | — |
| `pushToken` | string or null | no | length 0–512 |
| `deviceName` | string or null | no | length 0–255 |
| `appVersion` | string or null | no | length 0–64 |

**Request**

```bash
curl -X PUT 'https://api.alliswell.space/api/v1/notification-devices/:deviceId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"platform":"ios"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "platform": "ios",
  "pushToken": "string",
  "deviceName": "string",
  "appVersion": "string",
  "lastSeenAt": "2026-09-04T14:30:00.000Z",
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/notification-devices/{deviceId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `deviceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/notification-devices/:deviceId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |


### Files

#### `GET /api/v1/files/{fileId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `fileId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/files/:fileId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "file": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "targetType": "project",
    "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "name": "Pay the electricity bill",
    "mime": "string",
    "sizeBytes": 1,
    "status": "uploading",
    "uploadedBy": "string",
    "folderId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  },
  "downloadUrl": "string",
  "downloadExpiresAt": "2026-09-04T14:30:00.000Z"
}
```


#### `PATCH /api/v1/files/{fileId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `fileId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | no | length 1–1024 |
| `folderId` | ULID or null | no | 26-character identifier |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/files/:fileId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill","folderId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "file": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "targetType": "project",
    "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "name": "Pay the electricity bill",
    "mime": "string",
    "sizeBytes": 1,
    "status": "uploading",
    "uploadedBy": "string",
    "folderId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  }
}
```


#### `DELETE /api/v1/files/{fileId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `fileId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/files/:fileId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `POST /api/v1/files/{fileId}/complete`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `fileId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/files/:fileId/complete' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "file": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "targetType": "project",
    "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "name": "Pay the electricity bill",
    "mime": "string",
    "sizeBytes": 1,
    "status": "uploading",
    "uploadedBy": "string",
    "folderId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  }
}
```


#### `PATCH /api/v1/folders/{folderId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `folderId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | no | length 1–255 |
| `parentId` | ULID or null | no | 26-character identifier |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/folders/:folderId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill","parentId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/folders/{folderId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `folderId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/folders/:folderId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "deletedFolders": 1,
  "deletedFiles": 1
}
```


#### `GET /api/v1/storage`

**Auth:** Personal API key **or** session JWT.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/storage' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "configured": false,
  "maxUploadBytes": 1,
  "presignTtlSec": 1
}
```


#### `GET /api/v1/workspaces/{workspaceId}/files`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `targetType` | `project` · `task` · `note` · `workspace` | no | — |
| `targetId` | ULID | no | 26-character identifier |
| `projectId` | ULID | no | 26-character identifier |
| `folderId` | ULID | no | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/files' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "files": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "targetType": "project",
      "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "name": "Pay the electricity bill",
      "mime": "string",
      "sizeBytes": 1,
      "status": "uploading",
      "uploadedBy": "string",
      "folderId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z",
      "source": {
        "type": "project",
        "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
        "title": "Pay the electricity bill"
      }
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/files`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `targetType` | `project` · `task` · `note` · `workspace` | **yes** | — |
| `targetId` | ULID | **yes** | 26-character identifier |
| `name` | string | **yes** | length 1–1024 |
| `sizeBytes` | integer | **yes** | 1–∞ |
| `mime` | string | no | length 1–255 |
| `folderId` | ULID or null | no | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/files' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"targetType":"project","targetId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","name":"Pay the electricity bill","sizeBytes":1}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `413` | Too large. |
| `503` | Not configured on this server. |

**Example response** (`201`)

```json
{
  "file": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "targetType": "project",
    "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "name": "Pay the electricity bill",
    "mime": "string",
    "sizeBytes": 1,
    "status": "uploading",
    "uploadedBy": "string",
    "folderId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  },
  "upload": {
    "method": "string",
    "url": "https://example.com",
    "headers": {},
    "expiresAt": "2026-09-04T14:30:00.000Z"
  }
}
```


#### `GET /api/v1/workspaces/{workspaceId}/files/usage`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/files/usage' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "totalBytes": 1,
  "fileCount": 1
}
```


#### `GET /api/v1/workspaces/{workspaceId}/folders`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/folders' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "parentId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "name": "Pay the electricity bill",
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/folders`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | **yes** | length 1–255 |
| `parentId` | ULID or null | no | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/folders' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


### Google Calendar

#### `PATCH /api/v1/integrations/google/accounts/{accountId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `accountId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `defaultCalendarId` | string | **yes** | length 1–255 |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/integrations/google/accounts/:accountId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"defaultCalendarId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "provider": "string",
  "providerAccountId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "status": "active",
  "defaultCalendarId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "lastSyncedAt": "2026-09-04T14:30:00.000Z",
  "lastError": "string",
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/integrations/google/accounts/{accountId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `accountId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/integrations/google/accounts/:accountId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `GET /api/v1/integrations/google/accounts/{accountId}/calendars`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `accountId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/integrations/google/accounts/:accountId/calendars' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `502` | An upstream service failed. |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "summary": "string",
      "primary": false
    }
  ]
}
```


#### `GET /api/v1/integrations/google/callback`

**Auth:** None — this endpoint is public.

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `code` | string | no | — |
| `state` | string | no | — |
| `error` | string | no | — |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/integrations/google/callback'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |


#### `POST /api/v1/integrations/google/webhook`

**Auth:** None — this endpoint is public.

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/integrations/google/webhook'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `401` | No credential, or one that is expired, revoked or unknown. |


#### `GET /api/v1/workspaces/{workspaceId}/integrations/google`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/integrations/google' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "configured": false,
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "provider": "string",
      "providerAccountId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "status": "active",
      "defaultCalendarId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "lastSyncedAt": "2026-09-04T14:30:00.000Z",
      "lastError": "string",
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/integrations/google/connect`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/integrations/google/connect' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "authUrl": "string"
}
```


### Health

#### `GET /health/live`

**Auth:** None — this endpoint is public.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/health/live'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "status": "ok",
  "uptimeSec": 1,
  "version": "string"
}
```


#### `GET /health/ready`

**Auth:** None — this endpoint is public.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/health/ready'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `503` | Not configured on this server. |

**Example response** (`200`)

```json
{
  "status": "ok",
  "checks": {
    "mysql": {
      "status": "up",
      "latencyMs": 1,
      "error": "string"
    },
    "redis": {
      "status": "up",
      "latencyMs": 1,
      "error": "string"
    }
  }
}
```


### Notes

#### `GET /api/v1/notes/{noteId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/notes/:noteId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "snippet": "string",
  "isPinned": false,
  "isArchived": false,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "contentDelta": [],
  "contentMarkdown": "# Heading\n\nbody",
  "contentFormat": "delta",
  "plainText": "string",
  "tagIds": [
    "string"
  ],
  "links": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "entityType": "string",
      "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
    }
  ]
}
```


#### `PATCH /api/v1/notes/{noteId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | no | length 1–500 |
| `contentDelta` | array of any | no | up to 20000 items |
| `contentMarkdown` | string or null | no | length 0–1000000 |
| `contentFormat` | `delta` · `markdown` | no | — |
| `projectId` | ULID or null | no | 26-character identifier |
| `isPinned` | boolean | no | — |
| `isArchived` | boolean | no | — |
| `baseRevision` | integer | no | 0–∞ |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/notes/:noteId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill","contentDelta":[],"contentMarkdown":"# Heading\n\nbody","contentFormat":"delta","projectId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","isPinned":false,"isArchived":false,"baseRevision":0}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "snippet": "string",
  "isPinned": false,
  "isArchived": false,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "contentDelta": [],
  "contentMarkdown": "# Heading\n\nbody",
  "contentFormat": "delta",
  "plainText": "string",
  "tagIds": [
    "string"
  ],
  "links": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "entityType": "string",
      "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
    }
  ]
}
```


#### `DELETE /api/v1/notes/{noteId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/notes/:noteId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `GET /api/v1/notes/{noteId}/export`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `format` | `md` | no | default `"md"` |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/notes/:noteId/export' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `POST /api/v1/notes/{noteId}/links`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `entityType` | `task` · `project` | **yes** | — |
| `entityId` | ULID | **yes** | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/notes/:noteId/links' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"entityType":"task","entityId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "snippet": "string",
  "isPinned": false,
  "isArchived": false,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "contentDelta": [],
  "contentMarkdown": "# Heading\n\nbody",
  "contentFormat": "delta",
  "plainText": "string",
  "tagIds": [
    "string"
  ],
  "links": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "entityType": "string",
      "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
    }
  ]
}
```


#### `DELETE /api/v1/notes/{noteId}/links/{linkId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |
| `linkId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/notes/:noteId/links/:linkId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `PUT /api/v1/notes/{noteId}/tags`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `tagIds` | array of ULID | **yes** | up to 50 items |

**Request**

```bash
curl -X PUT 'https://api.alliswell.space/api/v1/notes/:noteId/tags' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"tagIds":["01J9Z4K8QK7B2N0M3XG5T6WQ7A"]}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "snippet": "string",
  "isPinned": false,
  "isArchived": false,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "contentDelta": [],
  "contentMarkdown": "# Heading\n\nbody",
  "contentFormat": "delta",
  "plainText": "string",
  "tagIds": [
    "string"
  ],
  "links": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "entityType": "string",
      "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
    }
  ]
}
```


#### `GET /api/v1/notes/{noteId}/versions`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `limit` | integer | no | 1–100, default `50` |
| `cursor` | ULID | no | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/notes/:noteId/versions' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "noteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "noteRevision": 1,
      "title": "Pay the electricity bill",
      "contentFormat": "2026-09-04T14:30:00.000Z",
      "origin": "string",
      "clientId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "createdBy": "string",
      "sizeBytes": 1,
      "createdAt": "2026-09-04T14:30:00.000Z"
    }
  ],
  "nextCursor": "string"
}
```


#### `GET /api/v1/notes/{noteId}/versions/{versionId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |
| `versionId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/notes/:noteId/versions/:versionId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "noteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "noteRevision": 1,
  "title": "Pay the electricity bill",
  "contentFormat": "2026-09-04T14:30:00.000Z",
  "origin": "string",
  "clientId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "createdBy": "string",
  "sizeBytes": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "contentMarkdown": "# Heading\n\nbody",
  "contentDelta": []
}
```


#### `GET /api/v1/notes/{noteId}/versions/{versionId}/diff`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |
| `versionId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/notes/:noteId/versions/:versionId/diff' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "segments": [
    {
      "type": "equal",
      "value": "string"
    }
  ],
  "comparable": false
}
```


#### `POST /api/v1/notes/{noteId}/versions/{versionId}/restore`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `noteId` | ULID | 26-character identifier |
| `versionId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `mode` | `replace` · `copy` | no | default `"replace"` |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/notes/:noteId/versions/:versionId/restore' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"mode":"replace"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{}
```


#### `GET /api/v1/projects/{projectId}/notes`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `projectId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `includeArchived` | boolean | no | default `false` |
| `limit` | integer | no | 1–200, default `50` |
| `cursor` | ULID | no | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/projects/:projectId/notes' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "snippet": "string",
      "isPinned": false,
      "isArchived": false,
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ],
  "nextCursor": "string"
}
```


#### `GET /api/v1/workspaces/{workspaceId}/export/notes`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `limit` | integer | no | 1–200, default `100` |
| `cursor` | ULID | no | 26-character identifier |
| `includeArchived` | boolean | no | default `true` |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/export/notes' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "notes": [
    {}
  ],
  "nextCursor": "string"
}
```


#### `POST /api/v1/workspaces/{workspaceId}/import/notes`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `notes` | array of object | **yes** | up to 500 items |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/import/notes' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"notes":[{"title":"Pay the electricity bill"}]}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "created": [
    "string"
  ],
  "errors": [
    {
      "index": 1,
      "code": "string",
      "message": "string"
    }
  ]
}
```


#### `GET /api/v1/workspaces/{workspaceId}/notes`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `pinned` | boolean | no | — |
| `archived` | boolean | no | — |
| `includeArchived` | boolean | no | default `false` |
| `readme` | boolean | no | — |
| `projectId` | ULID | no | 26-character identifier |
| `taskId` | ULID | no | 26-character identifier |
| `q` | string | no | length 1–200 |
| `limit` | integer | no | 1–200, default `50` |
| `cursor` | ULID | no | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/notes' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "snippet": "string",
      "isPinned": false,
      "isArchived": false,
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ],
  "nextCursor": "string"
}
```


#### `POST /api/v1/workspaces/{workspaceId}/notes`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | **yes** | length 1–500 |
| `contentDelta` | array of any | no | up to 20000 items |
| `contentMarkdown` | string or null | no | length 0–1000000 |
| `contentFormat` | `delta` · `markdown` | no | — |
| `projectId` | ULID or null | no | 26-character identifier |
| `isPinned` | boolean | no | — |
| `isArchived` | boolean | no | — |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/notes' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "snippet": "string",
  "isPinned": false,
  "isArchived": false,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "contentDelta": [],
  "contentMarkdown": "# Heading\n\nbody",
  "contentFormat": "delta",
  "plainText": "string",
  "tagIds": [
    "string"
  ],
  "links": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "entityType": "string",
      "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
    }
  ]
}
```


### Projects

#### `GET /api/v1/projects/{projectId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `projectId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/projects/:projectId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "description": "What this is for",
  "colorRgb": "string",
  "icon": "string",
  "status": "active",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "sortOrder": 1,
  "isFavorite": false,
  "readmeNoteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `PATCH /api/v1/projects/{projectId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `projectId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | no | length 1–255 |
| `description` | string or null | no | length 0–65535 |
| `colorRgb` | string | no | pattern `^#[0-9A-Fa-f]{6}$` |
| `icon` | string or null | no | length 0–64 |
| `status` | `active` · `paused` · `completed` · `archived` | no | — |
| `startAt` | string (date-time) or null | no | — |
| `dueAt` | string (date-time) or null | no | — |
| `sortOrder` | integer | no | -1000000–1000000 |
| `isFavorite` | boolean | no | — |
| `readmeNoteId` | ULID or null | no | 26-character identifier |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/projects/:projectId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill","description":"What this is for","colorRgb":"#0A5CFF","icon":"string","status":"active","startAt":"2026-09-04T14:30:00.000Z","dueAt":"2026-09-04T14:30:00.000Z","sortOrder":-1000000,"isFavorite":false,"readmeNoteId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "description": "What this is for",
  "colorRgb": "string",
  "icon": "string",
  "status": "active",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "sortOrder": 1,
  "isFavorite": false,
  "readmeNoteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/projects/{projectId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `projectId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/projects/:projectId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `POST /api/v1/projects/{projectId}/archive`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `projectId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `includeTasks` | boolean | no | default `false` |
| `includeNotes` | boolean | no | default `false` |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/projects/:projectId/archive' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"includeTasks":false,"includeNotes":false}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "project": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "name": "Pay the electricity bill",
    "description": "What this is for",
    "colorRgb": "string",
    "icon": "string",
    "status": "active",
    "startAt": "2026-09-04T14:30:00.000Z",
    "dueAt": "2026-09-04T14:30:00.000Z",
    "sortOrder": 1,
    "isFavorite": false,
    "readmeNoteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  },
  "tasksChanged": 1,
  "notesChanged": 1
}
```


#### `POST /api/v1/projects/{projectId}/unarchive`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `projectId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `includeTasks` | boolean | no | default `false` |
| `includeNotes` | boolean | no | default `false` |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/projects/:projectId/unarchive' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"includeTasks":false,"includeNotes":false}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "project": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "name": "Pay the electricity bill",
    "description": "What this is for",
    "colorRgb": "string",
    "icon": "string",
    "status": "active",
    "startAt": "2026-09-04T14:30:00.000Z",
    "dueAt": "2026-09-04T14:30:00.000Z",
    "sortOrder": 1,
    "isFavorite": false,
    "readmeNoteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  },
  "tasksChanged": 1,
  "notesChanged": 1
}
```


#### `GET /api/v1/workspaces/{workspaceId}/projects`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `status` | `active` · `paused` · `completed` · `archived` | no | — |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/projects' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "name": "Pay the electricity bill",
      "description": "What this is for",
      "colorRgb": "string",
      "icon": "string",
      "status": "active",
      "startAt": "2026-09-04T14:30:00.000Z",
      "dueAt": "2026-09-04T14:30:00.000Z",
      "sortOrder": 1,
      "isFavorite": false,
      "readmeNoteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/projects`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | **yes** | length 1–255 |
| `description` | string or null | no | length 0–65535 |
| `colorRgb` | string | no | pattern `^#[0-9A-Fa-f]{6}$` |
| `icon` | string or null | no | length 0–64 |
| `status` | `active` · `paused` · `completed` · `archived` | no | — |
| `startAt` | string (date-time) or null | no | — |
| `dueAt` | string (date-time) or null | no | — |
| `sortOrder` | integer | no | -1000000–1000000 |
| `isFavorite` | boolean | no | — |
| `readmeNoteId` | ULID or null | no | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/projects' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "description": "What this is for",
  "colorRgb": "string",
  "icon": "string",
  "status": "active",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "sortOrder": 1,
  "isFavorite": false,
  "readmeNoteId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


### Quick links

#### `PATCH /api/v1/quick-links/{quickLinkId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `quickLinkId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | no | length 1–200 |
| `emoji` | string or null | no | length 1–16 |
| `colorRgb` | string or null | no | pattern `^#[0-9A-Fa-f]{6}$` |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/quick-links/:quickLinkId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill","emoji":"string","colorRgb":"#0A5CFF"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "kind": "string",
  "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "url": "https://example.com",
  "title": "Pay the electricity bill",
  "emoji": "string",
  "colorRgb": "string",
  "sortOrder": 1,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/quick-links/{quickLinkId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `quickLinkId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/quick-links/:quickLinkId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `GET /api/v1/workspaces/{workspaceId}/quick-links`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/quick-links' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "kind": "string",
      "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "url": "https://example.com",
      "title": "Pay the electricity bill",
      "emoji": "string",
      "colorRgb": "string",
      "sortOrder": 1,
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/quick-links`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `kind` | `project` · `task` · `note` · `folder` · `file` · `url` | **yes** | — |
| `targetId` | ULID or null | no | 26-character identifier |
| `url` | string or null | no | length 0–2048 |
| `title` | string | **yes** | length 1–200 |
| `emoji` | string or null | no | length 1–16 |
| `colorRgb` | string or null | no | pattern `^#[0-9A-Fa-f]{6}$` |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/quick-links' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"kind":"project","title":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |
| `422` | Well-formed, but refused by a business rule. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "kind": "string",
  "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "url": "https://example.com",
  "title": "Pay the electricity bill",
  "emoji": "string",
  "colorRgb": "string",
  "sortOrder": 1,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `PUT /api/v1/workspaces/{workspaceId}/quick-links/order`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `orderedIds` | array of ULID | **yes** | up to 50 items |

**Request**

```bash
curl -X PUT 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/quick-links/order' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"orderedIds":["01J9Z4K8QK7B2N0M3XG5T6WQ7A"]}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `422` | Well-formed, but refused by a business rule. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "userId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "kind": "string",
      "targetId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "url": "https://example.com",
      "title": "Pay the electricity bill",
      "emoji": "string",
      "colorRgb": "string",
      "sortOrder": 1,
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


### Recurrence

#### `GET /api/v1/task-series/{seriesId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `seriesId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/task-series/:seriesId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "rule": {},
  "template": {},
  "timezone": "Europe/Istanbul",
  "anchorAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `PATCH /api/v1/task-series/{seriesId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `seriesId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `rule` | object | no | — |
| `template` | object | no | — |
| `timezone` | string | no | length 1–64 |
| `anchorAt` | string (date-time) | no | — |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/task-series/:seriesId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"rule":{},"template":{},"timezone":"Europe/Istanbul","anchorAt":"2026-09-04T14:30:00.000Z"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `422` | Well-formed, but refused by a business rule. |

**Example response** (`200`)

```json
{
  "series": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "rule": {},
    "template": {},
    "timezone": "Europe/Istanbul",
    "anchorAt": "2026-09-04T14:30:00.000Z",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  },
  "created": 1,
  "removed": 1
}
```


#### `DELETE /api/v1/task-series/{seriesId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `seriesId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `fromDay` | string | no | pattern `^\d{4}-\d{2}-\d{2}$` |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/task-series/:seriesId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "removed": 1
}
```


#### `GET /api/v1/workspaces/{workspaceId}/task-series`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/task-series' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "series": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "rule": {},
      "template": {},
      "timezone": "Europe/Istanbul",
      "anchorAt": "2026-09-04T14:30:00.000Z",
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/task-series`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `rule` | object | **yes** | — |
| `template` | object | **yes** | — |
| `timezone` | string | no | length 1–64 |
| `anchorAt` | string (date-time) | **yes** | — |
| `fromTaskId` | ULID or null | no | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/task-series' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"rule":{},"template":{},"anchorAt":"2026-09-04T14:30:00.000Z"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `422` | Well-formed, but refused by a business rule. |

**Example response** (`201`)

```json
{
  "series": {
    "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
    "rule": {},
    "template": {},
    "timezone": "Europe/Istanbul",
    "anchorAt": "2026-09-04T14:30:00.000Z",
    "revision": 1,
    "createdAt": "2026-09-04T14:30:00.000Z",
    "updatedAt": "2026-09-04T14:30:00.000Z"
  },
  "created": 1,
  "adoptedTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
}
```


### Reminders

#### `POST /api/v1/reminders/{reminderId}/acknowledge`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `reminderId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/reminders/:reminderId/acknowledge' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "taskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "kind": "string",
  "snoozeCount": 1,
  "remindAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "alarmLevel": "string",
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "status": "string",
  "snoozedUntil": "string",
  "deliveredAt": "2026-09-04T14:30:00.000Z",
  "acknowledgedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


### Service

#### `GET /`

**Auth:** None — this endpoint is public.

**Request**

```bash
curl -X GET 'https://api.alliswell.space/'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |

**Example response** (`200`)

```json
{
  "name": "Pay the electricity bill",
  "version": "string",
  "docs": "string",
  "health": "string"
}
```


### Sync

#### `GET /api/v1/sync/pull`

**Auth:** Personal API key **or** session JWT.

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `workspaceId` | ULID | yes | 26-character identifier |
| `sinceRevision` | integer | yes | 0–∞ |
| `limit` | integer | no | 1–500, default `200` |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/sync/pull' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "fromRevision": 1,
  "toRevision": 1,
  "hasMore": false,
  "changes": [
    {
      "revision": 1,
      "entityType": "string",
      "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "operation": "create",
      "data": {}
    }
  ]
}
```


#### `POST /api/v1/sync/push`

**Auth:** Personal API key **or** session JWT.

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `clientId` | ULID | **yes** | 26-character identifier |
| `workspaceId` | ULID | **yes** | 26-character identifier |
| `baseRevision` | integer | **yes** | 0–∞ |
| `mutations` | array of object | **yes** | up to 100 items |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/sync/push' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"clientId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","workspaceId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","baseRevision":0,"mutations":[{"clientMutationId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","entityType":"string","entityId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","operation":"create"}]}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "toRevision": 1,
  "results": [
    {
      "clientMutationId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "status": "applied",
      "revision": 1,
      "errorCode": "string",
      "replayed": false,
      "discardedFields": [
        "string"
      ],
      "conflictVersionId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "rebase": {
        "entityType": "string",
        "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
        "present": false,
        "data": {}
      },
      "reason": "string",
      "merged": {
        "contentMarkdown": "# Heading\n\nbody",
        "contentFormat": "2026-09-04T14:30:00.000Z"
      }
    }
  ]
}
```


### Tags

#### `GET /api/v1/tags/{tagId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `tagId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/tags/:tagId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "slug": "pay-the-electricity-bill",
  "colorRgb": "string",
  "icon": "string",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `PATCH /api/v1/tags/{tagId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `tagId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | no | length 1–100 |
| `colorRgb` | string | no | pattern `^#[0-9A-Fa-f]{6}$` |
| `icon` | string or null | no | length 0–64 |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/tags/:tagId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill","colorRgb":"#0A5CFF","icon":"string"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "slug": "pay-the-electricity-bill",
  "colorRgb": "string",
  "icon": "string",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/tags/{tagId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `tagId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/tags/:tagId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `GET /api/v1/workspaces/{workspaceId}/tags`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/tags' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "name": "Pay the electricity bill",
      "slug": "pay-the-electricity-bill",
      "colorRgb": "string",
      "icon": "string",
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/tags`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | **yes** | length 1–100 |
| `colorRgb` | string | no | pattern `^#[0-9A-Fa-f]{6}$` |
| `icon` | string or null | no | length 0–64 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/tags' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "name": "Pay the electricity bill",
  "slug": "pay-the-electricity-bill",
  "colorRgb": "string",
  "icon": "string",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


### Tasks

#### `GET /api/v1/tasks/{taskId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/tasks/:taskId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "description": "What this is for",
  "status": "inbox",
  "priority": "none",
  "colorRgb": "string",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "scheduledStartAt": "2026-09-04T14:30:00.000Z",
  "scheduledEndAt": "2026-09-04T14:30:00.000Z",
  "remindAt": "2026-09-04T14:30:00.000Z",
  "snoozedUntil": "string",
  "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "isUrgent": false,
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "occurrenceDate": "string",
  "estimatedMinutes": 1,
  "actualMinutes": 1,
  "sortOrder": 1,
  "calendarMirrorEnabled": false,
  "completedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "tagIds": [
    "string"
  ],
  "checklist": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "isDone": false,
      "sortOrder": 1,
      "revision": 1
    }
  ]
}
```


#### `PATCH /api/v1/tasks/{taskId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | no | length 1–500 |
| `description` | string or null | no | length 0–65535 |
| `projectId` | ULID or null | no | 26-character identifier |
| `parentTaskId` | ULID or null | no | 26-character identifier |
| `status` | `inbox` · `open` · `scheduled` · `in_progress` · `waiting` · `completed` · `cancelled` · `archived` | no | — |
| `priority` | `none` · `low` · `medium` · `high` · `urgent` | no | — |
| `colorRgb` | string or null | no | pattern `^#[0-9A-Fa-f]{6}$` |
| `startAt` | string (date-time) or null | no | — |
| `dueAt` | string (date-time) or null | no | — |
| `scheduledStartAt` | string (date-time) or null | no | — |
| `scheduledEndAt` | string (date-time) or null | no | — |
| `remindAt` | string (date-time) or null | no | — |
| `timezone` | string | no | length 1–64 |
| `isUrgent` | boolean | no | — |
| `requiresAcknowledgement` | boolean | no | — |
| `estimatedMinutes` | integer or null | no | 0–60000 |
| `actualMinutes` | integer or null | no | 0–60000 |
| `sortOrder` | integer | no | -1000000–1000000 |
| `calendarMirrorEnabled` | boolean | no | — |
| `alarmsMutedAt` | string (date-time) or null | no | — |
| `seriesScope` | `this` · `future` · `all` | no | — |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/tasks/:taskId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill","description":"What this is for","projectId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","parentTaskId":"01J9Z4K8QK7B2N0M3XG5T6WQ7A","status":"inbox","priority":"none","colorRgb":"#0A5CFF","startAt":"2026-09-04T14:30:00.000Z","dueAt":"2026-09-04T14:30:00.000Z","scheduledStartAt":"2026-09-04T14:30:00.000Z","scheduledEndAt":"2026-09-04T14:30:00.000Z","remindAt":"2026-09-04T14:30:00.000Z","timezone":"Europe/Istanbul","isUrgent":false,"requiresAcknowledgement":false,"estimatedMinutes":0,"actualMinutes":0,"sortOrder":-1000000,"calendarMirrorEnabled":false,"alarmsMutedAt":"2026-09-04T14:30:00.000Z","seriesScope":"this"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "description": "What this is for",
  "status": "inbox",
  "priority": "none",
  "colorRgb": "string",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "scheduledStartAt": "2026-09-04T14:30:00.000Z",
  "scheduledEndAt": "2026-09-04T14:30:00.000Z",
  "remindAt": "2026-09-04T14:30:00.000Z",
  "snoozedUntil": "string",
  "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "isUrgent": false,
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "occurrenceDate": "string",
  "estimatedMinutes": 1,
  "actualMinutes": 1,
  "sortOrder": 1,
  "calendarMirrorEnabled": false,
  "completedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "tagIds": [
    "string"
  ],
  "checklist": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "isDone": false,
      "sortOrder": 1,
      "revision": 1
    }
  ]
}
```


#### `DELETE /api/v1/tasks/{taskId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/tasks/:taskId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `POST /api/v1/tasks/{taskId}/checklist`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | **yes** | length 1–500 |
| `sortOrder` | integer | no | -1000000–1000000 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/tasks/:taskId/checklist' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "taskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "isDone": false,
  "sortOrder": 1,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `PATCH /api/v1/tasks/{taskId}/checklist/{itemId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |
| `itemId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | no | length 1–500 |
| `isDone` | boolean | no | — |
| `sortOrder` | integer | no | -1000000–1000000 |

**Request**

```bash
curl -X PATCH 'https://api.alliswell.space/api/v1/tasks/:taskId/checklist/:itemId' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill","isDone":false,"sortOrder":-1000000}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "taskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "isDone": false,
  "sortOrder": 1,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z"
}
```


#### `DELETE /api/v1/tasks/{taskId}/checklist/{itemId}`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |
| `itemId` | ULID | 26-character identifier |

**Request**

```bash
curl -X DELETE 'https://api.alliswell.space/api/v1/tasks/:taskId/checklist/:itemId' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `204` | Done. No body. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |


#### `POST /api/v1/tasks/{taskId}/complete`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/tasks/:taskId/complete' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "description": "What this is for",
  "status": "inbox",
  "priority": "none",
  "colorRgb": "string",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "scheduledStartAt": "2026-09-04T14:30:00.000Z",
  "scheduledEndAt": "2026-09-04T14:30:00.000Z",
  "remindAt": "2026-09-04T14:30:00.000Z",
  "snoozedUntil": "string",
  "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "isUrgent": false,
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "occurrenceDate": "string",
  "estimatedMinutes": 1,
  "actualMinutes": 1,
  "sortOrder": 1,
  "calendarMirrorEnabled": false,
  "completedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "tagIds": [
    "string"
  ],
  "checklist": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "isDone": false,
      "sortOrder": 1,
      "revision": 1
    }
  ]
}
```


#### `POST /api/v1/tasks/{taskId}/notes`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | no | length 1–500 |
| `contentDelta` | array of any | no | up to 20000 items |
| `contentMarkdown` | string or null | no | length 0–1000000 |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/tasks/:taskId/notes' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill","contentDelta":[],"contentMarkdown":"# Heading\n\nbody"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "createdFromTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "snippet": "string",
  "isPinned": false,
  "isArchived": false,
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "contentDelta": [],
  "contentMarkdown": "# Heading\n\nbody",
  "contentFormat": "delta",
  "plainText": "string",
  "tagIds": [
    "string"
  ],
  "links": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "entityType": "string",
      "entityId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A"
    }
  ]
}
```


#### `POST /api/v1/tasks/{taskId}/reopen`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/tasks/:taskId/reopen' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "description": "What this is for",
  "status": "inbox",
  "priority": "none",
  "colorRgb": "string",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "scheduledStartAt": "2026-09-04T14:30:00.000Z",
  "scheduledEndAt": "2026-09-04T14:30:00.000Z",
  "remindAt": "2026-09-04T14:30:00.000Z",
  "snoozedUntil": "string",
  "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "isUrgent": false,
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "occurrenceDate": "string",
  "estimatedMinutes": 1,
  "actualMinutes": 1,
  "sortOrder": 1,
  "calendarMirrorEnabled": false,
  "completedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "tagIds": [
    "string"
  ],
  "checklist": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "isDone": false,
      "sortOrder": 1,
      "revision": 1
    }
  ]
}
```


#### `POST /api/v1/tasks/{taskId}/snooze`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `preset` | `5_min` · `30_min` · `1_hour` · `tomorrow_morning` | no | — |
| `snoozeUntil` | string (date-time) | no | — |
| `reminderId` | ULID | no | 26-character identifier |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/tasks/:taskId/snooze' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |
| `409` | Refused because of a uniqueness or state clash (e.g. an edit conflict). |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "description": "What this is for",
  "status": "inbox",
  "priority": "none",
  "colorRgb": "string",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "scheduledStartAt": "2026-09-04T14:30:00.000Z",
  "scheduledEndAt": "2026-09-04T14:30:00.000Z",
  "remindAt": "2026-09-04T14:30:00.000Z",
  "snoozedUntil": "string",
  "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "isUrgent": false,
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "occurrenceDate": "string",
  "estimatedMinutes": 1,
  "actualMinutes": 1,
  "sortOrder": 1,
  "calendarMirrorEnabled": false,
  "completedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "tagIds": [
    "string"
  ],
  "checklist": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "isDone": false,
      "sortOrder": 1,
      "revision": 1
    }
  ]
}
```


#### `PUT /api/v1/tasks/{taskId}/tags`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `taskId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `tagIds` | array of ULID | **yes** | up to 50 items |

**Request**

```bash
curl -X PUT 'https://api.alliswell.space/api/v1/tasks/:taskId/tags' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"tagIds":["01J9Z4K8QK7B2N0M3XG5T6WQ7A"]}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |
| `404` | Not visible to you. Someone else’s row answers 404, never 403. |

**Example response** (`200`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "description": "What this is for",
  "status": "inbox",
  "priority": "none",
  "colorRgb": "string",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "scheduledStartAt": "2026-09-04T14:30:00.000Z",
  "scheduledEndAt": "2026-09-04T14:30:00.000Z",
  "remindAt": "2026-09-04T14:30:00.000Z",
  "snoozedUntil": "string",
  "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "isUrgent": false,
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "occurrenceDate": "string",
  "estimatedMinutes": 1,
  "actualMinutes": 1,
  "sortOrder": 1,
  "calendarMirrorEnabled": false,
  "completedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "tagIds": [
    "string"
  ],
  "checklist": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "isDone": false,
      "sortOrder": 1,
      "revision": 1
    }
  ]
}
```


#### `POST /api/v1/workspaces/{workspaceId}/import/tasks`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `tasks` | array of object | **yes** | up to 500 items |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/import/tasks' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"tasks":[{"title":"Pay the electricity bill"}]}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "created": [
    "string"
  ],
  "errors": [
    {
      "index": 1,
      "code": "string",
      "message": "string"
    }
  ]
}
```


#### `GET /api/v1/workspaces/{workspaceId}/tasks`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Query parameters**

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `status` | array of `inbox` · `open` · `scheduled` · `in_progress` · `waiting` · `completed` · `cancelled` · `archived` | no | — |
| `projectId` | ULID | no | 26-character identifier |
| `parentTaskId` | ULID | no | 26-character identifier |
| `tagId` | ULID | no | 26-character identifier |
| `dueFrom` | string (date-time) | no | — |
| `dueTo` | string (date-time) | no | — |
| `urgent` | boolean | no | — |
| `q` | string | no | length 1–200 |
| `limit` | integer | no | 1–200, default `50` |
| `cursor` | ULID | no | 26-character identifier |

**Request**

```bash
curl -X GET 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/tasks' \
  -H "Authorization: Bearer $ALLISWELL_KEY"
```

**Responses**

| Status | Meaning |
| --- | --- |
| `200` | Success. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`200`)

```json
{
  "items": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "description": "What this is for",
      "status": "inbox",
      "priority": "none",
      "colorRgb": "string",
      "startAt": "2026-09-04T14:30:00.000Z",
      "dueAt": "2026-09-04T14:30:00.000Z",
      "scheduledStartAt": "2026-09-04T14:30:00.000Z",
      "scheduledEndAt": "2026-09-04T14:30:00.000Z",
      "remindAt": "2026-09-04T14:30:00.000Z",
      "snoozedUntil": "string",
      "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
      "timezone": "Europe/Istanbul",
      "isUrgent": false,
      "requiresAcknowledgement": false,
      "repeatRule": "string",
      "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "occurrenceDate": "string",
      "estimatedMinutes": 1,
      "actualMinutes": 1,
      "sortOrder": 1,
      "calendarMirrorEnabled": false,
      "completedAt": "2026-09-04T14:30:00.000Z",
      "revision": 1,
      "createdAt": "2026-09-04T14:30:00.000Z",
      "updatedAt": "2026-09-04T14:30:00.000Z"
    }
  ],
  "nextCursor": "string"
}
```


#### `POST /api/v1/workspaces/{workspaceId}/tasks`

**Auth:** Personal API key **or** session JWT.

**Path parameters**

| Name | Type | Notes |
| --- | --- | --- |
| `workspaceId` | ULID | 26-character identifier |

**Request body**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | **yes** | length 1–500 |
| `description` | string or null | no | length 0–65535 |
| `projectId` | ULID or null | no | 26-character identifier |
| `parentTaskId` | ULID or null | no | 26-character identifier |
| `status` | `inbox` · `open` · `scheduled` · `in_progress` · `waiting` · `completed` · `cancelled` · `archived` | no | — |
| `priority` | `none` · `low` · `medium` · `high` · `urgent` | no | — |
| `colorRgb` | string or null | no | pattern `^#[0-9A-Fa-f]{6}$` |
| `startAt` | string (date-time) or null | no | — |
| `dueAt` | string (date-time) or null | no | — |
| `scheduledStartAt` | string (date-time) or null | no | — |
| `scheduledEndAt` | string (date-time) or null | no | — |
| `remindAt` | string (date-time) or null | no | — |
| `timezone` | string | no | length 1–64 |
| `isUrgent` | boolean | no | — |
| `requiresAcknowledgement` | boolean | no | — |
| `estimatedMinutes` | integer or null | no | 0–60000 |
| `actualMinutes` | integer or null | no | 0–60000 |
| `sortOrder` | integer | no | -1000000–1000000 |
| `calendarMirrorEnabled` | boolean | no | — |
| `alarmsMutedAt` | string (date-time) or null | no | — |
| `tagIds` | array of ULID | no | up to 50 items |

**Request**

```bash
curl -X POST 'https://api.alliswell.space/api/v1/workspaces/:workspaceId/tasks' \
  -H "Authorization: Bearer $ALLISWELL_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Pay the electricity bill"}'
```

**Responses**

| Status | Meaning |
| --- | --- |
| `201` | Created. |
| `400` | A field is malformed or missing. The body names a `code`. |
| `403` | Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route. |

**Example response** (`201`)

```json
{
  "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "workspaceId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "projectId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "parentTaskId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "title": "Pay the electricity bill",
  "description": "What this is for",
  "status": "inbox",
  "priority": "none",
  "colorRgb": "string",
  "startAt": "2026-09-04T14:30:00.000Z",
  "dueAt": "2026-09-04T14:30:00.000Z",
  "scheduledStartAt": "2026-09-04T14:30:00.000Z",
  "scheduledEndAt": "2026-09-04T14:30:00.000Z",
  "remindAt": "2026-09-04T14:30:00.000Z",
  "snoozedUntil": "string",
  "alarmsMutedAt": "2026-09-04T14:30:00.000Z",
  "timezone": "Europe/Istanbul",
  "isUrgent": false,
  "requiresAcknowledgement": false,
  "repeatRule": "string",
  "seriesId": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
  "occurrenceDate": "string",
  "estimatedMinutes": 1,
  "actualMinutes": 1,
  "sortOrder": 1,
  "calendarMirrorEnabled": false,
  "completedAt": "2026-09-04T14:30:00.000Z",
  "revision": 1,
  "createdAt": "2026-09-04T14:30:00.000Z",
  "updatedAt": "2026-09-04T14:30:00.000Z",
  "tagIds": [
    "string"
  ],
  "checklist": [
    {
      "id": "01J9Z4K8QK7B2N0M3XG5T6WQ7A",
      "title": "Pay the electricity bill",
      "isDone": false,
      "sortOrder": 1,
      "revision": 1
    }
  ]
}
```


<!-- END GENERATED REFERENCE -->

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
