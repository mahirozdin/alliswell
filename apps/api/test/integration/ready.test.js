import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

// These tests need real MySQL + Redis (docker compose up -d mysql redis)
// and applied migrations (npm run db:migrate). CI always runs them.
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('integration: health against real infrastructure', () => {
  let app;

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
  });

  afterAll(async () => {
    if (app) await app.close();
  });

  it('GET /health/ready reports all components up', async () => {
    const res = await app.inject({ method: 'GET', url: '/health/ready' });
    expect(res.json()).toMatchObject({
      status: 'ok',
      checks: { mysql: { status: 'up' }, redis: { status: 'up' } },
    });
    expect(res.statusCode).toBe(200);
  });

  it('has all baseline migrations applied', async () => {
    const migrations = await app.db('knex_migrations').select('name');
    expect(migrations.length).toBeGreaterThanOrEqual(5);

    const [rows] = await app.db.raw(
      `SELECT COUNT(*) AS c FROM information_schema.tables
       WHERE table_schema = ? AND table_name IN
       ('users','workspaces','workspace_members','refresh_tokens',
        'projects','tags','tasks','task_tags','checklist_items',
        'notes','note_tags','note_links',
        'sync_revisions','client_mutations',
        'calendar_accounts','calendar_event_links','reminders')`,
      [app.config.database.name],
    );
    expect(Number(rows[0].c)).toBe(17);
  });

  it('enforces the unique workspace revision constraint', async () => {
    const [rows] = await app.db.raw(
      `SELECT COUNT(*) AS c FROM information_schema.statistics
       WHERE table_schema = ? AND table_name = 'sync_revisions' AND index_name = 'uq_workspace_revision'`,
      [app.config.database.name],
    );
    expect(Number(rows[0].c)).toBeGreaterThan(0);
  });
});
