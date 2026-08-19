/**
 * Seam test overlay (EE-002) — NOT the real overlay. One fake register()
 * exercising every hook the seam offers, so the contract has teeth: a route,
 * a sync entity (pull + push), an MCP tool, a permission def, and an onSend
 * hook proving overlay hooks reach core routes.
 */
import { recordSyncWrite } from '../../../../src/db/sync.js';
import { newId } from '../../../../src/lib/ids.js';

export async function register(app, seam) {
  // Rows live per-register (= per app): two test apps must not share state.
  const probeRows = new Map();

  app.get(`${seam.apiPrefix}/__seam-probe`, async () => ({ ok: true, source: 'overlay' }));

  app.post(
    `${seam.apiPrefix}/__seam-probe/:workspaceId`,
    { onRequest: [app.authenticate] },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const id = newId();
      await app.db.transaction(async (trx) => {
        await recordSyncWrite(trx, {
          workspaceId,
          entityType: 'seam_probe',
          entityId: id,
          operation: 'create',
          changedFields: ['title'],
        });
      });
      probeRows.set(id, { id, workspace_id: workspaceId, title: 'probe', deleted_at: null });
      return { id };
    },
  );

  seam.registerSyncEntity('seam_probe', {
    loader: async (ids) => ({
      rows: ids.map((id) => probeRows.get(id)).filter(Boolean),
      serialize: (row) => ({ id: row.id, title: row.title }),
    }),
    entity: {
      table: 'seam_probes',
      fields: { title: { col: 'title', ok: (v) => typeof v === 'string' && v.length > 0 } },
      requiredOnCreate: ['title'],
      workspaceOf: (row) => row.workspace_id,
      insertRow: (ctx, mutation, rowPatch) => ({
        id: mutation.entityId,
        workspace_id: ctx.workspaceId,
        ...rowPatch,
      }),
    },
  });

  seam.registerMcpTool({
    name: 'seam_probe_tool',
    title: 'Seam probe',
    description: 'Test-only tool proving overlay MCP registration.',
    annotations: { readOnlyHint: true },
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
    // Handlers return the bare payload — /mcp wraps it into content +
    // structuredContent itself (toolResult), same as every built-in tool.
    async handler() {
      return { ok: true };
    },
  });

  seam.registerPermissions([
    { id: 'probe.view', label: 'seam.probe.view', description: 'test-only' },
  ]);

  // EE-013: origin checks are consulted at request time, after the static list.
  seam.registerCorsOriginCheck((origin) => origin === 'https://seam-allowed.example');

  // EE-016: spare 'seam-keep*' workspaces from an account purge by re-homing
  // them to the designated holder (the contract: sparing = re-homing).
  seam.registerAccountPurgeFilter(async (trx, { workspaceIds }) => {
    if (workspaceIds.length === 0) return [];
    const holder = await trx('users').where({ email: 'seam-holder@example.com' }).first();
    if (!holder) return [];
    const rows = await trx('workspaces')
      .whereIn('id', workspaceIds)
      .where('slug', 'like', 'seam-keep%')
      .select('id');
    const ids = rows.map((r) => r.id);
    if (ids.length > 0) {
      await trx('workspaces').whereIn('id', ids).update({ owner_id: holder.id });
    }
    return ids;
  });

  // The ordering guarantee made visible: this hook is added before ANY core
  // route registers, so every response carries the marker.
  app.addHook('onSend', async (request, reply, payload) => {
    reply.header('x-seam-probe', '1');
    return payload;
  });
}
