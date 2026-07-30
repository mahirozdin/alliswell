# Add AllisWell to Claude or ChatGPT

AllisWell ships a **remote MCP server** — a connector you add to your *own*
Claude or ChatGPT account. The AI then reads and updates your AllisWell
workspace using **your** subscription; AllisWell spends nothing on model calls.
This is Track A of the AI design ([AI.md](AI.md); [ADR-0022](adr/0022-remote-mcp-server.md)).

Every self-hosted instance is its own connector at `https://<your-instance>/mcp`.

## Add it to Claude

1. In Claude (Free ×1 / Pro / Max) open **Settings → Connectors → Add custom connector**.
2. Paste your instance's MCP URL: `https://api.your-instance.example/mcp`.
3. Claude opens AllisWell's sign-in page. Log in with your AllisWell account,
   pick a workspace, and approve the scopes.
4. The connector's tools now appear in Claude.

## Add it to ChatGPT

1. In ChatGPT (Plus / Pro) enable **Settings → Connectors → Advanced → Developer mode**.
2. **Add a connector** and paste the same `https://…/mcp` URL.
3. Sign in and approve, exactly as above.

## What the AI can do

Seven tools, no delete tool — by design (loosening it needs a new ADR):

| Tool | What it does |
| --- | --- |
| `search` | Find tasks, notes and projects (Turkish-aware folding) |
| `list_tasks` | Filtered list, plus `today` / `overdue` in your timezone |
| `get_task` / `get_note` / `get_project` | Full detail of one item |
| `create_task` | Create a task; an unknown/ambiguous project creates nothing and asks |
| `complete_task` | Mark a task done (idempotent) |

Plus two read-only resources: **today** and **overdue** task views.

Write tools are annotated so Claude/ChatGPT show you an approval prompt before
they run, and every AI-made change is recorded in AllisWell's action log.

## Self-hosting notes

- Set **`API_PUBLIC_URL`** to your instance's public origin (e.g.
  `https://api.your-instance.example`) — it is the OAuth issuer and the MCP
  resource identity. In production it must be **HTTPS**.
- **`MCP_ENABLED=false`** withdraws the connector entirely (every `/mcp` and
  `/oauth/*` route answers 404). It is **independent of `AI_ENABLED`** — the
  MCP track spends no model money and stores no provider keys.
- One connection maps to **one workspace**; connect twice to reach two.
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
