# ADR-0047 — The MCP authorization server accepts client ID metadata documents beside registration

- **Status:** Accepted
- **Date:** 2026-10-12
- **Related task:** OPH-364 (MCP discoverability and CIMD); extends [ADR-0022](0022-remote-mcp-server.md)

## Context

ADR-0022 built the connector's OAuth 2.1 server with RFC 7591 dynamic client
registration (DCR) as the only way a client gets a `client_id`. Claude's custom
connector dialog now defaults to **"Use Claude's published identity"**: the
client names itself by an https URL and expects the authorization server to read
its metadata from there (draft-ietf-oauth-client-id-metadata-document, "CIMD").
Against a DCR-only server that default fails with "Couldn't register with
AllisWell's sign-in service", and the only cure was knowing to pick "Register
automatically" instead. A Claude Team owner hit exactly this on 2026-10-12.

Reading a URL a stranger chose is a server-side request on their behalf, so the
fetch is the security-relevant part of the decision.

## Decision

1. **A `client_id` that is an https URL is a metadata client** when it has a DNS
   host on the default port, a path, and no credentials, query, fragment or dot
   segments, and parses back to exactly itself (`isClientMetadataUrl`). Anything
   else is looked up as a registered ULID, as before; the two cannot collide.
2. **The document is fetched only by `GET /oauth/authorize`**, never by the
   token endpoint. The fetch is fenced: every resolved address is checked
   against the private, loopback, link-local, CGNAT, documentation and multicast
   ranges *in the socket's `lookup` hook* (so DNS rebinding between check and
   connect is refused), IP-literal hosts are refused outright, redirects are not
   followed, and it has 5 s and 5 KB.
3. **The document must name itself** (`client_id` equal to the URL), carry no
   secret, use `token_endpoint_auth_method: none` (private_key_jwt is not built),
   allow the authorization-code grant, and list 1–10 redirect URIs that pass the
   same rule DCR applies (https, or http on loopback).
4. **A URL maps to an ordinary `oauth_clients` row** (new nullable, unique
   `metadata_url` and `metadata_expires_at` columns), so codes, tokens, mutations
   and the action log keep their 26-character foreign keys and cannot tell the
   two kinds of client apart. The cached name and redirect URIs are trusted for
   the document's `Cache-Control: max-age`, clamped to 5 min – 24 h (1 h when
   absent). An expired document that cannot be re-fetched or no longer validates
   is an error page — never a stale fallback, because its owner may have
   withdrawn a redirect URI on purpose.
5. **The consent page shows the publishing host beside the name**
   ("Claude (claude.ai)"): a metadata client chooses its own name in a document
   anyone can publish, and the host is the part it cannot fake.
6. Discovery advertises `client_id_metadata_document_supported: true`.
   `MCP_CIMD_ENABLED=false` withdraws all of it and leaves a DCR-only server.

## Alternatives considered

- **Document "pick Register automatically" and stop.** Free, but every new user
  meets the failing default first, and the error text points at AllisWell.
- **A fetch library with SSRF filtering.** A new dependency category for one
  GET; Node's `https.get` with a `lookup` hook does the same check at the only
  moment it matters.
- **A separate table for metadata clients.** Every token table would need a
  second, nullable foreign key; mapping the URL to a normal row keeps one.
- **Serving a stale document when the fetch fails.** Better availability, but
  it would keep honouring a redirect URI its owner removed.

## Consequences

- Claude's default connector option works; DCR clients (ChatGPT, the MCP
  Inspector, existing Claude connections) are untouched.
- `/oauth/authorize` can now make one outbound HTTPS request per expired client;
  it is rate-limited like the rest of the auth surface.
- Metadata clients are public clients only. Supporting `private_key_jwt` (a
  `jwks_uri` in the document) would be a follow-up decision.
