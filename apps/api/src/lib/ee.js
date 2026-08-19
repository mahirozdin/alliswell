import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

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
 * Failure policy: an ABSENT overlay is the CE build (info log, nothing else).
 * A PRESENT-but-broken overlay must not take the instance down with it — the
 * server boots as CE, logs loudly, and keeps the message on `app.ee.error`
 * for an operator-facing status surface to report.
 */
export async function loadEeOverlay(app) {
  const state = {
    enabled: app.config.ee.enabled,
    loaded: false,
    dir: null,
    error: null,
    // App-scoped extension registries — deliberately NOT module-level: two
    // apps built in one test process must not see each other's registrations.
    syncEntities: Object.create(null),
    mcpTools: [],
    permissions: [],
    corsOriginChecks: [],
    accountPurgeFilters: [],
  };
  app.decorate('ee', state);
  if (!state.enabled) return;

  const dir = resolveEeDir(app.config);
  state.dir = dir;
  const entry = path.join(dir, 'server', 'index.js');
  if (!existsSync(entry)) {
    app.log.info({ dir }, 'EE overlay not present — running as CE');
    return;
  }

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
    app.log.error({ err, dir }, 'EE overlay failed to load — continuing as CE');
  }
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
