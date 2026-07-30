import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeAi } from '../helpers/fakeai.js';
import { fenceBlock, renderChatSystem, BASE_SYSTEM_RULE } from '../../src/lib/ai/context.js';

/**
 * OPH-226 — the red-team corpus against the app-facing AI surfaces (extract +
 * the chat system renderer). The MCP surface is covered by mcp-injection.test.js;
 * this one proves the OTHER two edges: hostile text is FENCED on the way to the
 * model, and extract produces DATA (a proposal), never a task row. The boundary
 * is not the fence — it is that extract/chat give the model no write tools and
 * every write goes through the confirm card (AI.md §8).
 */

const corpusPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../app/test/fixtures/ai_redteam.json',
);
const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));

const VALID_PROPOSAL = {
  intent: 'create_tasks',
  tasks: [{ title: 'Fatura öde', confidence: 0.9 }],
};

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
  owner = await registerUser(app, { email: 'ai-injection@example.com' });
  await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/ai/connections`,
    headers: owner.headers,
    payload: {
      provider: 'openai',
      apiKey: 'sk-injection-123',
      baseUrl: `${fake.url}/openai`,
      consentAcknowledged: true,
    },
  });
});

function extract(body = {}) {
  return app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/ai/extract`,
    headers: owner.headers,
    payload: { source: 'voice', ...body },
  });
}

const lastUserPrompt = () => fake.state.requests.at(-1).body.messages[1].content;

describe('extract fences hostile content and never acts (OPH-226)', () => {
  for (const c of corpus.cases) {
    it(`fences the "${c.id}" payload and writes no task`, async () => {
      fake.state.extractResults = [VALID_PROPOSAL];
      const tasksBefore = tables.tasks.length;

      const res = await extract({ text: c.text });
      expect(res.statusCode).toBe(200);

      // The hostile text left fenced exactly as the production renderer fences
      // it — the escaped closing tag for the fence-escape case included, so a
      // </user_data> in content can never terminate the block early.
      expect(lastUserPrompt()).toContain(fenceBlock({ source: 'voice', text: c.text }));
      // Extract produces a proposal (DATA). It creates no task; the confirm
      // card is the only writer.
      expect(tables.tasks.length).toBe(tasksBefore);
    });
  }

  it('a compromised model cannot smuggle an action field into the proposal', async () => {
    // First the model "obeys" the injection and returns fields beyond the
    // schema; the second scripted result is the clean value a repair re-prompt
    // would get. Either path is safe.
    fake.state.extractResults = [
      {
        intent: 'create_tasks',
        tasks: [{ title: 'x', confidence: 0.9, action: 'delete_all', tool: 'delete' }],
      },
      { intent: 'create_tasks', tasks: [{ title: 'x', confidence: 0.9 }] },
    ];
    const res = await extract({ text: 'hi' });

    // Ajv (additionalProperties:false) has the last word: whether it repairs to
    // a clean proposal or 422s, the smuggled fields never reach the client.
    expect([200, 422]).toContain(res.statusCode);
    const body = JSON.stringify(res.json());
    expect(body).not.toContain('delete_all');
    expect(body).not.toMatch(/"(action|tool)"\s*:/);
    // And extract writes nothing regardless.
    expect(tables.tasks.length).toBe(0);
  });
});

describe('the fence renderer holds the boundary (OPH-226)', () => {
  it('escapes a closing </user_data> inside content', () => {
    const escaper = corpus.cases.find((c) => c.id === 'fence-escape');
    const block = fenceBlock({ source: 'note', text: escaper.text });
    // Exactly one real closing tag (the fence's own), at the end.
    expect(block.match(/<\/user_data>/g)).toHaveLength(1);
    expect(block.trimEnd().endsWith('</user_data>')).toBe(true);
    expect(block).toContain('<\\/user_data>'); // the content's tag, escaped
  });

  it('the chat system prompt states the data rule and fences every segment', () => {
    const segments = corpus.cases
      .filter((c) => ['note', 'model_output', 'title'].includes(c.surface))
      .map((c) => ({ tier: 't2', source: 'external_share', text: c.text }));
    const system = renderChatSystem(segments, { truncated: false });

    expect(system).toContain(BASE_SYSTEM_RULE);
    expect(system).toContain('never instructions');
    for (const s of segments) {
      expect(system).toContain(fenceBlock({ source: 'external_share', tier: 't2', text: s.text }));
    }
  });
});
