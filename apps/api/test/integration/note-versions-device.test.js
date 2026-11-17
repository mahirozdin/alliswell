import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

/**
 * Version history and the conflict diff name the writing device and the exact
 * moment (OPH-494): the device's name comes from the caller's own device
 * registry, joined on the version's client id.
 *
 * Shares its harness with note-sync-conflict.test.js (OPH-486/487).

 */
const enabled = process.env.INTEGRATION === '1';
const emailPrefix = `noteversiondevice-${Date.now()}`;

describe.runIf(enabled)('note versions: device and time (OPH-494)', () => {
  let app;
  let owner;

  const wsRev = async () =>
    Number(
      (await app.db('workspaces').where({ id: owner.workspace.id }).first('revision')).revision,
    );
  const note = (id) => app.db('notes').where({ id }).first();
  const push = async (clientId, mutations) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId,
        workspaceId: owner.workspace.id,
        baseRevision: await wsRev(),
        mutations,
      },
    });
    expect(res.statusCode).toBe(200);
    return res.json().results;
  };

  const createM = (noteId, body = '', title = 'Yeni not') => ({
    clientMutationId: newId(),
    entityType: 'note',
    entityId: noteId,
    operation: 'create',
    localUpdatedAt: new Date().toISOString(),
    patch: { title, contentMarkdown: body, contentFormat: 'markdown' },
  });
  const updateM = (noteId, body, baseRevision, cmid = newId(), extra = {}) => ({
    clientMutationId: cmid,
    entityType: 'note',
    entityId: noteId,
    operation: 'update',
    localUpdatedAt: new Date().toISOString(),
    ...(baseRevision == null ? {} : { baseRevision }),
    patch: { title: 'Yeni not', contentMarkdown: body, contentFormat: 'markdown', ...extra },
  });
  const create = async (clientId, body) => {
    const noteId = newId();
    const [c] = await push(clientId, [createM(noteId, body)]);
    expect(c.status).toBe('applied');
    return { noteId, rev: c.revision };
  };
  const update = async (clientId, noteId, base, body, cmid) =>
    (await push(clientId, [updateM(noteId, body, base, cmid)]))[0];

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({ ...process.env, NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-6' },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    owner = {
      user: body.user,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  describe('which device, and when', () => {
    const register = (deviceId, deviceName, platform = 'macos') =>
      app.inject({
        method: 'PUT',
        url: `/api/v1/notification-devices/${deviceId}`,
        headers: owner.headers,
        payload: { platform, deviceName },
      });

    it('history names the writing device from the registry, and when it last wrote', async () => {
      const mac = newId();
      const gone = newId();
      expect((await register(mac, 'Mahir MacBook')).statusCode).toBeLessThan(300);
      const { noteId, rev } = await create(mac, 'Bir');
      await update(mac, noteId, rev, 'Bir\nİki');
      const web = newId();
      const w = await update(web, noteId, (await note(noteId)).revision, 'Bir\nİki\nÜç');
      expect(w.status).toBe('applied');
      const g = await update(gone, noteId, w.revision, 'Bir\nİki\nÜç\nDört');
      expect(g.status).toBe('applied');

      const res = await app.inject({
        method: 'GET',
        url: `/api/v1/notes/${noteId}/versions`,
        headers: owner.headers,
      });
      expect(res.statusCode).toBe(200);
      const items = res.json().items;
      const byClient = Object.fromEntries(items.map((v) => [v.clientId, v]));
      expect(byClient[mac]).toMatchObject({ deviceName: 'Mahir MacBook', devicePlatform: 'macos' });
      // Not in the registry: no name, and the app says so instead of guessing.
      expect(byClient[gone]).toMatchObject({ deviceName: null, devicePlatform: null });
      for (const v of items) {
        expect(Date.parse(v.updatedAt)).toBeGreaterThanOrEqual(Date.parse(v.createdAt));
      }

      const detail = await app.inject({
        method: 'GET',
        url: `/api/v1/notes/${noteId}/versions/${byClient[mac].id}`,
        headers: owner.headers,
      });
      expect(detail.json()).toMatchObject({ deviceName: 'Mahir MacBook' });
    });

    it('a diff names the current side: its last write and its device', async () => {
      const mac = newId();
      const pc = newId();
      expect((await register(mac, 'Ofis Mac')).statusCode).toBeLessThan(300);
      const { noteId, rev: r0 } = await create(pc, 'A\nM\nN');
      const theirs = await update(mac, noteId, r0, 'A\nM\nX');
      expect(theirs.status).toBe('applied');
      const mine = await update(pc, noteId, r0, 'A\nM\nY');
      expect(mine.status).toBe('conflict');
      const res = await app.inject({
        method: 'GET',
        url: `/api/v1/notes/${noteId}/versions/${mine.conflictVersionId}/diff`,
        headers: owner.headers,
      });
      expect(res.statusCode).toBe(200);
      const row = await note(noteId);
      expect(res.json().current).toEqual({
        updatedAt: new Date(row.updated_at).toISOString(),
        origin: 'edit',
        clientId: mac,
        deviceName: 'Ofis Mac',
        devicePlatform: 'macos',
      });
    });
  });
});
