import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fakeStorage } from '../helpers/fakestorage.js';
import {
  ServerFileRefused,
  nameForSniffed,
  sniffFileType,
  storeServerFile,
} from '../../src/lib/server-files.js';

// OPH-340 — a file the server holds (ADR-0011, amendment 2026-09-25). Every
// protection the client path has, applied to the bytes in hand; fake storage
// here, the real bucket in test/integration/server-files.test.js.

const PNG_TYPE = {
  mime: 'image/png',
  ext: 'png',
  match: (b) => b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47,
};
const JPEG_TYPE = {
  mime: 'image/jpeg',
  ext: 'jpg',
  match: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
};
const TYPES = [PNG_TYPE, JPEG_TYPE];
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const TEXT = Buffer.from('not a picture at all', 'utf8');

async function setup({ storage } = {}) {
  const store = storage ?? fakeStorage();
  const { app, tables } = await buildTestApp({ storage: store });
  const session = await registerUser(app, { email: `srv-${Math.random()}@example.com` });
  const workspaceId = session.workspace.id;
  const project = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${workspaceId}/projects`,
    headers: session.headers,
    payload: { name: 'Server files' },
  });
  expect(project.statusCode).toBe(201);
  return { app, tables, store, workspaceId, projectId: project.json().id };
}

const refusal = (promise) =>
  promise.then(
    () => {
      throw new Error('expected a refusal');
    },
    (err) => err,
  );

describe('OPH-340 — the pieces', () => {
  it('the type is what the first bytes say, among what the caller accepts', () => {
    expect(sniffFileType(JPEG, TYPES)).toBe(JPEG_TYPE);
    expect(sniffFileType(PNG, TYPES)).toBe(PNG_TYPE);
    expect(sniffFileType(TEXT, TYPES)).toBeNull();
    expect(sniffFileType(PNG, [JPEG_TYPE])).toBeNull();
    expect(sniffFileType(Buffer.alloc(2), TYPES)).toBeNull();
  });

  it('the stored name wears the extension of what the file IS', () => {
    expect(nameForSniffed('kanit.pdf', 'jpg')).toBe('kanit.jpg');
    expect(nameForSniffed('C:\\Users\\m\\foto', 'png')).toBe('foto.png');
    expect(nameForSniffed('', 'png', 'ek')).toBe('ek.png');
    expect(nameForSniffed(null, 'png')).toBe('file.png');
    expect(nameForSniffed('.pdf', 'jpg', 'ek')).toBe('ek.jpg');
  });
});

describe('OPH-340 — storeServerFile', () => {
  it('writes what the bytes ARE, under a name that says so — born ready, and announced as the server’s', async () => {
    const { app, store, workspaceId, projectId } = await setup();
    const heard = [];
    app.ee.entityWriteObservers.push(async (trx, change) => heard.push(change));

    const row = await storeServerFile(app, {
      workspaceId,
      targetType: 'project',
      targetId: projectId,
      body: JPEG,
      // The name and the extension LIE; neither gets a vote.
      filename: 'kanit.pdf',
      types: TYPES,
    });

    expect(row).toMatchObject({
      workspace_id: workspaceId,
      target_type: 'project',
      target_id: projectId,
      uploaded_by: null,
      name: 'kanit.jpg',
      mime: 'image/jpeg',
      status: 'ready',
    });
    expect(Number(row.size_bytes)).toBe(JPEG.length);
    expect(Number(row.revision)).toBeGreaterThan(0);
    expect(store.objects.get(row.storage_key)).toBe(JPEG.length);
    // Observers hear it like any upload — and can tell nobody uploaded it.
    expect(heard).toHaveLength(1);
    expect(heard[0]).toMatchObject({
      entityType: 'file',
      entityId: row.id,
      operation: 'create',
      origin: 'server',
    });
  });

  it('a type the caller does not accept is refused by CONTENT — whatever the name says — and nothing is written', async () => {
    const { app, store, workspaceId, projectId } = await setup();
    const err = await refusal(
      storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: TEXT,
        filename: 'photo.png',
        types: TYPES,
      }),
    );
    expect(err).toBeInstanceOf(ServerFileRefused);
    expect(err.code).toBe('FILE_TYPE_REFUSED');
    expect(store.objects.size).toBe(0);
    expect(await app.db('files').where({ workspace_id: workspaceId }).first()).toBeUndefined();
  });

  it('the ceiling is the MEASURED size', async () => {
    const { app, store, workspaceId, projectId } = await setup({
      storage: fakeStorage({ maxUploadBytes: 8 }),
    });
    const err = await refusal(
      storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: PNG, // ten bytes against a ceiling of eight
        types: TYPES,
      }),
    );
    expect(err.code).toBe('FILE_TOO_LARGE');
    expect(store.objects.size).toBe(0);
  });

  it('every upload guard is asked, with the measured size, and a no stops it before a byte moves', async () => {
    const { app, store, workspaceId, projectId } = await setup();
    const asked = [];
    app.ee.uploadGuards.push(async (ctx) => {
      asked.push(ctx);
      return { code: 'STORAGE_QUOTA_EXCEEDED', message: 'The team is out of room' };
    });
    const err = await refusal(
      storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: PNG,
        types: TYPES,
      }),
    );
    expect(err.code).toBe('STORAGE_QUOTA_EXCEEDED');
    expect(err.message).toBe('The team is out of room');
    expect(asked).toHaveLength(1);
    expect(asked[0]).toMatchObject({
      workspaceId,
      sizeBytes: PNG.length,
      phase: 'commit',
      origin: 'server',
      request: null,
    });
    expect(store.objects.size).toBe(0);
  });

  it('a core target must be a live row of this workspace; an unknown kind is no target', async () => {
    const { app, store, workspaceId } = await setup();
    const missing = await refusal(
      storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: '01ZZZZZZZZZZZZZZZZZZZZZZZZ',
        body: PNG,
        types: TYPES,
      }),
    );
    expect(missing.code).toBe('FILE_INVALID_TARGET');
    const unknown = await refusal(
      storeServerFile(app, {
        workspaceId,
        targetType: 'nonsense',
        targetId: workspaceId,
        body: PNG,
        types: TYPES,
      }),
    );
    expect(unknown.code).toBe('FILE_INVALID_TARGET');
    expect(store.objects.size).toBe(0);
  });

  it("if the caller's own rows fail, the object is queued for removal", async () => {
    // The row's rollback is MySQL's to prove — this fake has no rollback
    // (fakedb.js says so) — and test/integration/server-files.test.js does.
    // What this holds is the half that is ours: the bytes do not outlive it.
    const { app, store, workspaceId, projectId } = await setup();
    const err = await refusal(
      storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: PNG,
        types: TYPES,
        inTransaction: async () => {
          throw new Error('the caller’s row could not be written');
        },
      }),
    );
    expect(err.message).toBe('the caller’s row could not be written');
    await app.storageGc.idle();
    expect(store.removed).toHaveLength(1);
    expect(store.objects.size).toBe(0);
  });

  it('with storage off there is nothing to write to', async () => {
    const { app, workspaceId, projectId } = await setup({
      storage: fakeStorage({ enabled: false }),
    });
    const err = await refusal(
      storeServerFile(app, {
        workspaceId,
        targetType: 'project',
        targetId: projectId,
        body: PNG,
        types: TYPES,
      }),
    );
    expect(err.code).toBe('STORAGE_DISABLED');
  });
});

describe('OPH-340 — the plain build has no caller', () => {
  it('no core module imports the server-held file writer', () => {
    // CE behaviour does not change because nothing in CE reaches this door:
    // only an extension does. A core caller added later would have to delete
    // this test — which is the conversation it should start.
    const src = fileURLToPath(new URL('../../src', import.meta.url));
    const importers = [];
    const walk = (dir) => {
      for (const entry of readdirSync(dir)) {
        const full = path.join(dir, entry);
        if (statSync(full).isDirectory()) walk(full);
        else if (full.endsWith('.js') && !full.endsWith(path.join('lib', 'server-files.js'))) {
          if (/server-files\.js['"]/.test(readFileSync(full, 'utf8'))) importers.push(full);
        }
      }
    };
    walk(src);
    expect(importers).toEqual([]);
  });
});
