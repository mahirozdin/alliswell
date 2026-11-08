import { execFile } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { storageTestEnv, ensureBucket } from '../helpers/minio.js';

/**
 * OPH-414 — `npm run seed:demo` against a real server, twice. The acceptance
 * line of the task: the seed is idempotent and a second run fails on nothing.
 *
 * The script is run as the CLI it is (a child process over real HTTP, real
 * MySQL, real MinIO, real OAuth for the MCP step), so what passes here is what
 * an operator gets. Before OPH-414 the second run uploaded every file again —
 * the "already there" check read `items` from a response that says `files`,
 * at the root folder level the seed never uploads to.
 */
const enabled = process.env.INTEGRATION === '1';
const SEED = join(dirname(fileURLToPath(import.meta.url)), '../../../../scripts/seed-demo.mjs');
const run = promisify(execFile);

describe.runIf(enabled)('integration: demo seed (OPH-414)', () => {
  let app;
  let api;
  const email = `seed-demo-${Date.now()}@example.com`;
  const password = 'seed-demo-pass-1';

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...storageTestEnv(), NODE_ENV: 'test' });
    await ensureBucket(config.storage);
    app = await buildApp({ config });
    await app.listen({ port: 0, host: '127.0.0.1' });
    api = `http://127.0.0.1:${app.server.address().port}`;
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where({ email }).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('workspace_members').whereIn('user_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  const seed = () =>
    run(process.execPath, [SEED, '--api', api, '--email', email, '--password', password], {
      env: { ...process.env, ...storageTestEnv(), NODE_ENV: 'test' },
      timeout: 170_000,
      maxBuffer: 4 * 1024 * 1024,
    });

  async function counts() {
    const user = await app.db('users').where({ email }).first('id');
    const ws = (await app.db('workspace_members').where({ user_id: user.id }).first('workspace_id'))
      .workspace_id;
    const count = async (table, where = {}) =>
      Number(
        (
          await app
            .db(table)
            .where({ workspace_id: ws, ...where })
            .count({ n: '*' })
        )[0].n,
      );
    const note = await app
      .db('notes')
      .where({ workspace_id: ws, title: 'Launch checklist' })
      .first();
    return {
      tasks: await count('tasks'),
      notes: await count('notes'),
      files: Number(
        (
          await app
            .db('files')
            .where({ workspace_id: ws, status: 'ready' })
            .whereNull('deleted_at')
            .count({ n: '*' })
        )[0].n,
      ),
      apiKeys: await count('api_keys'),
      ai: await count('ai_connections'),
      ledger: await count('import_ledger'),
      versions: (await app.db('note_versions').where({ note_id: note.id }).orderBy('created_at'))
        .map((v) => v.origin)
        .join(','),
      fileSizes: await app
        .db('files')
        .where({ workspace_id: ws })
        .whereNull('deleted_at')
        .select('name', 'size_bytes'),
    };
  }

  it('seeds every surface, and a second run adds nothing and fails on nothing', async () => {
    const first = await seed();
    expect(first.stdout).toContain('Demo workspace ready.');
    const once = await counts();

    expect(once.files).toBe(7);
    // Real bytes, not the old `n` kB of spaces.
    for (const f of once.fileSizes) expect(Number(f.size_bytes) % 1024).not.toBe(0);
    expect(once.apiKeys).toBe(1);
    expect(once.ai).toBe(1);
    expect(once.ledger).toBeGreaterThanOrEqual(3);
    // Born as a draft, edited in the app, finished by an MCP client.
    expect(once.versions).toBe('create,edit,mcp');
    expect(first.stdout).not.toMatch(/^\s*! /m);

    const second = await seed();
    expect(second.stdout).toContain('Demo workspace ready.');
    expect(second.stdout).not.toMatch(/^\s*! /m);
    expect(await counts()).toEqual(once);
  }, 360_000);
});
