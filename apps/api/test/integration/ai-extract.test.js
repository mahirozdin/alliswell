import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
import { startFakeAi } from '../helpers/fakeai.js';

/**
 * OPH-219 over real MySQL: the JSON columns round-trip (proposal in
 * ai_action_log, entity_refs after a decision) and the source ENUM accepts
 * the extract surfaces.
 */
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('AI extract integration (OPH-219)', () => {
  let fake;
  let app;
  let ws;
  let headers;
  const emailPrefix = `ai-extract-int-${Date.now()}`;

  beforeAll(async () => {
    fake = await startFakeAi();
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'sifre-12345' },
    });
    const body = res.json();
    ws = body.workspace.id;
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
    await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/ai/connections`,
      headers,
      payload: {
        provider: 'anthropic',
        apiKey: 'sk-int-extract-123',
        baseUrl: `${fake.url}/anthropic`,
        consentAcknowledged: true,
      },
    });
  });

  afterAll(async () => {
    if (app) {
      const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
      const ids = users.map((u) => u.id);
      if (ids.length > 0) {
        await app.db('workspaces').whereIn('owner_id', ids).delete();
        await app.db('workspace_members').whereIn('user_id', ids).delete();
        await app.db('users').whereIn('id', ids).delete();
      }
      await app.close();
    }
    if (fake) await fake.app.close();
  });

  it('proposal JSON survives MySQL and the decision writes refs + timestamps', async () => {
    fake.state.extractResults = [
      {
        intent: 'create_tasks',
        tasks: [
          {
            title: 'Türkçe başlık: ışık faturası',
            projectName: 'Ev işleri',
            dueAt: '2027-03-01T09:30:00+03:00',
            dueAtSource: 'gelecek pazartesi 09:30',
            confidence: 0.85,
          },
        ],
      },
    ];
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/ai/extract`,
      headers,
      payload: { text: 'ev işlerine ışık faturası ekle', source: 'share' },
    });
    expect(res.statusCode).toBe(200);
    const { actionId, proposal } = res.json();
    expect(proposal.tasks[0].title).toBe('Türkçe başlık: ışık faturası');

    const row = await app.db('ai_action_log').where({ id: actionId }).first();
    expect(row.source).toBe('share');
    const stored = typeof row.proposal === 'string' ? JSON.parse(row.proposal) : row.proposal;
    expect(stored.tasks[0].projectName).toBe('Ev işleri');

    const taskId = '01INTEGRATION0000000000TSK'.slice(0, 26);
    const decision = await app.inject({
      method: 'POST',
      url: `/api/v1/ai/actions/${actionId}/decision`,
      headers,
      payload: { accepted: true, entityRefs: [{ type: 'task', id: taskId }] },
    });
    expect(decision.statusCode).toBe(200);
    expect(decision.json().accepted).toBe(true);
    expect(decision.json().entityRefs).toEqual([{ type: 'task', id: taskId }]);

    const decided = await app.db('ai_action_log').where({ id: actionId }).first();
    expect(decided.decided_at).not.toBeNull();
    // MySQL boolean → 1; the serializer already proved the Boolean mapping.
    expect(Number(decided.accepted)).toBe(1);
  });

  it('usage rows for a repaired extraction land as TWO real rows', async () => {
    fake.state.extractResults = ['INVALID_JSON', { intent: 'none', tasks: [] }];
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/ai/extract`,
      headers,
      payload: { text: 'sadece soru', source: 'quick_add' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().repaired).toBe(true);
    const requestId = res.json().requestId;
    const rows = await app.db('ai_usage_events').where({ request_id: requestId }).select();
    expect(rows).toHaveLength(2);
    expect(rows.every((r) => r.kind === 'extract')).toBe(true);
  });
});
