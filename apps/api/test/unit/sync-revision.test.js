import { describe, it, expect } from 'vitest';
import { fakeDb } from '../helpers/fakedb.js';
import { recordSyncWrite, withRevision } from '../../src/db/sync.js';

const WS = '01WORKSPACE0000000000000AA';

function seedWorkspace(tables, id = WS) {
  tables.workspaces.push({
    id,
    owner_id: '01OWNER00000000000000000AA',
    name: 'Ws',
    slug: `ws-${id.slice(-4).toLowerCase()}`,
    revision: 0,
    created_at: new Date(),
    updated_at: new Date(),
  });
}

describe('db/sync withRevision (OPH-050)', () => {
  it('bumps the workspace revision monotonically and logs every write', async () => {
    const { db, tables } = fakeDb();
    seedWorkspace(tables);

    const revisions = [];
    await db.transaction(async (trx) => {
      revisions.push(await withRevision(trx, WS, 'task', 'T1'.padEnd(26, '0'), 'create'));
      revisions.push(
        await withRevision(trx, WS, 'task', 'T1'.padEnd(26, '0'), 'update', ['title', 'due_at']),
      );
      revisions.push(await withRevision(trx, WS, 'note', 'N1'.padEnd(26, '0'), 'delete'));
    });

    expect(revisions).toEqual([1, 2, 3]);
    expect(tables.workspaces[0].revision).toBe(3);
    expect(tables.sync_revisions).toHaveLength(3);
    expect(tables.sync_revisions[1]).toMatchObject({
      workspace_id: WS,
      revision: 2,
      entity_type: 'task',
      operation: 'update',
      changed_fields: JSON.stringify(['title', 'due_at']),
    });
    expect(tables.sync_revisions[2]).toMatchObject({
      entity_type: 'note',
      operation: 'delete',
      changed_fields: null,
    });
  });

  it('is the same log as recordSyncWrite and scopes counters per workspace', async () => {
    const { db, tables } = fakeDb();
    const otherWs = '01WORKSPACE0000000000000BB';
    seedWorkspace(tables);
    seedWorkspace(tables, otherWs);

    await db.transaction(async (trx) => {
      await withRevision(trx, WS, 'project', 'P1'.padEnd(26, '0'), 'create');
      await recordSyncWrite(trx, {
        workspaceId: WS,
        entityType: 'project',
        entityId: 'P1'.padEnd(26, '0'),
        operation: 'update',
        changedFields: ['name'],
      });
      await withRevision(trx, otherWs, 'project', 'P2'.padEnd(26, '0'), 'create');
    });

    // Each workspace has its own monotonic counter (BLUEPRINT §6.2).
    expect(tables.workspaces.find((w) => w.id === WS).revision).toBe(2);
    expect(tables.workspaces.find((w) => w.id === otherWs).revision).toBe(1);
    const perWs = tables.sync_revisions.map((r) => [r.workspace_id, r.revision]);
    expect(perWs).toEqual([
      [WS, 1],
      [WS, 2],
      [otherWs, 1],
    ]);
  });

  it('refuses a duplicate (workspace, revision) pair like the real unique index', async () => {
    const { db, tables } = fakeDb();
    seedWorkspace(tables);
    await db.transaction(async (trx) => {
      await withRevision(trx, WS, 'task', 'T1'.padEnd(26, '0'), 'create');
    });

    // Simulate a colliding writer that did not go through the row-lock bump.
    await expect(
      db('sync_revisions').insert({
        id: 'X'.padEnd(26, '0'),
        workspace_id: WS,
        revision: 1,
        entity_type: 'task',
        entity_id: 'T2'.padEnd(26, '0'),
        operation: 'create',
        changed_fields: null,
      }),
    ).rejects.toMatchObject({ code: 'ER_DUP_ENTRY' });
  });
});
