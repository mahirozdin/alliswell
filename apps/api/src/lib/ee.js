import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { MCP_TOOLS } from './mcp/tools.js';

// The overlay's default home: a sibling checkout at the repo root. Resolved
// from this file so the dev tree, the Docker image and a test fixture all go
// through the same code path — only EE_DIR moves it.
const DEFAULT_DIR = fileURLToPath(new URL('../../../../ee', import.meta.url));

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
  };
  app.decorate('ee', state);
  if (!state.enabled) return;

  const dir = app.config.ee.dir || DEFAULT_DIR;
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
