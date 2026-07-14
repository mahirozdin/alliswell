import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';

let app;
let tables;
let owner;

const CLIENT = newId();

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
});

afterEach(async () => {
  await app.close();
});

const push = (payload, headers = owner.headers) =>
  app.inject({ method: 'POST', url: '/api/v1/sync/push', headers, payload });

const batch = (mutations, overrides = {}) => ({
  clientId: CLIENT,
  workspaceId: owner.workspace.id,
  baseRevision: 0,
  mutations,
  ...overrides,
});

const api = (method, url, payload) => app.inject({ method, url, headers: owner.headers, payload });

const mut = (overrides) => ({
  clientMutationId: newId(),
  operation: 'create',
  ...overrides,
});

describe('POST /sync/push — apply (OPH-052)', () => {
  it('applies an offline capture batch: project, task with tags, checklist, note', async () => {
    const tag = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tags`, { name: 'seyahat' })
    ).json(); // rev 1

    const projectId = newId();
    const taskId = newId();
    const itemId = newId();
    const noteId = newId();

    const res = await push(
      batch(
        [
          mut({
            entityType: 'project',
            entityId: projectId,
            patch: { name: 'Kamp', colorRgb: '#00AA55' },
          }),
          mut({
            entityType: 'task',
            entityId: taskId,
            patch: {
              title: 'Çadır kur',
              projectId,
              tagIds: [tag.id],
              isUrgent: true,
              remindAt: '2030-06-01T09:00:00.000Z',
            },
          }),
          mut({
            entityType: 'checklist_item',
            entityId: itemId,
            patch: { taskId, title: 'kazıklar' },
          }),
          mut({
            entityType: 'note',
            entityId: noteId,
            patch: { title: 'Kamp notu', contentDelta: [{ insert: 'liste\n' }] },
          }),
        ],
        { baseRevision: 1 },
      ),
    );

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.results.map((r) => r.status)).toEqual(['applied', 'applied', 'applied', 'applied']);
    expect(body.results.every((r) => r.replayed === false)).toBe(true);
    // project=2, task=3, reminder=4 (urgent remind → reminder row), item=5, note=6
    expect(body.toRevision).toBe(6);

    const task = (await api('GET', `/api/v1/tasks/${taskId}`)).json();
    expect(task).toMatchObject({
      title: 'Çadır kur',
      projectId,
      isUrgent: true,
      requiresAcknowledgement: true, // urgent default (REST parity)
      tagIds: [tag.id],
    });
    expect(task.checklist).toEqual([
      expect.objectContaining({ id: itemId, title: 'kazıklar', isDone: false }),
    ]);
    expect(tables.reminders).toEqual([
      expect.objectContaining({ task_id: taskId, status: 'scheduled', alarm_level: 'urgent' }),
    ]);
    const note = (await api('GET', `/api/v1/notes/${noteId}`)).json();
    expect(note.plainText).toBe('liste');
    // every mutation left an idempotency record
    expect(tables.client_mutations).toHaveLength(4);
  });

  it('creates and renames tags with slug rules; duplicates are rejected', async () => {
    const tagId = newId();
    const first = await push(
      batch([mut({ entityType: 'tag', entityId: tagId, patch: { name: 'Çok Önemli' } })]),
    );
    expect(first.json().results[0].status).toBe('applied');
    expect(tables.tags[0]).toMatchObject({ id: tagId, name: 'Çok Önemli', slug: 'cok-onemli' });

    const dup = await push(
      batch([mut({ entityType: 'tag', entityId: newId(), patch: { name: 'çok önemli' } })]),
    );
    expect(dup.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'TAG_SLUG_TAKEN',
    });

    const rename = await push(
      batch([
        mut({
          entityType: 'tag',
          entityId: tagId,
          operation: 'update',
          patch: { name: 'Ertelendi' },
          localUpdatedAt: new Date(Date.now() + 3600000).toISOString(),
        }),
      ]),
    );
    expect(rename.json().results[0].status).toBe('applied');
    expect(tables.tags[0]).toMatchObject({ name: 'Ertelendi', slug: 'ertelendi' });
  });

  it('deletes: soft delete + subtree cascade for tasks, idempotent re-delete, role guard for projects', async () => {
    const parent = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, { title: 'üst' })
    ).json();
    const child = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
        title: 'alt',
        parentTaskId: parent.id,
      })
    ).json();
    const project = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/projects`, { name: 'P' })
    ).json();

    const del = await push(
      batch([mut({ entityType: 'task', entityId: parent.id, operation: 'delete' })]),
    );
    expect(del.json().results[0].status).toBe('applied');
    expect(tables.tasks.find((t) => t.id === parent.id).deleted_at).not.toBeNull();
    expect(tables.tasks.find((t) => t.id === child.id).deleted_at).not.toBeNull();

    // Re-deleting (a new mutation id) is an idempotent no-op.
    const again = await push(
      batch([mut({ entityType: 'task', entityId: parent.id, operation: 'delete' })]),
    );
    expect(again.json().results[0]).toMatchObject({ status: 'applied', replayed: false });

    // Plain members cannot delete projects (REST parity).
    const member = await registerUser(app, { email: 'member@example.com' });
    addMember(tables, { workspaceId: owner.workspace.id, user: member.user });
    const memberDelete = await push(
      {
        ...batch([mut({ entityType: 'project', entityId: project.id, operation: 'delete' })]),
        clientId: newId(),
      },
      member.headers,
    );
    expect(memberDelete.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'AUTH_WORKSPACE_FORBIDDEN',
    });
  });

  it('rejects invalid entities, unknown fields, bad values and broken patches per mutation', async () => {
    const task = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, { title: 'sağlam' })
    ).json();

    const res = await push(
      batch([
        mut({ entityType: 'wormhole', entityId: newId(), patch: { spin: 1 } }),
        mut({ entityType: 'task', entityId: newId(), operation: 'update', patch: { title: 'x' } }),
        mut({ entityType: 'task', entityId: task.id, patch: { title: 'zaten var' } }),
        mut({ entityType: 'task', entityId: newId(), patch: { title: 'ok', warp: 9 } }),
        mut({ entityType: 'task', entityId: newId(), patch: { title: '' } }),
        mut({ entityType: 'task', entityId: newId() }), // patch yok
        mut({
          entityType: 'task',
          entityId: newId(),
          patch: { title: 'tz', timezone: 'Mars/Olympus' },
        }),
        mut({
          entityType: 'task',
          entityId: newId(),
          patch: { title: 'proje?', projectId: newId() },
        }),
        mut({
          entityType: 'note',
          entityId: newId(),
          patch: { title: 'n', contentDelta: [{ nope: 1 }] },
        }),
      ]),
    );

    expect(res.json().results.map((r) => [r.status, r.errorCode])).toEqual([
      ['rejected', 'SYNC_UNSUPPORTED_ENTITY'],
      ['rejected', 'SYNC_ENTITY_NOT_FOUND'],
      ['rejected', 'SYNC_ENTITY_EXISTS'],
      ['rejected', 'SYNC_UNKNOWN_FIELD'],
      ['rejected', 'SYNC_INVALID_VALUE'],
      ['rejected', 'SYNC_INVALID_PATCH'],
      ['rejected', 'TASK_INVALID_TIMEZONE'],
      ['rejected', 'TASK_INVALID_PROJECT'],
      ['rejected', 'NOTE_INVALID_DELTA'],
    ]);
    // Rejected mutations still land in the idempotency log…
    expect(tables.client_mutations).toHaveLength(9);
    // …but never in the sync log.
    expect(tables.sync_revisions.filter((r) => r.entity_type === 'wormhole')).toHaveLength(0);
  });

  it('guards workspace boundaries: foreign workspaces 403, foreign entities invisible', async () => {
    const outsider = await registerUser(app, { email: 'outsider@example.com' });
    const foreignTask = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${outsider.workspace.id}/tasks`,
      headers: outsider.headers,
      payload: { title: 'yabancı' },
    });

    const forbidden = await push(
      batch([mut({ entityType: 'task', entityId: newId(), patch: { title: 'x' } })], {
        workspaceId: outsider.workspace.id,
      }),
    );
    expect(forbidden.statusCode).toBe(403);

    const crossWs = await push(
      batch([
        mut({
          entityType: 'task',
          entityId: foreignTask.json().id,
          operation: 'update',
          patch: { title: 'çalıntı' },
        }),
      ]),
    );
    expect(crossWs.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_ENTITY_NOT_FOUND',
    });
    expect(tables.tasks.find((t) => t.id === foreignTask.json().id).title).toBe('yabancı');
  });

  it('keeps archived tasks immutable except the lone unarchive', async () => {
    const task = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, { title: 'eski' })
    ).json();
    await api('PATCH', `/api/v1/tasks/${task.id}`, { status: 'archived' });

    const blocked = await push(
      batch([
        mut({
          entityType: 'task',
          entityId: task.id,
          operation: 'update',
          patch: { title: 'yeni' },
        }),
      ]),
    );
    expect(blocked.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'TASK_ARCHIVED',
    });

    const unarchive = await push(
      batch([
        mut({
          entityType: 'task',
          entityId: task.id,
          operation: 'update',
          patch: { status: 'open' },
          localUpdatedAt: new Date(Date.now() + 3600000).toISOString(),
        }),
      ]),
    );
    expect(unarchive.json().results[0].status).toBe('applied');
    expect(tables.tasks.find((t) => t.id === task.id).status).toBe('open');
  });
});

describe('POST /sync/push — field-level LWW (OPH-052)', () => {
  let task;

  beforeEach(async () => {
    task = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, { title: 'orijinal' })
    ).json(); // rev 1
  });

  it('applies cleanly when no foreign writer touched the fields', async () => {
    const res = await push(
      batch(
        [
          mut({
            entityType: 'task',
            entityId: task.id,
            operation: 'update',
            patch: { title: 'düzenlendi' },
            localUpdatedAt: '2020-01-01T00:00:00.000Z', // old clock is fine — no overlap
          }),
        ],
        { baseRevision: 1 },
      ),
    );
    expect(res.json().results[0].status).toBe('applied');
    expect(tables.tasks.find((t) => t.id === task.id).title).toBe('düzenlendi');
  });

  it('discards only the stale overlapping fields and reports them', async () => {
    await api('PATCH', `/api/v1/tasks/${task.id}`, { title: 'sunucuda yeni' }); // foreign, rev 2

    const res = await push(
      batch(
        [
          mut({
            entityType: 'task',
            entityId: task.id,
            operation: 'update',
            patch: { title: 'bayat başlık', priority: 'high' },
            localUpdatedAt: '2020-01-01T00:00:00.000Z', // older than the server edit
          }),
        ],
        { baseRevision: 1 },
      ),
    );

    const result = res.json().results[0];
    expect(result).toMatchObject({ status: 'applied', discardedFields: ['title'] });
    const row = tables.tasks.find((t) => t.id === task.id);
    expect(row.title).toBe('sunucuda yeni'); // server won
    expect(row.priority).toBe('high'); // client's non-conflicting field landed
  });

  it('conflicts when every field is stale, wins when the client clock is newer', async () => {
    await api('PATCH', `/api/v1/tasks/${task.id}`, { title: 'sunucuda yeni' }); // rev 2

    const stale = await push(
      batch(
        [
          mut({
            entityType: 'task',
            entityId: task.id,
            operation: 'update',
            patch: { title: 'bayat' },
            localUpdatedAt: '2020-01-01T00:00:00.000Z',
          }),
        ],
        { baseRevision: 1 },
      ),
    );
    expect(stale.json().results[0]).toMatchObject({
      status: 'conflict',
      errorCode: 'SYNC_STALE_MUTATION',
    });
    expect(tables.tasks.find((t) => t.id === task.id).title).toBe('sunucuda yeni');

    const newer = await push(
      batch(
        [
          mut({
            entityType: 'task',
            entityId: task.id,
            operation: 'update',
            patch: { title: 'istemci daha taze' },
            localUpdatedAt: new Date(Date.now() + 3600000).toISOString(),
          }),
        ],
        { baseRevision: 1 },
      ),
    );
    expect(newer.json().results[0].status).toBe('applied');
    expect(tables.tasks.find((t) => t.id === task.id).title).toBe('istemci daha taze');
  });

  it('does not conflict with the client’s own earlier pushes (attribution)', async () => {
    const created = newId();
    const first = await push(
      batch([mut({ entityType: 'task', entityId: created, patch: { title: 'offline v1' } })]),
    );
    expect(first.json().results[0].status).toBe('applied');

    // Same client pushes again WITHOUT pulling — baseRevision is still 1, and
    // the create it just made sits above it. Own writes must not read as
    // foreign conflicts.
    const second = await push(
      batch(
        [
          mut({
            entityType: 'task',
            entityId: created,
            operation: 'update',
            patch: { title: 'offline v2' },
            localUpdatedAt: '2020-01-01T00:00:00.000Z',
          }),
        ],
        { baseRevision: 1 },
      ),
    );
    expect(second.json().results[0].status).toBe('applied');
    expect(tables.tasks.find((t) => t.id === created).title).toBe('offline v2');
  });

  it('locks note CONTENT at document level: no timestamp ever merges it', async () => {
    const note = (
      await api('POST', `/api/v1/workspaces/${owner.workspace.id}/notes`, {
        title: 'ortak not',
        contentDelta: [{ insert: 'v1\n' }],
      })
    ).json(); // rev 2 (task create was rev 1)
    await api('PATCH', `/api/v1/notes/${note.id}`, { contentDelta: [{ insert: 'sunucu v2\n' }] }); // rev 3

    const contentPush = await push(
      batch(
        [
          mut({
            entityType: 'note',
            entityId: note.id,
            operation: 'update',
            patch: { contentDelta: [{ insert: 'istemci v2\n' }] },
            localUpdatedAt: new Date(Date.now() + 3600000).toISOString(), // even a future clock
          }),
        ],
        { baseRevision: 2 },
      ),
    );
    expect(contentPush.json().results[0]).toMatchObject({
      status: 'conflict',
      errorCode: 'NOTE_CONTENT_CONFLICT',
    });
    expect(tables.notes.find((n) => n.id === note.id).content_delta).toBe(
      JSON.stringify([{ insert: 'sunucu v2\n' }]),
    );

    // Metadata on the same note still LWW-merges normally.
    const pinPush = await push(
      batch(
        [
          mut({
            entityType: 'note',
            entityId: note.id,
            operation: 'update',
            patch: { isPinned: true },
            localUpdatedAt: '2020-01-01T00:00:00.000Z',
          }),
        ],
        { baseRevision: 2 },
      ),
    );
    expect(pinPush.json().results[0].status).toBe('applied');
    expect(tables.notes.find((n) => n.id === note.id).is_pinned).toBe(true);
  });

  it('maintains completed_at and the reminder lifecycle through pushed status changes', async () => {
    await api('PATCH', `/api/v1/tasks/${task.id}`, { remindAt: '2030-06-01T09:00:00.000Z' }); // rev 2+3

    const complete = await push(
      batch(
        [
          mut({
            entityType: 'task',
            entityId: task.id,
            operation: 'update',
            patch: { status: 'completed' },
            localUpdatedAt: new Date(Date.now() + 3600000).toISOString(),
          }),
        ],
        { baseRevision: 3 },
      ),
    );
    expect(complete.json().results[0].status).toBe('applied');
    const row = tables.tasks.find((t) => t.id === task.id);
    expect(row.status).toBe('completed');
    expect(row.completed_at).toBeInstanceOf(Date);
    expect(tables.reminders[0].status).toBe('completed'); // silenced with the task
  });
});

describe('POST /sync/push — idempotent replay (OPH-053)', () => {
  it('returns recorded results without re-applying, including partial replays', async () => {
    const taskId = newId();
    const createMutation = mut({
      entityType: 'task',
      entityId: taskId,
      patch: { title: 'bir kez' },
    });

    const first = await push(batch([createMutation]));
    const firstResult = first.json().results[0];
    expect(firstResult).toMatchObject({ status: 'applied', replayed: false });

    // Exact replay: same statuses and revisions, replayed flag on, no new writes.
    const replay = await push(batch([createMutation]));
    expect(replay.json().results[0]).toMatchObject({
      status: 'applied',
      revision: firstResult.revision,
      replayed: true,
    });
    expect(replay.json().toRevision).toBe(first.json().toRevision);
    expect(tables.tasks.filter((t) => t.id === taskId)).toHaveLength(1);
    expect(tables.sync_revisions.filter((r) => r.entity_id === taskId)).toHaveLength(1);
    expect(tables.client_mutations).toHaveLength(1);

    // Partial replay: the old mutation replays, the new one applies.
    const updateMutation = mut({
      entityType: 'task',
      entityId: taskId,
      operation: 'update',
      patch: { priority: 'urgent' },
      localUpdatedAt: new Date(Date.now() + 3600000).toISOString(),
    });
    const mixed = await push(batch([createMutation, updateMutation]));
    expect(mixed.json().results.map((r) => [r.status, r.replayed])).toEqual([
      ['applied', true],
      ['applied', false],
    ]);
    expect(tables.tasks.find((t) => t.id === taskId).priority).toBe('urgent');

    // Rejected outcomes replay too — the entity is never re-touched.
    const badMutation = mut({ entityType: 'wormhole', entityId: newId(), patch: { x: 1 } });
    await push(batch([badMutation]));
    const badReplay = await push(batch([badMutation]));
    expect(badReplay.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_UNSUPPORTED_ENTITY',
      replayed: true,
    });
  });

  it('scopes idempotency to the client id', async () => {
    const sharedMutationId = newId();
    const t1 = newId();
    const t2 = newId();

    const clientA = await push(
      batch([
        {
          clientMutationId: sharedMutationId,
          entityType: 'task',
          entityId: t1,
          operation: 'create',
          patch: { title: 'A' },
        },
      ]),
    );
    // A different device may reuse a mutation id — it is a fresh mutation.
    const clientB = await push(
      batch(
        [
          {
            clientMutationId: sharedMutationId,
            entityType: 'task',
            entityId: t2,
            operation: 'create',
            patch: { title: 'B' },
          },
        ],
        { clientId: newId() },
      ),
    );

    expect(clientA.json().results[0]).toMatchObject({ status: 'applied', replayed: false });
    expect(clientB.json().results[0]).toMatchObject({ status: 'applied', replayed: false });
    expect(tables.tasks).toHaveLength(2);
  });
});
