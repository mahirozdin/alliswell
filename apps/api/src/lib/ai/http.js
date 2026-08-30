/**
 * Fetch for the five AI adapters (OPH-216, ADR-0019): AbortSignal plumbing,
 * streaming handshakes, and retry that never duplicates streamed text.
 *
 * Deliberately NOT a refactor of lib/google.js — its retry core is ~10 shared
 * lines, but google.js buffers whole bodies and has no abort path, and its
 * process-wide concurrency gate is right for ONE project credential and wrong
 * here (AI keys are per-user; a global gate would let one user starve the
 * rest — fairness lives in OPH-217's per-user bucket instead).
 */

const MAX_ATTEMPTS = 3;
const BASE_BACKOFF_MS = 400;
const RETRY_STATUSES = new Set([429, 500, 502, 503, 504]);

/**
 * Per-call handshake budgets. The default 15 s exists for verify-class calls;
 * a NON-streaming completion delivers its headers only when the whole
 * generation is done, so for extract the handshake IS the generation — a
 * reasoning-class model routinely needs more than 15 s, and the old default
 * turned that into three aborted attempts the user experienced as a ~50 s
 * hang ending in "provider unreachable" (found live on alliswell.space).
 * Streaming chat gets a smaller raise: providers send SSE headers early, but
 * queue time under load is real.
 */
export const CHAT_HANDSHAKE_TIMEOUT_MS = 30000;
export const EXTRACT_TIMEOUT_MS = 90000;
/**
 * Transcription is `extract`'s problem an order of magnitude larger: a
 * non-streaming call whose headers arrive only when the generation is done,
 * and the generation is an hour of speech. Ten minutes is a ceiling on ONE
 * attempt, not a promise about a file — a pipeline that must survive longer
 * recordings resumes rather than waits (the job runner's business).
 */
export const TRANSCRIBE_TIMEOUT_MS = 600000;

export class AiProviderError extends Error {
  /**
   * @param {'upstream_auth'|'upstream_rate_limited'|'upstream_error'|'bad_json'} code
   * @param {{status?: number, body?: unknown, rawText?: string, retryAfterMs?: number, message?: string}} [details]
   */
  constructor(
    code,
    { status = null, body = null, rawText = null, retryAfterMs = null, message } = {},
  ) {
    super(message ?? `AI provider error (${code}${status ? ` ${status}` : ''})`);
    this.name = 'AiProviderError';
    this.code = code;
    this.status = status;
    this.body = body;
    this.rawText = rawText;
    this.retryAfterMs = retryAfterMs;
  }
}

function sleep(ms, signal) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(done, ms);
    function done() {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }
    function onAbort() {
      clearTimeout(timer);
      reject(signal.reason ?? new Error('aborted'));
    }
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

/** `Retry-After` seconds or HTTP-date, capped at 60 s; else full jitter. */
function retryAfterMs(header, attempt) {
  if (header) {
    const seconds = Number(header);
    if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, 60000);
    const date = Date.parse(header);
    if (!Number.isNaN(date)) return Math.min(Math.max(date - Date.now(), 0), 60000);
  }
  const cap = BASE_BACKOFF_MS * 2 ** attempt;
  return Math.round(cap * (0.5 + Math.random() / 2));
}

function classifyStatus(status) {
  if (status === 401 || status === 403) return 'upstream_auth';
  if (status === 429) return 'upstream_rate_limited';
  return 'upstream_error';
}

/**
 * The provider's own human-readable failure line, if one exists — all five
 * dialects put it at `body.error.message` (OpenAI/Anthropic/Gemini) or
 * `body.error` (Ollama's plain string). Capped so it can ride a log line or an
 * SSE error frame; never contains user content, only the provider's verdict
 * ("You exceeded your current quota…", "model not found", …). Live debugging
 * on alliswell.space was blind without this — every failure collapsed into
 * "The AI provider failed".
 */
export function upstreamMessage(err) {
  if (err?.name !== 'AiProviderError') return null;
  const raw = err.body?.error?.message ?? err.body?.error ?? err.body?.message;
  if (typeof raw !== 'string' || raw.length === 0) return null;
  return raw.length > 240 ? `${raw.slice(0, 239)}…` : raw;
}

/**
 * @param {string} url
 * @param {{
 *   method?: string, headers?: Record<string, string>, json?: unknown,
 *   signal?: AbortSignal, stream?: boolean, timeoutMs?: number, maxAttempts?: number,
 * }} options
 * @returns {Promise<any>} parsed JSON body, or the raw Response when `stream`
 *
 * Retry policy: non-stream requests retry 429/5xx with Retry-After/jitter.
 * Stream requests retry ONLY the handshake (non-2xx before any body byte) —
 * a mid-stream retry would replay text the user already saw, so a broken
 * stream throws and the client resends.
 */
export async function aiFetch(
  url,
  {
    method = 'POST',
    headers = {},
    json,
    signal,
    stream = false,
    timeoutMs = 15000,
    maxAttempts = MAX_ATTEMPTS,
  } = {},
) {
  for (let attempt = 0; ; attempt += 1) {
    // The timeout guards the HANDSHAKE only: it is disarmed the moment headers
    // arrive, so a long-lived stream is governed by the caller's signal alone.
    const timeoutCtrl = new AbortController();
    const timer = setTimeout(() => timeoutCtrl.abort(new Error('AI upstream timeout')), timeoutMs);
    const combined = signal ? AbortSignal.any([signal, timeoutCtrl.signal]) : timeoutCtrl.signal;

    let res;
    try {
      res = await fetch(url, {
        method,
        headers: json === undefined ? headers : { 'content-type': 'application/json', ...headers },
        body: json === undefined ? undefined : JSON.stringify(json),
        signal: combined,
      });
    } catch (err) {
      clearTimeout(timer);
      if (signal?.aborted) throw signal.reason ?? err;
      if (attempt < maxAttempts - 1) {
        await sleep(retryAfterMs(null, attempt), signal);
        continue;
      }
      throw new AiProviderError('upstream_error', {
        message: `AI provider unreachable: ${err.message}`,
      });
    }
    clearTimeout(timer);

    if (RETRY_STATUSES.has(res.status) && attempt < maxAttempts - 1) {
      const header = res.headers?.get?.('retry-after');
      const drained = await res.text().catch(() => null); // drain so the socket is reusable
      // An out-of-credit 429 does not heal between attempts — retrying it just
      // stretches a clear "add billing" answer into a mute half-minute hang.
      if (res.status === 429 && drained && /insufficient_quota/i.test(drained)) {
        let body = null;
        try {
          body = JSON.parse(drained);
        } catch {
          body = null;
        }
        throw new AiProviderError('upstream_rate_limited', {
          status: res.status,
          body,
          rawText: drained,
        });
      }
      await sleep(retryAfterMs(header, attempt), signal);
      continue;
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      let body = null;
      try {
        body = text ? JSON.parse(text) : null;
      } catch {
        body = null;
      }
      const code = classifyStatus(res.status);
      throw new AiProviderError(code, {
        status: res.status,
        body,
        rawText: text || null,
        retryAfterMs:
          res.status === 429 ? retryAfterMs(res.headers?.get?.('retry-after'), attempt) : null,
      });
    }

    if (stream) return res;
    if (res.status === 204) return null;
    const text = await res.text();
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch {
      throw new AiProviderError('upstream_error', {
        status: res.status,
        rawText: text,
        message: 'AI provider answered with unparseable JSON',
      });
    }
  }
}
