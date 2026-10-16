# Connect AllisWell to Claude or ChatGPT (MCP)

AllisWell ships a **remote MCP server** — a connector you add to your *own*
Claude or ChatGPT account. The assistant then reads and updates your AllisWell
workspace using **your** subscription; AllisWell spends nothing on model calls.
This is Track A of the AI design ([AI.md](AI.md); [ADR-0022](adr/0022-remote-mcp-server.md)).

## The connector URL

| You use… | Connector URL |
| --- | --- |
| **alliswell.space** (the hosted app) | **`https://api.alliswell.space/mcp`** |
| Your own server | `https://<API_PUBLIC_URL>/mcp` — e.g. `https://api.your-domain.example/mcp` |

The URL lives on the **API** host, not the website. `https://alliswell.space/mcp`
is the marketing site; it forwards to the address above, but paste the `api.`
address so nothing depends on the forward. The app shows the exact URL for your
server under **Settings → Integrations → Add to Claude / ChatGPT**, with a copy button.

- Transport: Streamable HTTP · Auth: OAuth 2.1 with PKCE (S256)
- Client registration: dynamic (RFC 7591) **and** client ID metadata documents
  ([ADR-0047](adr/0047-oauth-client-id-metadata-documents.md)) — every option
  Claude offers works
- Discovery: `https://api.alliswell.space/.well-known/oauth-protected-resource`
  and `https://api.alliswell.space/.well-known/oauth-authorization-server`

Writing a script rather than asking an assistant? That is the REST API and a
personal key instead: [API.md](API.md).

## Add it to Claude (Free, Pro, Max)

1. Open **Settings → Connectors → Add custom connector**.
2. Name it `AllisWell` and paste `https://api.alliswell.space/mcp`.
3. Leave the advanced OAuth settings as they are and press **Add**, then **Connect**.
4. AllisWell's sign-in page opens: log in with your AllisWell email and
   password, or press **Continue with Google** / **Continue with Apple** if that
   is how you sign in to the app. Enter your authenticator code if two-factor
   authentication is on, pick a workspace if you have several, and approve.
5. In a chat, open the tools menu and make sure AllisWell is switched on.

## Add it to Claude Team or Enterprise

On Team and Enterprise plans only an **Owner** can add a custom connector, and
each member then connects with their own AllisWell account.

1. **Owner:** **Organization settings → Connectors → Add → Add custom connector**,
   name `AllisWell`, URL `https://api.alliswell.space/mcp`, save. Any OAuth client
   option works — *Use Claude's published identity* (the default) or *Register
   automatically*; there is no client ID or secret to enter.
2. **Every member:** **Settings → Connectors**, find AllisWell (tagged *Custom*),
   press **Connect** and sign in with their own AllisWell account.

Each member's connection reaches only that member's own workspace.

## Add it to ChatGPT

1. In ChatGPT (Plus / Pro / Business) enable **Settings → Apps & Connectors →
   Advanced settings → Developer mode**.
2. **Create** a connector, paste `https://api.alliswell.space/mcp`, choose OAuth.
3. Sign in and approve, exactly as above.

## Add it to Claude Code or another MCP client

```bash
claude mcp add --transport http alliswell https://api.alliswell.space/mcp
```

Then run `/mcp` inside Claude Code to sign in. Any client that speaks Streamable
HTTP with OAuth (Cursor, VS Code, the MCP Inspector) takes the same URL.

## Things to ask

- "What is overdue today?"
- "Add 'renew passport' to my Errands project for next Friday, urgent."
- "Summarise my notes on the kitchen renovation and list the open tasks."
- "Snooze the dentist reminder until tomorrow morning."

## Troubleshooting

| What you see | Why, and what to do |
| --- | --- |
| *Couldn't register with AllisWell's sign-in service* | The URL is not the API's. Use `https://api.alliswell.space/mcp` (or your own `API_PUBLIC_URL` + `/mcp`), remove the connector and add it again. |
| The sign-in page says *The client's metadata document could not be loaded* | The AI app's identity document was unreachable for a moment. Try again; if it persists, re-add the connector with *Register automatically*. |
| *Email or password is wrong* | Use the email and password of your AllisWell account. If you sign in to the app with Google or Apple, use **Continue with Google / Apple** instead — such an account has no password. |
| *No AllisWell account uses this Google/Apple account yet* | The provider signed you in with an account AllisWell does not know — usually the wrong one in Google's account chooser. Pick the account you use in the app, or sign up in the app first; the sign-in page never creates an account. |
| *That code is not right* | Two-factor authentication is on: enter the current code from your authenticator app, or one of your recovery codes (each works once). |
| The connector is listed but has no tools | Open a new chat and switch AllisWell on in the tools menu. On Team/Enterprise, an Owner may have disabled it or some of its tools. |
| Self-hosted: every request fails | `curl -i https://<your-api>/mcp` must answer **401** with a `www-authenticate: Bearer resource_metadata=…` header. HTML means the request reached a website, not the API; 404 means `API_PUBLIC_URL` is unset, is not https, or `MCP_ENABLED=false`. |

Still stuck? Write to info@bubiapps.com — we answer within two working days.

## What the AI can do

Twenty-five tools, no delete tool — by design (loosening it needs a new ADR):

**Tasks**

| Tool | What it does |
| --- | --- |
| `list_tasks` | Filtered list, plus `today` / `overdue` in your timezone. `today` = due today, or its "when" day has come and it is not overdue. Every task read returns `startAt` ("when") and `estimatedMinutes` |
| `get_task` | One task in full — checklist, tags, project, alarms, its notes and how it repeats (`repeat`) |
| `create_task` | Create a task; an unknown/ambiguous project creates nothing and asks. Takes `startAt` ("when": the day it shows in Today, never the deadline or the alarm) and `estimatedMinutes` (the calendar block length) |
| `update_task` | Change title, description, status, priority, dates (incl. `startAt` "when"), duration (`estimatedMinutes`, `null` clears), urgency, project or tags |
| `complete_task` / `reopen_task` | Mark a task done, or put a finished one back to open. For a task that repeats after completion, `complete_task` returns the `next` task it created; reopening withdraws it |
| `set_task_repeat` | Make a task repeat, or change how: a calendar pattern ("every month on the 31st") or N days/weeks/months **after completion** (`basis: "completion"` — "change the water filter 90 days after I change it") |
| `snooze_task` | Push a task's alarms out (5 min / 30 min / 1 hour / tomorrow morning, or a time you name) |
| `add_checklist_item` / `set_checklist_item` | Add a checklist item, tick it, or rename it |
| `acknowledge_reminder` | Answer an urgent alarm that is waiting for you |

**Notes, projects, tags, files**

| Tool | What it does |
| --- | --- |
| `search` | Find tasks, notes, projects, tags and file names (Turkish-aware folding); `types` narrows to any of the five. A file result is metadata (name, mime, target) — no link, no bytes |
| `list_notes` / `get_note` | Notes with a short summary; one note in full, with its tags and what it is attached to |
| `create_note` | Write a note — standalone, filed under a project, or attached to a task in the same write |
| `update_note` | Retitle, rewrite, pin or archive a note (see the rich-text note below) |
| `link_note` / `unlink_note` | Attach a note to a task or project, or detach it |
| `list_projects` / `get_project` | Projects with their open-task counts |
| `create_project` / `update_project` | Make a project, change its name, description, status or due date |
| `list_tags` / `create_tag` | See the tags you use; add a new one |
| `list_files` | Attachment names, types and sizes — **never** the file contents |

Plus three read-only resources: **today**, **overdue** and **inbox** task views.

Write tools are annotated so Claude/ChatGPT show you an approval prompt before
they run, and every AI-made change is recorded in AllisWell's action log. The
ones that can overwrite text you wrote — `update_task`, `update_note`,
`update_project`, `set_checklist_item` — say so in their annotations, so hosts
treat them with more ceremony than a status change. Tools that create
something accept an idempotency key, so a host's retry never gives you the same
note or task twice.

Deliberate limits, so nothing here surprises you:

- **Nothing can be deleted.** There is no delete tool and there never will be
  one without a new architecture decision. `unlink_note` detaches a note; it
  does not remove it.
- **Any note's body can be rewritten, and nothing is lost when it is.** Every
  note is a markdown document ([ADR-0033](adr/0033-markdown-is-the-only-note-format.md)),
  and the body being replaced is kept as a version you can restore. Until
  2026-08-18 a note written in the app's rich editor answered
  `NOTE_NOT_MARKDOWN` — the assistant could rename a note it was not allowed
  to edit — because writing markdown onto a Delta would have left the body and
  the canonical source disagreeing.
- **Stopping a repeat stays in the app**: it deletes the future tasks of the
  series, and deleting is not something the connector does. `set_task_repeat`
  can start or change a repeat, never end it.
- **Archiving a project stays in the app**, because it cascades over that
  project's tasks and notes and deserves your confirmation.
- **File contents never leave through the connector** — no download links, no
  bytes, only metadata. That covers exports too: PDF and Word (`.docx`) files
  are made in the app on the device ([ADR-0048](adr/0048-docx-export-own-ooxml-writer.md)),
  and an assistant reads the note's markdown with `get_note` instead.
- Colours and icons are not settable by the AI: those are yours to pick.
- **Importing from Todoist or TickTick stays in the app and the API**
  ([ADR-0052](adr/0052-importing-from-other-apps.md)): an export file is a file,
  and the assistant already has `create_task` for one thing at a time.

## Self-hosting notes

- Set **`API_PUBLIC_URL`** to your instance's public origin (e.g.
  `https://api.your-instance.example`) — it is the OAuth issuer and the MCP
  resource identity, and `<API_PUBLIC_URL>/mcp` is your connector URL. In
  production it must be **HTTPS**.
- **`MCP_CIMD_ENABLED=false`** turns off client ID metadata documents and leaves
  dynamic registration as the only way in ([ADR-0047](adr/0047-oauth-client-id-metadata-documents.md)).
  The metadata fetch refuses private and loopback addresses, follows no
  redirects and gives up after 5 s or 5 KB.
- **`MCP_ENABLED=false`** withdraws the connector entirely (every `/mcp` and
  `/oauth/*` route answers 404). It is **independent of `AI_ENABLED`** — the
  MCP track spends no model money and stores no provider keys.
- **Continue with Google / Apple** appears on the sign-in page only when
  `SIGN_IN_GOOGLE_WEB_CLIENT_ID` / `SIGN_IN_APPLE_SERVICE_ID` are set (Apple also
  needs an https `API_PUBLIC_URL`). Register
  **`<API_PUBLIC_URL>/oauth/authorize/callback`** as an authorized redirect URI on
  the Google *Web application* client and as a Return URL on the Apple Services ID
  (whose primary App ID must be your iOS app's). Accounts are never created from
  that page ([ADR-0049](adr/0049-mcp-consent-social-sign-in-and-second-factor.md)).
- One connection maps to **one workspace**; connect twice to reach two.
- An extension installed on the server may add tools of its own and say which
  connections they are for. A connection is shown only the tools it is
  offered, and one it is not offered answers exactly like a name that does not
  exist.
- Disconnect from Claude/ChatGPT, or revoke server-side, and the tokens die
  (opaque, hashed, family-revoked on reuse).
- Data the AI reads flows into **your** Claude/ChatGPT account under *your*
  consumer terms with that provider.

## Verifying with the MCP Inspector

```bash
npx @modelcontextprotocol/inspector
```

Choose **Streamable HTTP**, enter `http://localhost:3000/mcp`, and Connect —
the Inspector registers itself (dynamic client registration), opens the
sign-in/consent page in your browser (loopback redirect), and then lets you
call every tool and read both resources. This is the standing conformance
check (ADR-0022 consequences).
