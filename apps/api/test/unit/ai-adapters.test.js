import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from 'vitest';
import { providers } from '../../src/lib/ai/providers/index.js';
import { AiProviderError, upstreamMessage } from '../../src/lib/ai/http.js';
import { startFakeAi } from '../helpers/fakeai.js';

/**
 * OPH-216 — the ×5 contract suite (ADR-0019 §2): five adapters, one shared
 * fake with five native encoders, identical assertions. What it proves is
 * NORMALIZATION — the same script comes back as the same normalized event
 * sequence whichever dialect carried it — plus the two properties that
 * cannot be faked from inside: cancellation really reaches the upstream
 * socket, and the wire really carries each dialect's constrained-output
 * shape.
 */

let fake;

beforeAll(async () => {
  fake = await startFakeAi();
});
afterAll(async () => {
  await fake.app.close();
});
beforeEach(() => {
  fake.reset();
});

const PROVIDER_NAMES = ['anthropic', 'openai', 'gemini', 'openrouter', 'ollama'];

const SCHEMA = {
  type: 'object',
  properties: { intent: { type: 'string' } },
  required: ['intent'],
  additionalProperties: false,
};

describe.each(PROVIDER_NAMES.map((name) => ({ name })))('adapter contract: $name', ({ name }) => {
  const adapter = providers[name];
  const args = (overrides = {}) => ({
    baseUrl: `${fake.url}/${name}`,
    apiKey: 'test-key-123',
    model: 'test-model',
    system: 'system rule',
    messages: [{ role: 'user', content: 'merhaba' }],
    ...overrides,
  });

  async function collectStream(overrides = {}) {
    const events = [];
    for await (const event of adapter.chatStream(args(overrides))) events.push(event);
    return events;
  }

  it('streams the scripted text in order — Turkish chars split across chunks survive', async () => {
    fake.state.chatScript = [{ text: 'Işıklar ' }, { text: 'söndü' }];
    const events = await collectStream();
    const text = events
      .filter((e) => e.type === 'text')
      .map((e) => e.text)
      .join('');
    expect(text).toBe('Işıklar söndü');
  });

  it('reports usage and terminates with done', async () => {
    const events = await collectStream();
    const usage = events.find((e) => e.type === 'usage');
    expect(usage).toMatchObject({ inputTokens: 12, outputTokens: 34 });
    expect(events[events.length - 1].type).toBe('done');
  });

  it('aborts the upstream socket when the consumer stops early', async () => {
    fake.state.stall = true;
    for await (const event of adapter.chatStream(args())) {
      if (event.type === 'text') break;
    }
    await vi.waitFor(() => expect(fake.state.aborted).toBeGreaterThan(0));
  });

  it('an AbortSignal tears down a stalled stream', async () => {
    fake.state.stall = true;
    const ac = new AbortController();
    const run = (async () => {
      for await (const event of adapter.chatStream(args({ signal: ac.signal }))) {
        if (event.type === 'text') ac.abort();
      }
    })();
    await expect(run).rejects.toThrow();
    await vi.waitFor(() => expect(fake.state.aborted).toBeGreaterThan(0));
  });

  it('maps 401 to upstream_auth with the status attached', async () => {
    fake.state.failNext = { status: 401, times: 1 };
    await expect(collectStream()).rejects.toMatchObject({
      name: 'AiProviderError',
      code: 'upstream_auth',
      status: 401,
    });
  });

  it('retries a 429 (Retry-After: 0) on non-stream extract, then succeeds', async () => {
    fake.state.failNext = { status: 429, retryAfter: 0, times: 1 };
    fake.state.extractResults = [{ intent: 'none' }];
    const { json } = await adapter.extract({
      ...args(),
      input: 'text',
      schema: SCHEMA,
      schemaName: 'p',
    });
    expect(json).toEqual({ intent: 'none' });
    const total = Object.values(fake.state.attempts).reduce((a, b) => a + b, 0);
    expect(total).toBe(2);
  });

  it('retries a failed stream HANDSHAKE (5xx before any body byte)', async () => {
    fake.state.failNext = { status: 503, times: 1 };
    const events = await collectStream();
    expect(events.some((e) => e.type === 'text')).toBe(true);
  });

  it('extract returns parsed JSON + usage', async () => {
    fake.state.extractResults = [{ intent: 'create_tasks' }];
    const { json, usage } = await adapter.extract({
      ...args(),
      input: 'yarın fatura öde',
      schema: SCHEMA,
      schemaName: 'proposal',
    });
    expect(json).toEqual({ intent: 'create_tasks' });
    expect(usage).toMatchObject({ inputTokens: 12, outputTokens: 34 });
  });

  it('extract surfaces unparseable output as bad_json carrying rawText', async () => {
    fake.state.extractResults = ['INVALID_JSON'];
    await expect(
      adapter.extract({ ...args(), input: 'x', schema: SCHEMA, schemaName: 'p' }),
    ).rejects.toMatchObject({ code: 'bad_json', rawText: expect.stringContaining('not json') });
  });

  it('verify answers ok against the cheapest authenticated endpoint', async () => {
    await expect(adapter.verify(args())).resolves.toEqual({ ok: true });
  });

  it('a quota-exhausted 429 fails fast — one attempt, verdict preserved', async () => {
    // Out-of-credit never heals between attempts; the old path slept through
    // two retries and the user read the silence as a hang (live finding).
    fake.state.failNext = {
      status: 429,
      retryAfter: 0,
      times: 3,
      body: {
        error: { message: 'You exceeded your current quota.', code: 'insufficient_quota' },
      },
    };
    const attempt = adapter.extract({ ...args(), input: 'text', schema: SCHEMA, schemaName: 'p' });
    await expect(attempt).rejects.toMatchObject({
      name: 'AiProviderError',
      code: 'upstream_rate_limited',
      status: 429,
    });
    const total = Object.values(fake.state.attempts).reduce((a, b) => a + b, 0);
    expect(total).toBe(1);
  });
});

describe('upstreamMessage', () => {
  it('lifts the provider verdict line out of the error body', () => {
    const err = new AiProviderError('upstream_rate_limited', {
      status: 429,
      body: { error: { message: 'You exceeded your current quota.' } },
    });
    expect(upstreamMessage(err)).toBe('You exceeded your current quota.');
  });

  it('handles Ollama plain-string errors and caps long ones', () => {
    expect(
      upstreamMessage(
        new AiProviderError('upstream_error', { body: { error: 'model not found' } }),
      ),
    ).toBe('model not found');
    const long = new AiProviderError('upstream_error', {
      body: { error: { message: 'x'.repeat(500) } },
    });
    expect(upstreamMessage(long)).toHaveLength(240);
    expect(upstreamMessage(long).endsWith('…')).toBe(true);
  });

  it('answers null for bodiless failures and foreign errors', () => {
    expect(upstreamMessage(new AiProviderError('upstream_error'))).toBeNull();
    expect(upstreamMessage(new Error('boom'))).toBeNull();
    expect(upstreamMessage(null)).toBeNull();
  });
});

describe('dialect wire assertions', () => {
  const args = (name, overrides = {}) => ({
    baseUrl: `${fake.url}/${name}`,
    apiKey: 'test-key-123',
    model: 'test-model',
    system: 'sys',
    messages: [{ role: 'user', content: 'merhaba' }],
    input: 'metin',
    schema: SCHEMA,
    schemaName: 'proposal',
    ...overrides,
  });
  const lastRequest = () => fake.state.requests[fake.state.requests.length - 1];

  it('openai sends strict json_schema and include_usage; system as first message', async () => {
    fake.state.extractResults = [{ intent: 'none' }];
    await providers.openai.extract(args('openai'));
    let body = lastRequest().body;
    expect(body.response_format).toEqual({
      type: 'json_schema',
      json_schema: { name: 'proposal', strict: true, schema: SCHEMA },
    });
    expect(body.messages[0]).toEqual({ role: 'system', content: 'sys' });

    for await (const e of providers.openai.chatStream(args('openai'))) void e;
    body = lastRequest().body;
    expect(body.stream_options).toEqual({ include_usage: true });
    expect(body.max_completion_tokens).toBeUndefined();
  });

  it('openrouter reuses the dialect with max_tokens and its courtesy headers', async () => {
    for await (const e of providers.openrouter.chatStream(args('openrouter', { maxTokens: 99 }))) {
      void e;
    }
    const req = lastRequest();
    expect(req.body.max_tokens).toBe(99);
    expect(req.body.max_completion_tokens).toBeUndefined();
    expect(req.headers['x-title']).toBe('AllisWell');
  });

  it('gemini authenticates in the HEADER — the key never reaches the URL', async () => {
    fake.state.extractResults = [{ intent: 'none' }];
    await providers.gemini.extract(args('gemini'));
    const req = lastRequest();
    expect(req.headers['x-goog-api-key']).toBe('test-key-123');
    expect(req.query.key).toBeUndefined();
    expect(req.body.generationConfig).toMatchObject({
      responseMimeType: 'application/json',
      responseSchema: SCHEMA,
    });
    expect(req.body.systemInstruction).toEqual({ parts: [{ text: 'sys' }] });
  });

  it('anthropic sends the version header, required max_tokens and output_format', async () => {
    fake.state.extractResults = [{ intent: 'none' }];
    await providers.anthropic.extract(args('anthropic'));
    const req = lastRequest();
    expect(req.headers['anthropic-version']).toBe('2023-06-01');
    expect(req.headers['anthropic-beta']).toContain('structured-outputs');
    expect(req.body.max_tokens).toBeGreaterThan(0);
    expect(req.body.output_format).toMatchObject({ type: 'json_schema', schema: SCHEMA });
    expect(req.body.system).toBe('sys');
  });

  it('ollama sends the FULL schema as format and maps assistant history', async () => {
    fake.state.extractResults = [{ intent: 'none' }];
    await providers.ollama.extract(args('ollama'));
    expect(lastRequest().body.format).toEqual(SCHEMA);

    for await (const e of providers.ollama.chatStream(
      args('ollama', {
        messages: [
          { role: 'user', content: 'a' },
          { role: 'assistant', content: 'b' },
        ],
      }),
    )) {
      void e;
    }
    const body = lastRequest().body;
    expect(body.messages).toEqual([
      { role: 'system', content: 'sys' },
      { role: 'user', content: 'a' },
      { role: 'assistant', content: 'b' },
    ]);
  });

  it('ollama lists live models from /api/tags', async () => {
    const models = await providers.ollama.listModels({
      baseUrl: `${fake.url}/ollama`,
      apiKey: null,
    });
    expect(models).toEqual([{ id: 'llama3.3:latest' }, { id: 'llama3.2:1b' }]);
  });

  it('gemini maps assistant→model in contents', async () => {
    for await (const e of providers.gemini.chatStream(
      args('gemini', {
        messages: [
          { role: 'user', content: 'soru' },
          { role: 'assistant', content: 'cevap' },
          { role: 'user', content: 'devam' },
        ],
      }),
    )) {
      void e;
    }
    const body = lastRequest().body;
    expect(body.contents.map((c) => c.role)).toEqual(['user', 'model', 'user']);
  });
});
