import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { coreMigrationsDir, migrationNamesIn } from '../db/migration-dirs.js';
import { MCP_TOOLS } from './mcp/tools.js';

// The overlay's default home: a sibling checkout at the repo root. Resolved
// from this file so the dev tree, the Docker image and a test fixture all go
// through the same code path — only EE_DIR moves it.
const DEFAULT_DIR = fileURLToPath(new URL('../../../../ee', import.meta.url));

/** The overlay's resolved home, or null when the seam is off. Shared with the
 * knex config so runtime and CLI agree on where EE migrations live. */
export function resolveEeDir(config) {
  if (!config.ee.enabled) return null;
  return config.ee.dir || DEFAULT_DIR;
}

/**
 * Enterprise overlay loader (EE-002). Imports `<dir>/server/index.js` and
 * calls its `register(app, seam)` BEFORE any core route registers — that
 * ordering IS the seam's contract: hooks the overlay adds apply to core
 * routes, sync entities land before /sync snapshots its registries, MCP tools
 * land before /mcp compiles its schemas.
 *
 * Failure policy (OPH-343, ADR-0041 — it replaced "a broken overlay boots as
 * CE"): the question is not whether the extension is here but whether the
 * DATA it governs is. Its rules — permission resolvers, sync guards — leave
 * with it, and core's answer without them is membership: every member of a
 * workspace the extension restricted would be served with the plain build's
 * wider rights. So:
 *
 *   • disabled                          → CE, and nothing here runs at all;
 *   • loaded                            → open;
 *   • present but failed to load        → LOCKED (whatever EE_REQUIRED says —
 *                                         a half-registered overlay is the
 *                                         worst state to serve from);
 *   • absent, EE_REQUIRED=true          → LOCKED;
 *   • absent, EE_REQUIRED=false         → CE (the operator accepted it);
 *   • absent, EE_REQUIRED unset         → the migration ledger decides: a
 *                                         recorded migration this build does
 *                                         not have means the extension wrote
 *                                         data here → LOCKED; a clean ledger
 *                                         is the plain build → CE.
 *
 * Locked = every request but /health answers 503 EXTENSION_UNAVAILABLE and
 * readiness reports why. A ledger that cannot be read yet (the database is
 * still coming up) locks too, and is asked again on the next request: failing
 * closed costs a few seconds of 503 on a server that could not serve anyway.
 * The plain build — disabled, or absent with a clean ledger — installs no hook
 * and answers byte for byte as before (tested).
 */
export async function loadEeOverlay(app) {
  const state = {
    enabled: app.config.ee.enabled,
    loaded: false,
    dir: null,
    error: null,
    // OPH-343: null = open, else { code } — see the failure policy above.
    lock: null,
    // App-scoped extension registries — deliberately NOT module-level: two
    // apps built in one test process must not see each other's registrations.
    syncEntities: Object.create(null),
    mcpTools: [],
    permissions: [],
    permissionResolvers: [],
    aiConnectionResolvers: [],
    syncMutationGuards: [],
    entityWriteObservers: [],
    corsOriginChecks: [],
    accountPurgeFilters: [],
    statusDecorators: [],
    signInRequirements: [],
    passwordRequirements: [],
    signInFailureObservers: [],
    credentialVerifiers: [],
    // OPH-325 (ADR-0040): attachable target kinds an extension registers, keyed
    // by the `files.target_type` value. Empty here IS the plain build: the
    // four built-in kinds live in `routes/files.js` and nothing else is
    // accepted.
    attachmentTargets: Object.create(null),
    // OPH-331: guards an extension may put in front of an upload. Empty here
    // IS the plain build — CE has one ceiling (`maxUploadBytes`, per file) and
    // that is the whole policy.
    //
    // `attachmentTargets` answers "may this file exist HERE"; this answers
    // "may this file exist AT ALL, given how much already does". They are
    // different questions and the second one CE does not ask.
    uploadGuards: [],
  };
  app.decorate('ee', state);
  if (!state.enabled) return;

  const dir = resolveEeDir(app.config);
  state.dir = dir;
  const entry = path.join(dir, 'server', 'index.js');
  if (existsSync(entry)) {
    const seam = buildSeam(state);
    try {
      const mod = await import(pathToFileURL(entry).href);
      if (typeof mod.register !== 'function') {
        throw new Error('overlay entry must export register(app, seam)');
      }
      await mod.register(app, seam);
      state.loaded = true;
      app.log.info({ dir }, 'EE overlay loaded');
    } catch (err) {
      state.error = err?.message ?? String(err);
      app.log.error({ err, dir }, 'EE overlay failed to load — the server locks (ADR-0041)');
    }
  } else {
    app.log.info({ dir }, 'EE overlay not present');
  }

  const gate = lockGate(app, state);
  state.readiness = gate.readiness;
  await gate.verdict();
  // Installed only when the answer is or may become "locked": the plain build
  // (absent, clean ledger) carries no hook, so it answers exactly as before.
  if (gate.mayLock()) app.addHook('onRequest', gate.onRequest);
}

/** OPH-343 — the lock's three questions, asked once and remembered. */
function lockGate(app, state) {
  let settled = false;
  let inflight = null;

  async function decide() {
    if (state.loaded) return null;
    if (state.error) return 'EXTENSION_LOAD_FAILED';
    const required = app.config.ee.required;
    if (required === true) return 'EXTENSION_REQUIRED';
    if (required === false) return null;
    const unknown = await unknownLedgerEntries(app.db);
    return unknown.length > 0 ? 'EXTENSION_MISSING' : null;
  }

  async function verdict() {
    if (settled) return state.lock;
    inflight ??= decide()
      .then((code) => {
        state.lock = code ? { code } : null;
        settled = true;
        if (code)
          app.log.error({ code }, 'extension unavailable — the server is locked (ADR-0041)');
      })
      .catch((err) => {
        // Unreadable is not clean: stay locked and ask again next time.
        state.lock = { code: 'EXTENSION_UNVERIFIED' };
        app.log.error({ err }, 'migration ledger unreadable — locked until it can be read');
      })
      .finally(() => {
        inflight = null;
      });
    await inflight;
    return state.lock;
  }

  return {
    verdict,
    mayLock: () => !settled || state.lock !== null,
    async onRequest(request) {
      if (request.url === '/health' || request.url.startsWith('/health/')) return;
      const lock = await verdict();
      if (!lock) return;
      const err = app.httpErrors.serviceUnavailable(
        'This server is locked until its extension is available again.',
      );
      err.code = 'EXTENSION_UNAVAILABLE';
      throw err;
    },
    /** A readiness component, or null when there is nothing to report (plain build). */
    async readiness() {
      const lock = await verdict();
      if (lock) return { status: 'down', error: lock.code };
      return state.loaded ? { status: 'up' } : null;
    },
  };
}

/**
 * Ledger rows this build has no file for. With the overlay absent, "known" is
 * core's directory alone — so every row the extension's migrations wrote is
 * unknown, and one is enough.
 */
async function unknownLedgerEntries(db) {
  let rows;
  try {
    rows = await db('knex_migrations').select('name');
  } catch (err) {
    // A database never migrated has written nothing for anyone.
    if (err?.code === 'ER_NO_SUCH_TABLE') return [];
    throw err;
  }
  const known = new Set(migrationNamesIn(coreMigrationsDir()));
  return rows.map((row) => row.name).filter((name) => !known.has(name));
}

/**
 * The dynamic half of the CORS `origin` option (EE-013): reproduces the
 * static value's semantics (true = allow, list = exact match) and then
 * consults extension-registered checks. Requests without an Origin header
 * answer true — the plugin sets no CORS headers for them either way.
 */
export function corsOriginAllowed(app, origin) {
  if (!origin) return true;
  const configured = app.config.corsOrigin;
  if (configured === true) return true;
  const list = Array.isArray(configured) ? configured : [configured];
  if (list.includes(origin)) return true;
  return app.ee.corsOriginChecks.some((check) => check(origin) === true);
}

/** The kinds `routes/files.js` owns; an extension may not shadow one. */
const CORE_ATTACHMENT_TARGETS = new Set(['project', 'task', 'note', 'workspace']);

function buildSeam(state) {
  const builtinTools = new Set(MCP_TOOLS.map((tool) => tool.name));
  return Object.freeze({
    // Routes need no dedicated hook — the overlay holds `app` and registers
    // Fastify plugins itself. The constant keeps overlay prefixes honest.
    apiPrefix: '/api/v1',

    /**
     * Sync registry extension. `loader` is a SNAPSHOT_LOADERS value (function
     * or `{ userScoped, load }`), `entity` an ENTITIES value; either may be
     * omitted — pull-only entities exist (`file` is one). /sync merges these
     * after its built-in literals; built-in types are not overridable there.
     */
    registerSyncEntity(type, { loader, entity } = {}) {
      if (typeof type !== 'string' || type.length === 0) {
        throw new Error('registerSyncEntity: a non-empty type is required');
      }
      if (!loader && !entity) {
        throw new Error(`registerSyncEntity(${type}): loader or entity required`);
      }
      if (state.syncEntities[type]) {
        throw new Error(`registerSyncEntity(${type}): duplicate registration`);
      }
      state.syncEntities[type] = { loader, entity };
    },

    /**
     * OPH-325 — a new kind of thing files can hang on (ADR-0040).
     *
     * `type` is the stored `files.target_type`; `check` answers the one
     * question core asks about every upload — "is this a real target of THIS
     * workspace, for THIS caller?" — and answers it with the extension's own
     * rules, because core cannot know them. Returning false produces the same
     * `FILE_INVALID_TARGET` a bad core target produces: a caller probing ids
     * must not be able to tell "no such thing" from "not yours".
     *
     * The check runs AFTER `requireWorkspaceMember`, so membership is already
     * settled; what it adds is existence and whatever verb the extension
     * considers the right to contribute one.
     */
    registerAttachmentTarget(type, check) {
      if (typeof type !== 'string' || !/^[a-z][a-z0-9_]{0,31}$/.test(type)) {
        throw new Error('registerAttachmentTarget: type must be a short snake_case name');
      }
      if (typeof check !== 'function') {
        throw new Error(`registerAttachmentTarget(${type}): a check function is required`);
      }
      if (CORE_ATTACHMENT_TARGETS.has(type) || state.attachmentTargets[type]) {
        throw new Error(`registerAttachmentTarget(${type}): name already taken`);
      }
      state.attachmentTargets[type] = { check };
    },

    /** MCP tool: the exact MCP_TOOLS entry shape; names are one namespace. */
    registerMcpTool(tool) {
      if (!tool?.name || typeof tool.handler !== 'function' || !tool.inputSchema) {
        throw new Error('registerMcpTool: { name, inputSchema, handler } required');
      }
      if (builtinTools.has(tool.name) || state.mcpTools.some((t) => t.name === tool.name)) {
        throw new Error(`registerMcpTool(${tool.name}): name already taken`);
      }
      state.mcpTools.push(tool);
    },

    /**
     * Extra CORS origin check: `(origin: string) => boolean`. Consulted at
     * REQUEST time (the CORS plugin registers before the overlay loads), only
     * for origins the static allowlist did not already admit. Never receives
     * an absent origin.
     */
    registerCorsOriginCheck(check) {
      if (typeof check !== 'function') {
        throw new Error('registerCorsOriginCheck: a function is required');
      }
      state.corsOriginChecks.push(check);
    },

    /**
     * Account-purge filter: `async (trx, { userId, workspaceIds }) => ids to
     * SPARE`. Consulted inside the purge transaction before owned workspaces
     * are deleted; a filter that spares a workspace must also re-home it
     * (update its ownership) in the same trx, or the user-row delete will
     * hit the owner FK. Core without filters behaves exactly as before.
     */
    registerAccountPurgeFilter(filter) {
      if (typeof filter !== 'function') {
        throw new Error('registerAccountPurgeFilter: a function is required');
      }
      state.accountPurgeFilters.push(filter);
    },

    /**
     * Capability-discovery contributor: `async (request, status) => partial`.
     *
     * `/ee/status` answers what THIS INSTANCE is licensed for, which is all a
     * single-tenant install can be asked. An extension that serves several
     * customers from one instance knows something core cannot: which of them
     * is asking. Registered decorators are consulted per request and their
     * result is merged over the instance answer, so the endpoint keeps one
     * shape while gaining a narrower truth where one exists.
     *
     * A decorator that throws is ignored (logged): capability discovery is
     * the endpoint clients cache their whole surface from, and it degrades to
     * the instance answer rather than failing.
     */
    registerStatusDecorator(decorator) {
      if (typeof decorator !== 'function') {
        throw new Error('registerStatusDecorator: a function is required');
      }
      state.statusDecorators.push(decorator);
    },

    /**
     * Permission resolver: `async (request, workspaceId) => Set<string> | null`.
     *
     * Consulted by `app.requirePermission` AFTER membership has been
     * established, and only then — the answer to "who may be here" is core's
     * and does not move. `null` means the resolver has no opinion about this
     * workspace (it is not one it governs), which is how a personal
     * workspace behaves identically with and without an extension.
     *
     * With no resolver registered, `requirePermission` IS
     * `requireWorkspaceMember`, byte for byte. That equivalence is the whole
     * compatibility promise of this member and it has its own test.
     */
    registerPermissionResolver(resolver) {
      if (typeof resolver !== 'function') {
        throw new Error('registerPermissionResolver: a function is required');
      }
      state.permissionResolvers.push(resolver);
    },

    /**
     * AI connection resolver:
     * `async (request, { workspaceId, connectionId }) => credential | null`.
     *
     * Consulted by `app.ai.resolveConnection` BEFORE the caller's own stored
     * connections are looked at, on every resolution — but what it may DO
     * depends on `connectionId`:
     *
     *   • **nothing pinned** — a returned credential WINS. This is the default
     *     choice, and the one an extension can have a better answer to (a
     *     credential the caller may use but does not own).
     *   • **a connection pinned** — a returned credential is IGNORED. Pinning
     *     names a specific `ai_connections` row by id, an explicit choice out
     *     of the user's own list, and core keeps that promise.
     *
     * A resolver that THROWS refuses the request either way, and that is why
     * the pinned path consults the chain at all: "this caller may not use
     * their own key here" is an authorisation answer, not a resolution, and a
     * refusal that could be sidestepped by naming a connection would not be
     * one.
     *
     * `null` means this resolver has no opinion, which is how a request
     * behaves identically with and without an extension. With none registered,
     * `resolveConnection` IS the function it has always been, byte for byte —
     * that equivalence is this member's whole compatibility promise and it has
     * its own test.
     *
     * The credential is a DESCRIPTION, not a resolution:
     *
     *     { provider, apiKey?, baseUrl?, models?: { chat?, fast? } }
     *
     * Core builds the resolution around it, which is deliberate on two counts.
     * The shape callers depend on stays owned by one file, so a field added
     * here later cannot break an extension that never knew about it. And there
     * is no way to supply a connection id: `ai_usage_events.connection_id` is a
     * foreign key into `ai_connections`, so an id from anywhere else would be a
     * constraint violation at the meter. Not accepting one makes that
     * impossible to write rather than merely wrong to write.
     *
     * A refusal is never swallowed — unlike a status decorator, which is
     * ignored when it throws. The difference is what the answer is for:
     * capability discovery degrades to a narrower truth, but a credential
     * lookup that failed must not fall through to a different payer's key.
     */
    registerAiConnectionResolver(resolver) {
      if (typeof resolver !== 'function') {
        throw new Error('registerAiConnectionResolver: a function is required');
      }
      state.aiConnectionResolvers.push(resolver);
    },

    /**
     * Upload guard (OPH-331): `async (ctx) => { code, message } | null`,
     * where `ctx` is `{ app, db, request, workspaceId, sizeBytes, phase }`.
     *
     * Consulted TWICE for an ordinary upload, and the pair is the point:
     *
     *   phase `declare`  the client has said how big the file will be and no
     *                    bytes have moved. A refusal here costs nothing, so
     *                    it is worth making early.
     *   phase `commit`   the object is in storage and its size was verified
     *                    by HeadObject. A refusal here is the one that cannot
     *                    be lied to — the declare phase trusts a number the
     *                    caller chose.
     *
     * That split is EE-117's, which learned it on transcription minutes: "an
     * uploader can claim a duration and a claim is not a measurement." The
     * same shape applies to bytes, and for the same reason: without the second
     * check, one honest-looking declaration per request is enough to walk a
     * whole tenant past any ceiling by opening many uploads at once.
     *
     * Returning a code refuses the upload; returning null allows it. Guards
     * run in registration order and the first refusal wins. An extension that
     * registers none — or a build with no extension — behaves exactly as
     * before, which is why CE needs no branch for this.
     */
    registerUploadGuard(guard) {
      if (typeof guard !== 'function') {
        throw new Error('registerUploadGuard: a function is required');
      }
      state.uploadGuards.push(guard);
    },

    /**
     * Sync push guard: `async (ctx, mutation) => errorCode | null`.
     *
     * Consulted for every push mutation AFTER the entity, operation and patch
     * have been validated and BEFORE anything is written, so a refusal costs
     * no transaction. A returned code becomes an ordinary `rejected` outcome
     * — the same shape the protocol has always had — which is what keeps an
     * older client from looping: it settles a rejection the way it settles
     * any other answer, and the result is recorded per clientMutationId, so a
     * replay returns the recorded refusal instead of re-deciding it.
     *
     * `ctx.request` is the originating request, for guards that need to ask
     * `app.requirePermission`.
     */
    registerSyncMutationGuard(guard) {
      if (typeof guard !== 'function') {
        throw new Error('registerSyncMutationGuard: a function is required');
      }
      state.syncMutationGuards.push(guard);
    },

    /**
     * Entity write observers: `async (trx, change) => void`, called INSIDE the
     * write transaction, AFTER the row has changed.
     *
     * `change` is `{ workspaceId, entityType, entityId, operation, actorId,
     * before, after }` — `before`/`after` are whatever the write path chose to
     * describe, so an observer can say what changed rather than only that
     * something did. Core registers none and reads none: this exists so an
     * extension can derive a record (an activity trail, a webhook, a search
     * index) from a change without every write path having to know about it.
     *
     * IN the transaction is the point, not a detail. A post-commit hook would
     * let the derived record and the change it describes disagree whenever the
     * process died in between — and `entity:changed` (OPH-072) already covers
     * the post-commit case for anything that only needs to be told later.
     *
     * A throwing observer rolls the write back. That is deliberate: a change
     * nobody could account for should not be committed.
     */
    registerEntityWriteObserver(observer) {
      if (typeof observer !== 'function') {
        throw new Error('registerEntityWriteObserver: a function is required');
      }
      state.entityWriteObservers.push(observer);
    },

    /**
     * Sign-in requirements: `async (ctx) => null | { code, message }`.
     *
     * Consulted by `/auth/login` AFTER the password and any second factor have
     * been checked, and only then — whether the credentials are right is
     * core's question and does not move. `ctx` is
     * `{ db, user, request, factors: { totpEnrolled, totpVerified } }`, and a
     * check that returns null has no opinion about this sign-in, which is how
     * an install with no extension behaves exactly as before.
     *
     * The order matters and is the whole design: a requirement runs on a
     * sign-in that has ALREADY proven the password. It can therefore say
     * "correct password, and still no" — which is what a policy is — without
     * ever being able to say "wrong password, but yes".
     *
     * A throwing check refuses the sign-in. That is deliberate and the
     * opposite of `registerStatusDecorator`'s degrade-to-core: a capability
     * list that loses an entry is a smaller answer, but a policy that fails
     * open is not a policy.
     */
    registerSignInRequirement(check) {
      if (typeof check !== 'function') {
        throw new Error('registerSignInRequirement: a function is required');
      }
      state.signInRequirements.push(check);
    },

    /**
     * Failed sign-in observers: `async ({ db, email, user, request }) => void`.
     *
     * Called when `/auth/login` refuses a password — including for an address
     * with no account, where `user` is null. Core keeps no per-account failure
     * state of its own (its brute-force answer is the auth rate limit, which
     * is per IP), so this exists for an extension that must: an account
     * lockout is a policy, and a policy needs to see the failures.
     *
     * Observers CANNOT change the outcome and their errors are swallowed: the
     * request has already been refused, and a counter that fails must not turn
     * a 401 into a 500 — that difference is itself an oracle.
     */
    registerSignInFailureObserver(observer) {
      if (typeof observer !== 'function') {
        throw new Error('registerSignInFailureObserver: a function is required');
      }
      state.signInFailureObservers.push(observer);
    },

    /**
     * Password requirements: `async (ctx) => null | { code, message }`.
     *
     * Consulted when somebody SETS a password, after the right to set it has
     * been established (the current password proven, or an invitation
     * redeemed). `ctx` is `{ db, user, request, password }`.
     *
     * Core enforces a floor of its own (8 characters, in the route schema) and
     * nothing else: what makes a good password is a policy, policies differ per
     * install, and a product that hard-codes one is a product that argues with
     * its customer's security team. This is where that argument gets settled by
     * whoever is running the thing.
     */
    registerPasswordRequirement(check) {
      if (typeof check !== 'function') {
        throw new Error('registerPasswordRequirement: a function is required');
      }
      state.passwordRequirements.push(check);
    },

    /**
     * Credential verifiers: `async (ctx) => null | { ok: false } | { ok: true, userId }`.
     *
     * The other three auth hooks REFUSE or OBSERVE; this one ANSWERS. It is
     * the only place an extension can say "this credential is right" about a
     * credential core cannot check itself — a directory bind, a federated
     * assertion — and it exists because none of the other three can: a
     * requirement runs after core has already proven the password, and an
     * account whose password lives somewhere else has no password here to
     * prove (`users.password_hash` is null for it, which core refuses).
     *
     * ── THREE ANSWERS, NOT TWO ───────────────────────────────────────────
     *
     *   • `null` (or undefined) — NOT MINE. Core carries on exactly as it
     *     would with no extension loaded: one argon2 verify against the real
     *     or the dummy hash, and the same refusal. This is the answer that
     *     keeps a CE install and an install whose verifiers all decline
     *     byte-identical, so it is the default for anything a verifier does
     *     not recognise.
     *   • `{ ok: false }` — MINE, AND NO. Core refuses with its ordinary
     *     invalid-credentials error and runs the failure observers, so a
     *     lockout counter sees a directory refusal the same as a local one.
     *     There is deliberately no way to return a custom message here: a
     *     refusal worded per address is an account-existence oracle, and the
     *     one thing this seam must not do is make the login endpoint chatty.
     *   • `{ ok: true, userId }` — MINE, AND YES. Core then re-reads that
     *     user from its OWN tables and refuses if the row is missing or
     *     deleted. A verifier names who signed in; it cannot conjure an
     *     account, because the account in MySQL is the source of truth (the
     *     same stance `lib/oauth-identity.js` takes for Google and Apple).
     *
     * ── WHERE IT RUNS, AND WHY THAT IS BEFORE ────────────────────────────
     *
     * Verifiers are consulted BEFORE core checks the password, for EVERY
     * address presented — including addresses with no account here. Both
     * halves matter. Running first means one authority decides one identity;
     * running after core's refusal would make this a hook that OVERTURNS a
     * no, which is a far more dangerous thing to hold. Running for every
     * address means the mere fact that a verifier was consulted says nothing
     * about whether an account exists.
     *
     * The FIRST verifier to claim the address wins and the rest are not
     * consulted. Which source owns which identity is a policy, and policies
     * belong to the extension that has the customer's configuration — core
     * only guarantees the order it asks in is the order they registered in.
     *
     * A THROWING verifier refuses the sign-in, like a sign-in requirement and
     * for the same reason: a credential source that fails open is not a
     * credential source. It surfaces as a server error rather than a 401 on
     * purpose — an unreachable directory is not a wrong password, and an
     * operator watching status codes should be able to tell them apart.
     */
    registerCredentialVerifier(verify) {
      if (typeof verify !== 'function') {
        throw new Error('registerCredentialVerifier: a function is required');
      }
      state.credentialVerifiers.push(verify);
    },

    /** Collection point only — enforcing permissions is the overlay's business. */
    registerPermissions(defs) {
      if (!Array.isArray(defs)) throw new Error('registerPermissions: an array is required');
      for (const def of defs) {
        if (!def?.id) throw new Error('registerPermissions: every def needs an id');
        state.permissions.push(def);
      }
    },
  });
}

/**
 * Tell the registered observers that a row changed (see
 * `registerEntityWriteObserver`). A no-op with no extension loaded, which is
 * every plain build.
 *
 * @param {import('fastify').FastifyInstance} app
 * @param {import('knex').Knex.Transaction} trx the WRITE's transaction
 * @param {{workspaceId: string, entityType: string, entityId: string,
 *          operation: 'create'|'update'|'delete', actorId?: string|null,
 *          before?: object|null, after?: object|null}} change
 */
export async function notifyEntityWrite(app, trx, change) {
  const observers = app.ee?.entityWriteObservers;
  if (!observers || observers.length === 0) return;
  for (const observer of observers) await observer(trx, change);
}
