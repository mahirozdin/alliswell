import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { storageTestEnv, ensureBucket } from '../helpers/minio.js';

// Account deletion over REAL infrastructure. The point of this test is the part
// a fake database cannot prove: that the schema's CASCADEs really erase a whole
// workspace when its owner goes (App Store 5.1.1(v) / Google Play require the
// data to be GONE, not deactivated), and that the file's bytes leave storage
// with it.
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('integration: account deletion (MySQL + MinIO)', () => {
  let app;
  let headers;
  let userId;
  let workspaceId;

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...storageTestEnv(), NODE_ENV: 'test' });
    await ensureBucket(config.storage);
    app = await buildApp({ config });

    const reg = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `delete-me-${Date.now()}@example.com`, password: 'integration-pass-1' },
    });
    const body = reg.json();
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
    userId = body.user.id;
    workspaceId = body.workspace.id;
  });

  afterAll(async () => {
    if (app) await app.close();
  });

  it('schedules, can be cancelled, then purges the account and its bytes', async () => {
    // Content that must not survive: a project, a task, and a real uploaded file.
    const project = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/projects`,
      headers,
      payload: { name: 'Doomed' },
    });
    const projectId = project.json().id;

    const task = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/tasks`,
      headers,
      payload: { title: 'Doomed task', projectId },
    });
    const taskId = task.json().id;

    const content = 'bytes that must not outlive the account';
    const init = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${workspaceId}/files`,
      headers,
      payload: {
        targetType: 'task',
        targetId: taskId,
        name: 'evidence.txt',
        sizeBytes: Buffer.byteLength(content),
      },
    });
    const { file, upload } = init.json();
    await fetch(upload.url, { method: 'PUT', headers: upload.headers, body: content });
    await app.inject({ method: 'POST', url: `/api/v1/files/${file.id}/complete`, headers });
    const storageKey = `ws/${workspaceId}/${file.id}`;
    expect(await app.storage.head(storageKey)).not.toBeNull();

    // ── 1. Requesting deletion schedules it; the account keeps working ───────
    const requested = await app.inject({ method: 'DELETE', url: '/api/v1/me', headers });
    expect(requested.statusCode).toBe(200);
    expect(requested.json().graceDays).toBe(app.config.accountDeletionGraceDays);
    const deadline = new Date(requested.json().deletionScheduledAt);
    expect(deadline.getTime()).toBeGreaterThan(Date.now());

    const during = await app.inject({ method: 'GET', url: '/api/v1/me', headers });
    expect(during.statusCode).toBe(200); // still usable — that is the undo window
    expect(during.json().user.deletionScheduledAt).toBe(deadline.toISOString());

    // Asking twice must not extend the countdown.
    const again = await app.inject({ method: 'DELETE', url: '/api/v1/me', headers });
    expect(again.json().deletionScheduledAt).toBe(deadline.toISOString());

    // A sweep before the deadline must leave everything alone.
    expect(await app.accountGc.sweep(new Date())).toBe(0);
    expect(await app.db('users').where({ id: userId }).first()).toBeTruthy();

    // ── 2. Cancelling clears it ──────────────────────────────────────────────
    const cancelled = await app.inject({
      method: 'POST',
      url: '/api/v1/me/deletion/cancel',
      headers,
    });
    expect(cancelled.statusCode).toBe(200);
    expect(cancelled.json().deletionScheduledAt).toBeNull();
    const after = await app.inject({ method: 'GET', url: '/api/v1/me', headers });
    expect(after.json().user.deletionScheduledAt).toBeNull();

    // ── 3. Re-request, then sweep past the deadline: everything goes ─────────
    await app.inject({ method: 'DELETE', url: '/api/v1/me', headers });
    const afterDeadline = new Date(
      Date.now() + (app.config.accountDeletionGraceDays + 1) * 86400000,
    );
    expect(await app.accountGc.sweep(afterDeadline)).toBeGreaterThanOrEqual(1);

    // The person, their workspace and everything cascading off it are gone.
    expect(await app.db('users').where({ id: userId }).first()).toBeUndefined();
    expect(await app.db('workspaces').where({ id: workspaceId }).first()).toBeUndefined();
    expect(await app.db('projects').where({ id: projectId }).first()).toBeUndefined();
    expect(await app.db('tasks').where({ id: taskId }).first()).toBeUndefined();
    expect(await app.db('files').where({ id: file.id }).first()).toBeUndefined();
    expect(await app.db('workspace_members').where({ user_id: userId }).first()).toBeUndefined();
    expect(await app.db('refresh_tokens').where({ user_id: userId }).first()).toBeUndefined();

    // And the object leaves storage (queued after the transaction commits).
    let gone = null;
    for (let attempt = 0; attempt < 40; attempt += 1) {
      gone = await app.storage.head(storageKey);
      if (gone === null) break;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    expect(gone).toBeNull();

    // The old token now names a user that does not exist.
    const dead = await app.inject({ method: 'GET', url: '/api/v1/me', headers });
    expect(dead.statusCode).toBe(401);
  });
});
