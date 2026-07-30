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
      await res.text().catch(() => null); // drain so the socket is reusable
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
