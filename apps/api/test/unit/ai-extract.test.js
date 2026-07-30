import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeAi } from '../helpers/fakeai.js';
import { enforcePastDueAmbiguity } from '../../src/lib/ai/extract.js';

/**
 * OPH-219 — the extraction pipeline over the fake provider. The fake is not
 * an LLM: scripted results prove PROMPT ASSEMBLY (what we send) and PIPELINE
 * SEMANTICS (validation, repair, logging, accounting) — the parts that are
 * ours to get right.
 */

let fake;
let app;
let tables;
let owner;

beforeAll(async () => {
  fake = await startFakeAi();
});
afterAll(async () => {
  await fake.app.close();
});

beforeEach(async () => {
  fake.reset();
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'ai-extract@example.com' });
  await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/ai/connections`,
    headers: owner.headers,
    payload: {
      provider: 'openai',
      apiKey: 'sk-extract-123',
      baseUrl: `${fake.url}/openai`,
      consentAcknowledged: true,
    },
  });
});

const VALID_PROPOSAL = {
  intent: 'create_tasks',
  tasks: [
    {
      title: 'Fatura öde',
      projectName: 'Ahmet',
      dueAt: '2027-01-01T15:00:00+03:00',
      dueAtSource: 'yarın 15:00',
      confidence: 0.9,
    },
    { title: 'Rapor yaz', confidence: 0.8 },
  ],
};

function extract(body = {}) {
  return app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/ai/extract`,
    headers: owner.headers,
    payload: {
      text: 'Ahmet projesine yarın şu iki işi ekle: fatura, rapor',
      source: 'voice',
      ...body,
    },
  });
}

const lastRequestBody = () => fake.state.requests.at(-1).body;

describe('POST /ai/extract (OPH-219)', () => {
  it('returns the proposal untouched and logs it as an undecided action', async () => {
    fake.state.extractResults = [VALID_PROPOSAL];
    const res = await extract();
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.repaired).toBe(false);
    expect(body.proposal.tasks).toHaveLength(2);
    // projectName comes back VERBATIM — resolution is the client's job.
    expect(body.proposal.tasks[0].projectName).toBe('Ahmet');

    expect(tables.ai_action_log).toHaveLength(1);
    const logRow = tables.ai_action_log[0];
    expect(logRow.accepted).toBeNull();
    expect(logRow.source).toBe('voice');
    expect(JSON.parse(logRow.proposal).tasks).toHaveLength(2);
    expect(body.actionId).toBe(logRow.id);
  });

  it('assembles the prompt: now+offset, TZ, weekday, default time, fences', async () => {
    fake.state.extractResults = [VALID_PROPOSAL];
    await extract({ defaultTaskTime: '09:00', projectNames: ['Ahmet', 'Okul'] });
    const sent = lastRequestBody();
    const system = sent.messages[0].content;
    expect(sent.messages[0].role).toBe('system');
    // now with the user's offset (registration default TZ Europe/Istanbul).
    expect(system).toMatch(/Now is \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}/);
    expect(system).toContain('(Europe/Istanbul)');
    expect(system).toMatch(/today is (Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day/);
    expect(system).toContain('default time 09:00');
    expect(system).toContain('<user_data source="project_names">\nAhmet\nOkul\n</user_data>');
    // The utterance itself is fenced with its surface as the source.
    const user = sent.messages[1].content;
    expect(user).toContain('<user_data source="voice">');
    // Strict json_schema went out on the wire.
    expect(sent.response_format.json_schema.strict).toBe(true);
  });

  it('falls back to the product default time when the client sends none', async () => {
    fake.state.extractResults = [VALID_PROPOSAL];
    await extract();
    expect(lastRequestBody().messages[0].content).toContain('default time 23:59');
  });

  it('appends date_unclear to a past due the model failed to flag', async () => {
    fake.state.extractResults = [
      {
        intent: 'create_tasks',
        tasks: [
          {
            title: 'Geçmiş iş',
            dueAt: '2020-01-01T10:00:00+03:00',
            dueAtSource: 'dün',
            confidence: 0.7,
          },
        ],
      },
    ];
    const res = await extract();
    expect(res.statusCode).toBe(200);
    const task = res.json().proposal.tasks[0];
    expect(task.ambiguities).toContain('date_unclear');
    // The date itself is NOT shifted — visible, never silent.
    expect(task.dueAt).toBe('2020-01-01T10:00:00+03:00');
  });

  it('repairs once: invalid then valid → repaired:true and TWO usage rows', async () => {
    fake.state.extractResults = [
      { intent: 'create_tasks', tasks: [{ title: '', confidence: 2 }] }, // invalid
      VALID_PROPOSAL,
    ];
    const res = await extract();
    expect(res.statusCode).toBe(200);
    expect(res.json().repaired).toBe(true);
    expect(tables.ai_usage_events.filter((r) => r.kind === 'extract')).toHaveLength(2);
    // The repair turn carries the validator's own words.
    expect(lastRequestBody().messages[1].content).toContain('previous answer was invalid');
  });

  it('recovers from unparseable output the same way (rawText fed back)', async () => {
    fake.state.extractResults = ['INVALID_JSON', VALID_PROPOSAL];
    const res = await extract();
    expect(res.statusCode).toBe(200);
    expect(res.json().repaired).toBe(true);
    expect(lastRequestBody().messages[1].content).toContain('not json');
  });

  it('twice-invalid → 422 AI_EXTRACTION_INVALID, usage rows yes, log row NO', async () => {
    fake.state.extractResults = [
      { intent: 'create_tasks', tasks: [{ title: '', confidence: 2 }] },
      'INVALID_JSON',
    ];
    const res = await extract();
    expect(res.statusCode).toBe(422);
    expect(res.json().code).toBe('AI_EXTRACTION_INVALID');
    expect(tables.ai_usage_events.length).toBeGreaterThanOrEqual(2);
    expect(tables.ai_action_log).toHaveLength(0);
  });

  it('shares the rate bucket with chat', async () => {
    const { loadConfig } = await import('../../src/config.js');
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      AI_RATE_BURST: '1',
      AI_RATE_PER_MINUTE: '1',
    });
    const { app: tightApp } = await buildTestApp({ config });
    const user = await registerUser(tightApp, { email: 'ai-extract-rl@example.com' });
    const first = await tightApp.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${user.workspace.id}/ai/extract`,
      headers: user.headers,
      payload: { text: 'x', source: 'bubble' },
    });
    expect(first.statusCode).toBe(503); // no connection — but the token is spent
    const second = await tightApp.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${user.workspace.id}/ai/chat`,
      headers: user.headers,
      payload: {
        requestId: '01AI0000000000000000000002',
        messages: [{ role: 'user', content: 'x' }],
      },
    });
    expect(second.statusCode).toBe(429);
    expect(second.json().code).toBe('AI_RATE_LIMITED');
  });
});

describe('enforcePastDueAmbiguity (pure)', () => {
  it('only touches genuinely past dues and never duplicates the flag', () => {
    const now = new Date('2026-07-30T12:00:00Z');
    const proposal = {
      tasks: [
        { title: 'a', dueAt: '2026-07-30T11:00:00Z', dueAtSource: 'x', confidence: 1 },
        { title: 'b', dueAt: '2026-07-30T13:00:00Z', dueAtSource: 'y', confidence: 1 },
        {
          title: 'c',
          dueAt: '2026-07-29T11:00:00Z',
          dueAtSource: 'z',
          confidence: 1,
          ambiguities: ['date_unclear'],
        },
        { title: 'd', confidence: 1 },
      ],
    };
    const out = enforcePastDueAmbiguity(proposal, now);
    expect(out.tasks[0].ambiguities).toEqual(['date_unclear']);
    expect(out.tasks[1].ambiguities).toBeUndefined();
    expect(out.tasks[2].ambiguities).toEqual(['date_unclear']);
    expect(out.tasks[3].ambiguities).toBeUndefined();
  });
});
