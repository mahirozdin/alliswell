import { renderChatSystem } from './context.js';
import { upstreamMessage } from './http.js';

/**
 * The chat engine (OPH-217): ONE code path from adapter stream to client,
 * whatever the transport. `runChat` pumps a provider stream into a sink;
 * `sseSink` writes SSE frames onto a hijacked reply, `socketSink` emits
 * `ai:stream` events into the caller's personal room. The sink contract:
 *
 *   start({requestId})  text({text})  usage({inputTokens, outputTokens})
 *   done({requestId, stopReason} | {requestId, cancelled: true})
 *   error({code, message})  heartbeat?()  end?()
 *
 * Cancellation is NOT an error: a cancel (bubble dismissed) ends the stream
 * with `done {cancelled: true}`. A silent client disconnect writes nothing —
 * there is nobody left to write to — but still aborts the upstream fetch.
 */

/** Abort reasons the route layer sets so runChat can tell the cases apart. */
export const ABORT_CANCELLED = 'ai:cancelled';
export const ABORT_CLIENT_GONE = 'ai:client-gone';

function errorCode(err) {
  if (err?.code === 'upstream_auth') return 'AI_UPSTREAM_AUTH_FAILED';
  if (err?.code === 'upstream_rate_limited') return 'AI_UPSTREAM_RATE_LIMITED';
  return 'AI_UPSTREAM_ERROR';
}

/**
 * @param {{
 *   app: import('fastify').FastifyInstance,
 *   resolution: {adapter: object, provider: string, connectionId: string, apiKey: string|null, baseUrl: string},
 *   requestId: string, model: string,
 *   messages: Array<{role: string, content: string}>,
 *   context?: {segments?: Array<object>, truncated?: boolean} | null,
 *   userId: string, workspaceId: string,
 *   sink: object, signal: AbortSignal,
 * }} input
 */
export async function runChat({
  app,
  resolution,
  requestId,
  model,
  messages,
  context,
  userId,
  workspaceId,
  sink,
  signal,
}) {
  const started = Date.now();
  const system = renderChatSystem(context?.segments ?? [], {
    truncated: Boolean(context?.truncated),
  });
  let inputTokens = null;
  let outputTokens = null;
  let stopReason = null;
  let authFailed = false;

  const heartbeat = setInterval(() => {
    try {
      sink.heartbeat?.();
    } catch {
      /* a dead sink must not kill the pump; the abort signal ends it */
    }
  }, app.config.ai.heartbeatMs);
  heartbeat.unref?.();

  try {
    await sink.start({ requestId });
    const stream = resolution.adapter.chatStream({
      baseUrl: resolution.baseUrl,
      apiKey: resolution.apiKey,
      model,
      system,
      messages,
      signal,
    });
    for await (const event of stream) {
      if (event.type === 'text') {
        await sink.text({ text: event.text });
      } else if (event.type === 'usage') {
        inputTokens = event.inputTokens ?? null;
        outputTokens = event.outputTokens ?? null;
        await sink.usage({ inputTokens, outputTokens });
      } else if (event.type === 'done') {
        stopReason = event.stopReason ?? null;
      }
    }
    await sink.done({ requestId, stopReason });
  } catch (err) {
    if (signal.aborted && signal.reason === ABORT_CANCELLED) {
      await sink.done({ requestId, cancelled: true });
    } else if (signal.aborted) {
      // Client gone: nothing to write, upstream already aborted via signal.
    } else {
      const code = errorCode(err);
      authFailed = code === 'AI_UPSTREAM_AUTH_FAILED';
      // The provider's own verdict line rides along (status + capped message,
      // never content) — without it every live failure reads the same and is
      // undebuggable, which is exactly how the alliswell.space incident hid.
      const detail = upstreamMessage(err);
      app.log.warn(
        { err: err.message, status: err.status ?? null, upstream: detail, requestId },
        'ai chat upstream failed',
      );
      await sink.error({ code, message: detail ?? 'The AI provider failed to answer' });
    }
  } finally {
    clearInterval(heartbeat);
    await app.ai.recordUsage({
      workspaceId,
      userId,
      connectionId: resolution.connectionId,
      provider: resolution.provider,
      kind: 'chat',
      model,
      inputTokens,
      outputTokens,
      durationMs: Date.now() - started,
      requestId,
    });
    await app.ai.touchConnection(resolution.connectionId);
    if (resolution.authMode === 'instance_env') {
      await app.ai.dailyCap.add(userId, (inputTokens ?? 0) + (outputTokens ?? 0));
    }
    if (authFailed) {
      try {
        await app
          .db('ai_connections')
          .where({ id: resolution.connectionId })
          .update({ status: 'error', updated_at: new Date() });
      } catch {
        /* cosmetic flag; never fail the stream teardown over it */
      }
    }
    await sink.end?.();
  }
}

/** SSE writer over a hijacked reply — backpressure-aware, close-tolerant. */
export function sseSink(reply) {
  reply.hijack();
  const raw = reply.raw;
  raw.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
    // Belt-and-braces for nginx-style proxies; Apache needs the conf checklist.
    'x-accel-buffering': 'no',
  });

  const write = (frame) =>
    new Promise((resolve) => {
      if (raw.writableEnded || raw.destroyed) return resolve();
      const ok = raw.write(frame);
      if (ok) resolve();
      else raw.once('drain', resolve);
    });
  const event = (name, data) => write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);

  return {
    start: (data) => event('start', data),
    text: (data) => event('text', data),
    usage: (data) => event('usage', data),
    done: (data) => event('done', data),
    error: (data) => event('error', data),
    heartbeat: () => {
      if (!raw.writableEnded && !raw.destroyed) raw.write(': hb\n\n');
    },
    end: () =>
      new Promise((resolve) => {
        if (raw.writableEnded || raw.destroyed) return resolve();
        raw.end(resolve);
      }),
  };
}

/** Web transport: events into the caller's personal room (Socket.IO ping
 *  replaces the heartbeat; same-user devices all receive — own data). */
export function socketSink(io, userId, requestId) {
  const emit = (type, data = {}) => {
    io.to(`user:${userId}`).emit('ai:stream', { requestId, type, ...data });
  };
  return {
    start: () => emit('start'),
    text: (data) => emit('text', data),
    usage: (data) => emit('usage', data),
    done: (data) => {
      // requestId already rides on every envelope; don't double it.
      const rest = { ...data };
      delete rest.requestId;
      emit('done', rest);
    },
    error: (data) => emit('error', data),
  };
}
