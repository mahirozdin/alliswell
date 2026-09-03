# ADR-0035 — The API reference is generated from the routes, not written beside them

- **Status:** Accepted
- **Date:** 2026-09-04
- **Related task:** OPH-294 (Epic 27; gate for OPH-295 and OPH-297)
- **Related:** [ADR-0032](0032-api-keys.md) (the keys this documents),
  [ADR-0022](0022-remote-mcp-server.md) (the surface it deliberately excludes),
  [issue #3](https://github.com/mahirozdin/alliswell/issues/3)

## Context

Issue #3 asked for API keys *and* a REST API. The keys shipped in v1.7.0 with
`docs/API.md` beside them — 380 lines, hand-written, honest about being a guide
rather than a reference. Two weeks later the owner minted a key and reported:
*"there is no documentation — which endpoints are there, what do they take,
what do they return?"*

The complaint was right, and reading the file against the code showed it was
worse than incomplete. It had **drifted invisibly**:

- It described a `409 NOTE_CONTENT_CONFLICT` body carrying `conflictVersionId`.
  The route does set that property (`routes/notes.js`), but Fastify's error
  serializer emits exactly `{statusCode, code, error, message}` and drops the
  rest. **The server has never sent that field.** The one test covering the
  case asserts the `code` and then goes to the database for the version — so
  nothing caught it.
- It listed **three** families of route closed to API keys. There are four: the
  self-credential routes (password, two-factor, sessions) were closed when
  OPH-283 and OPH-284 landed, and nobody updated the prose. That is 9 endpoints
  a reader would have been told they could reach.
- Its endpoint reference covered ~55 of 78 key-reachable routes, with no
  request bodies, no response shapes, no field types, no enums, and no
  parameter meanings anywhere in the file.
- Its error table had 9 entries. The codebase has roughly 90.

None of that is carelessness. It is the arithmetic of maintaining a reference
for 113 operations by hand, next to code that changes weekly.

## Decision

**One source of truth: the Ajv schemas Fastify already validates against.**

1. **`docs/openapi.json` is generated** by `scripts/api/openapi.mjs`, which
   builds the real app with stubbed infrastructure (the pattern `buildApp`
   already documents for tests), collects every route through an `onRoute`
   hook, and serializes it with `@fastify/swagger`. Nothing connects and
   nothing listens; the routes only have to *register*.
2. **`@fastify/swagger` is a devDependency and is never registered in the
   served app.** It is installed by the generator through a new `instrument`
   seam on `buildApp` — the only moment an `onRoute` hook can still see every
   route. Production carries no new plugin and no new request-path work.
3. **The reference section of `docs/API.md` is generated** from that spec,
   between markers. The narrative sections — get a key, find your workspace,
   the recipes, key lifecycle — stay hand-written, because they are the part a
   person reads once and prose is the right form for them.
4. **The Postman collection is generated from the same spec**, so the three
   artefacts cannot disagree with each other.
5. **Three CI gates** (`check:openapi`, `check:apidocs`, `check:postman`)
   regenerate and fail on any difference. Without them this is just a
   different way of writing the same rotting file.
6. **Auth is read from the routes' own hooks**, not from a list in the
   generator — because a list is one more thing to forget, and forgetting it
   is exactly how "three closed doors" survived two releases. The one
   exception is `/ai/*`, which closes its whole scope with a plugin-level
   hook that `onRoute` cannot see; that rule is stated in the generator **and
   checked against its source file**, so it fails loudly rather than silently
   downgrading if the hook ever moves.

## Alternatives considered

- **Keep writing it by hand, more carefully.** This is what we were doing. The
  three defects above were all introduced by careful people; the failure is
  structural, not attentional.
- **A docs framework — Redoc, Scalar, Docusaurus, Stoplight.** All of them
  render an OpenAPI spec beautifully and all of them are a second web
  framework, which AGENTS §1.3 forbids without an ADR — and the ADR would have
  to argue that the existing `marked`-based static-page pipeline is
  insufficient. It is not: it already renders `/privacy`, `/support` and
  `/enterprise`, it needs no runtime JavaScript, and a docs page that works
  with scripts disabled is worth more than an expandable schema widget.
- **Register `@fastify/swagger` in the app and serve `/docs` from the API.**
  Tempting: the spec could never be stale because it would be computed per
  boot. But it puts a marketing surface on the API host, splits the docs away
  from the site's design, and adds a plugin to production for a file that
  changes only when the code does — which is exactly when CI runs.
- **Hand-write the Postman collection.** A third copy of the route table. The
  first two both drifted.

## Consequences

**Easier.** A new route is documented by existing. Adding a field to a schema
updates the reference, the examples and the collection in one command. The
auth column stops being a claim and becomes a reading of the code — which is
how the 25 closed endpoints and the 78 key-reachable ones were confirmed
against an independent audit, and matched exactly.

**Harder.** The reference reads like a reference, not like prose: Fastify
schemas carry no per-field descriptions today, so the "Notes" column is
constraints rather than explanation. Adding `description` to the schemas would
improve the docs and the validation errors at once, and is the obvious next
step. Response schemas that are deliberately loose (`task-series` validates
rules semantically, not structurally) document as loose, which is honest but
thin.

**Follow-ups this creates.**
- Error codes are still hand-listed in §5 of `docs/API.md`. They are inline
  string literals scattered across the source, some inside ternaries, so no
  honest scan can collect them — a central `error-codes.js` registry would let
  the table be generated and gated like the rest. Recorded here rather than
  half-done.
- The EE overlay's 153 routes are excluded (`check:no-ee`); if the enterprise
  docs ever want the same treatment it needs its own generator in that repo.
