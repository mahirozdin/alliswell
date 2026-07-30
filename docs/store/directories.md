# MCP directory submissions (OPH-227)

Draft application copy for listing the **hosted** AllisWell MCP server in the
public connector directories. These are **operator-submitted** — review is a
third party's call and does not gate the v0.9.0 tag. Self-hosters don't need any
of this: their instance is its own connector URL (see [docs/MCP.md](../MCP.md)).

Connector endpoint (hosted): `https://api.alliswell.space/mcp`
Discovery: `https://api.alliswell.space/.well-known/oauth-protected-resource`

## Anthropic — Claude Connectors Directory

- **Name:** AllisWell
- **Category:** Productivity / Task management
- **One-liner:** Your tasks, projects and notes in Claude — read your day and
  add tasks, with your confirmation.
- **Description (≤ ~500 chars):** AllisWell is an open-source, self-hostable
  productivity hub (tasks, projects, notes, files, calendar sync). Connect it to
  Claude to search your workspace, list what's due today or overdue, read a task,
  note or project, and create or complete tasks. It is **read-first**: there is
  **no delete tool**, and every connection runs behind AllisWell's own OAuth 2.1
  with per-request workspace checks. Bring your own instance or use the hosted
  service.
- **Auth:** OAuth 2.1 (PKCE, dynamic client registration, refresh-token
  rotation). Scopes: `mcp:read`, `mcp:write`.
- **Tools:** `search`, `list_tasks`, `get_task`, `get_note`, `get_project`,
  `create_task`, `complete_task`. No deletion, ever.
- **Privacy/security:** [SECURITY.md](../../SECURITY.md) "AI surfaces",
  [PRIVACY.md](../PRIVACY.md) "AI features", [docs/MCP.md](../MCP.md).
- **Support:** support@alliswell.space · **Homepage:** https://alliswell.space

## OpenAI — ChatGPT apps / connectors

Same product summary as above. Emphasise for ChatGPT's review:

- The server speaks **Streamable HTTP** (protocol `2025-06-18`, also accepts
  `2025-03-26`), stateless, POST-only JSON-RPC, `Origin` validated.
- Write tools (`create_task`, `complete_task`) are annotated
  `readOnlyHint:false, destructiveHint:false`; an ambiguous project yields a
  candidate list rather than creating in the wrong place.
- No user content is used for training by AllisWell; the connector transmits
  only what the assistant requests, over the authorized connection.

## Submission checklist (operator)

- [ ] Hosted `/mcp` reachable over HTTPS with valid discovery documents.
- [ ] A demo workspace with sample data for reviewers.
- [ ] Live end-to-end run from Claude (add connector → OAuth → a search + a
      confirmed `create_task`) captured for the review notes.
- [ ] Logos/screenshots per each directory's asset spec.
