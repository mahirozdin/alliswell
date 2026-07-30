import Fastify from 'fastify';

/**
 * In-process AI provider farm (OPH-216) — ONE Fastify serving all five wire
 * dialects, reached over real HTTP because every adapter base URL is config-
 * driven (the ADR-0006 §5 / fakegoogle pattern). One shared script, five
 * encoders: `state.chatScript` is rendered into each dialect's NATIVE frames,
 * which is what makes the ×5 contract suite prove normalization instead of
 * testing the fake.
 *
 * Assertion surface: `state.requests` (method/path/query/headers/body),
 * `state.aborted` (client disconnects mid-stream — proves AbortSignal reaches
 * the upstream socket), `state.attempts` per path (retry proofs),
 * `state.failNext = {status, body, retryAfter, times}` and `state.stall`
 * (emit chunks, then hang until the client gives up).
 */
export async function startFakeAi() {
  const state = {
    chatScript: [{ text: 'Merhaba ' }, { text: 'dünya' }],
    usage: { input: 12, output: 34 },
    stopReason: 'stop',
    extractResults: [], // queue of objects | 'INVALID_JSON'
    failNext: null,
    stall: false,
    aborted: 0,
    requests: [],
    attempts: {},
    tags: [{ name: 'llama3.3:latest' }, { name: 'llama3.2:1b' }],
  };

  const reset = () => {
    state.chatScript = [{ text: 'Merhaba ' }, { text: 'dünya' }];
    state.usage = { input: 12, output: 34 };
    state.stopReason = 'stop';
    state.extractResults = [];
    state.failNext = null;
    state.stall = false;
    state.aborted = 0;
    state.requests = [];
    state.attempts = {};
  };

  const app = Fastify({ logger: false });

  app.addHook('onRequest', async (request) => {
    const path = request.url.split('?')[0];
    state.attempts[path] = (state.attempts[path] ?? 0) + 1;
    state.requests.push({
      method: request.method,
      path,
      query: { ...request.query },
      headers: { ...request.headers },
    });
  });
  // Body isn't parsed yet at onRequest; attach it once it is.
  app.addHook('preHandler', async (request) => {
    state.requests[state.requests.length - 1].body = request.body ?? null;
  });

  /** One-shot scripted failure, honored by every route. */
  function maybeFail(reply) {
    if (!state.failNext || state.failNext.times <= 0) return false;
    state.failNext.times -= 1;
    const { status, body, retryAfter } = state.failNext;
    if (retryAfter !== undefined) reply.header('retry-after', String(retryAfter));
    reply.code(status).send(body ?? { error: { message: `scripted ${status}` } });
    return true;
  }

  function nextExtractRaw() {
    const next = state.extractResults.shift() ?? { intent: 'none', tasks: [] };
    return next === 'INVALID_JSON' ? 'this is { not json' : JSON.stringify(next);
  }

  /**
   * Streams `frames` (strings) over a hijacked reply. Every frame's bytes are
   * written in TWO halves so multi-byte characters split across TCP writes —
   * the decoder-correctness fixture. Tracks aborts; honors `state.stall`.
   */
  function streamFrames(request, reply, contentType, frames) {
    reply.hijack();
    const raw = reply.raw;
    raw.writeHead(200, { 'content-type': contentType });
    let finished = false;
    let closed = false;
    // ServerResponse 'close', NOT IncomingMessage 'close': the request-side
    // event means "request complete", not "connection died" — a client abort
    // only reliably surfaces on the RESPONSE object (learned empirically;
    // OPH-217's real SSE endpoint must use the same listener).
    raw.on('close', () => {
      closed = true;
      if (!finished) state.aborted += 1;
    });

    // Stall mode holds back the TERMINAL frame (message_stop / [DONE] /
    // done:true) so the adapter's read loop stays genuinely open — a stall
    // that has already said "the end" isn't a stall, it's a slow goodbye.
    const limit = state.stall ? frames.length - 1 : frames.length;
    let index = 0;
    const writeNext = () => {
      if (closed) return;
      if (index >= limit) {
        if (state.stall) return; // hang: only a client abort ends this request
        finished = true;
        raw.end();
        return;
      }
      const buffer = Buffer.from(frames[index], 'utf8');
      index += 1;
      const mid = Math.max(1, Math.floor(buffer.length / 2));
      raw.write(buffer.subarray(0, mid));
      setImmediate(() => {
        if (closed) return;
        raw.write(buffer.subarray(mid));
        setImmediate(writeNext);
      });
    };
    writeNext();
  }

  const sse = (event, data) =>
    (event ? `event: ${event}\n` : '') + `data: ${JSON.stringify(data)}\n\n`;

  // ── Anthropic ─────────────────────────────────────────────────────────────
  app.post('/anthropic/v1/messages', (request, reply) => {
    if (maybeFail(reply)) return;
    if (request.body?.stream) {
      const frames = [
        sse('message_start', {
          type: 'message_start',
          message: { usage: { input_tokens: state.usage.input } },
        }),
        sse('ping', { type: 'ping' }),
        ...state.chatScript.map((chunk) =>
          sse('content_block_delta', {
            type: 'content_block_delta',
            delta: { type: 'text_delta', text: chunk.text },
          }),
        ),
        sse('message_delta', {
          type: 'message_delta',
          usage: { output_tokens: state.usage.output },
          delta: { stop_reason: state.stopReason },
        }),
        sse('message_stop', { type: 'message_stop' }),
      ];
      streamFrames(request, reply, 'text/event-stream', frames);
      return;
    }
    reply.send({
      content: [{ type: 'text', text: nextExtractRaw() }],
      usage: { input_tokens: state.usage.input, output_tokens: state.usage.output },
      stop_reason: state.stopReason,
    });
  });
  app.get('/anthropic/v1/models', (request, reply) => {
    if (maybeFail(reply)) return;
    reply.send({ data: [{ id: 'claude-sonnet-5' }] });
  });

  // ── OpenAI + OpenRouter (same dialect, two prefixes) ──────────────────────
  for (const prefix of ['openai', 'openrouter']) {
    app.post(`/${prefix}/v1/chat/completions`, (request, reply) => {
      if (maybeFail(reply)) return;
      if (request.body?.stream) {
        const frames = [
          ...state.chatScript.map((chunk) =>
            sse(null, { choices: [{ delta: { content: chunk.text } }] }),
          ),
          sse(null, { choices: [{ delta: {}, finish_reason: state.stopReason }] }),
          sse(null, {
            choices: [],
            usage: {
              prompt_tokens: state.usage.input,
              completion_tokens: state.usage.output,
            },
          }),
          'data: [DONE]\n\n',
        ];
        streamFrames(request, reply, 'text/event-stream', frames);
        return;
      }
      reply.send({
        choices: [{ message: { content: nextExtractRaw() } }],
        usage: { prompt_tokens: state.usage.input, completion_tokens: state.usage.output },
      });
    });
  }
  app.get('/openai/v1/models', (request, reply) => {
    if (maybeFail(reply)) return;
    reply.send({ data: [{ id: 'gpt-5.1' }] });
  });
  app.get('/openrouter/v1/auth/key', (request, reply) => {
    if (maybeFail(reply)) return;
    reply.send({ data: { label: 'test-key' } });
  });

  // ── Gemini (the whole segment lands in :modelAction, colon included) ──────
  app.post('/gemini/v1beta/models/:modelAction', (request, reply) => {
    if (maybeFail(reply)) return;
    const action = request.params.modelAction.split(':')[1] ?? '';
    if (action === 'streamGenerateContent') {
      const frames = [
        ...state.chatScript.map((chunk) =>
          sse(null, { candidates: [{ content: { parts: [{ text: chunk.text }] } }] }),
        ),
        sse(null, {
          candidates: [{ content: { parts: [] }, finishReason: state.stopReason }],
          usageMetadata: {
            promptTokenCount: state.usage.input,
            candidatesTokenCount: state.usage.output,
          },
        }),
      ];
      streamFrames(request, reply, 'text/event-stream', frames);
      return;
    }
    reply.send({
      candidates: [{ content: { parts: [{ text: nextExtractRaw() }] } }],
      usageMetadata: {
        promptTokenCount: state.usage.input,
        candidatesTokenCount: state.usage.output,
      },
    });
  });
  app.get('/gemini/v1beta/models', (request, reply) => {
    if (maybeFail(reply)) return;
    reply.send({ models: [{ name: 'models/gemini-2.5-flash' }] });
  });

  // ── Ollama (NDJSON, not SSE) ──────────────────────────────────────────────
  app.post('/ollama/api/chat', (request, reply) => {
    if (maybeFail(reply)) return;
    if (request.body?.stream) {
      const frames = [
        ...state.chatScript.map(
          (chunk) => `${JSON.stringify({ message: { content: chunk.text }, done: false })}\n`,
        ),
        `${JSON.stringify({
          done: true,
          done_reason: state.stopReason,
          prompt_eval_count: state.usage.input,
          eval_count: state.usage.output,
        })}\n`,
      ];
      streamFrames(request, reply, 'application/x-ndjson', frames);
      return;
    }
    reply.send({
      message: { content: nextExtractRaw() },
      done: true,
      prompt_eval_count: state.usage.input,
      eval_count: state.usage.output,
    });
  });
  app.get('/ollama/api/tags', (request, reply) => {
    if (maybeFail(reply)) return;
    reply.send({ models: state.tags });
  });

  await app.listen({ port: 0, host: '127.0.0.1' });
  const url = `http://127.0.0.1:${app.server.address().port}`;
  return { app, url, state, reset };
}
