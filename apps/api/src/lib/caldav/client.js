import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import { guardedLookup, isBlockedAddress } from '../net-guard.js';
import { bodies, parseDavError, parseMultistatus, textOf } from './xml.js';

/**
 * The CalDAV transport (OPH-380, CALDAV.md §4, ADR-0059): PROPFIND / REPORT /
 * GET / PUT / DELETE over node:http(s) — hand-rolled rather than `fetch`
 * because `fetch` cannot take the connect-time DNS guard (`net-guard.js`), and
 * the URL this talks to is one a user typed.
 *
 * The fences, all of them per request AND per redirect hop:
 *
 * 1. **Scheme** — https only, unless the admin set `CALDAV_ALLOW_PRIVATE_HOSTS`.
 * 2. **Host policy** — iCloud: `caldav.icloud.com` (or the configured iCloud
 *    URL) and the per-account partition hosts `pNN-caldav.icloud.com`;
 *    generic: the host the user typed. The Basic credential is therefore
 *    never sent to any other host — a redirect off the host is refused, not
 *    followed without auth.
 * 3. **Address** — every resolved address checked against the private and
 *    reserved ranges at connect time (and IP literals directly), unless
 *    `CALDAV_ALLOW_PRIVATE_HOSTS`.
 * 4. **Budget** — a timeout, a 10 MB response ceiling, at most 2 requests in
 *    flight per host, and 429/503 retried while OBEYING `Retry-After`
 *    (CALDAV.md §7.2: Apple publishes no limits, so assume they exist).
 */

export const MAX_RESPONSE_BYTES = 10 * 1024 * 1024;
const MAX_REDIRECTS = 5;
const MAX_ATTEMPTS = 4;
const BASE_BACKOFF_MS = 500;
const RETRY_STATUSES = new Set([429, 503]);
const PER_HOST_CONCURRENCY = 2;
const ICLOUD_PARTITION = /^p\d+-caldav\.icloud\.com$/i;
/** sync-collection pages (507 = "truncated, ask again with the new token"). */
const MAX_SYNC_PAGES = 50;
/** hrefs per calendar-multiget. */
export const MULTIGET_BATCH = 50;

export class CaldavError extends Error {
  /**
   * @param {string} message never carries a URL with credentials
   * @param {{ status?: number|null, code: string, davError?: string|null }} details
   */
  constructor(message, { status = null, code, davError = null }) {
    super(message);
    this.name = 'CaldavError';
    this.status = status;
    this.code = code;
    this.davError = davError;
  }
}

// ── Host policy ────────────────────────────────────────────────────────────

/**
 * Which hosts an account's requests may reach.
 *
 * @param {{ kind: 'icloud'|'generic', serverUrl?: string, icloudUrl: string }} input
 * @returns {(url: URL) => boolean}
 */
export function hostPolicy({ kind, serverUrl, icloudUrl }) {
  if (kind === 'icloud') {
    const home = new URL(icloudUrl).host.toLowerCase();
    return (url) => url.host.toLowerCase() === home || ICLOUD_PARTITION.test(url.hostname);
  }
  const allowed = new URL(serverUrl).hostname.toLowerCase();
  return (url) => url.hostname.toLowerCase() === allowed;
}

// ── Concurrency, per host ──────────────────────────────────────────────────

const gates = new Map(); // host → { inFlight, waiting[] }

async function acquire(host) {
  let gate = gates.get(host);
  if (!gate) {
    gate = { inFlight: 0, waiting: [] };
    gates.set(host, gate);
  }
  if (gate.inFlight < PER_HOST_CONCURRENCY) {
    gate.inFlight += 1;
    return;
  }
  await new Promise((resolve) => gate.waiting.push(resolve));
}

function release(host) {
  const gate = gates.get(host);
  if (!gate) return;
  const next = gate.waiting.shift();
  if (next) {
    next();
    return;
  }
  gate.inFlight -= 1;
  if (gate.inFlight === 0) gates.delete(host);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** `Retry-After` is seconds or an HTTP date; both are worth obeying (cap 60 s). */
export function retryAfterMs(header, attempt) {
  if (header != null && header !== '') {
    const seconds = Number(header);
    if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, 60000);
    const when = Date.parse(header);
    if (!Number.isNaN(when)) return Math.max(0, Math.min(when - Date.now(), 60000));
  }
  // Full jitter: a fleet of retries that all wake together is a second spike.
  return Math.round(BASE_BACKOFF_MS * 2 ** attempt * (0.5 + Math.random() / 2));
}

const blockedLookup = guardedLookup('CALDAV_BLOCKED_ADDRESS');

// ── One HTTP exchange ──────────────────────────────────────────────────────

function exchange(url, { method, headers, body, timeoutMs, allowPrivateHosts }) {
  return new Promise((resolve, reject) => {
    const transport = url.protocol === 'https:' ? https : http;
    const payload = body == null ? null : Buffer.from(body, 'utf8');
    const request = transport.request(
      url,
      {
        method,
        headers: {
          ...headers,
          ...(payload ? { 'content-length': String(payload.length) } : {}),
        },
        timeout: timeoutMs,
        ...(allowPrivateHosts ? {} : { lookup: blockedLookup }),
      },
      (response) => {
        const chunks = [];
        let size = 0;
        response.on('data', (chunk) => {
          size += chunk.length;
          if (size > MAX_RESPONSE_BYTES) {
            request.destroy();
            reject(
              new CaldavError('CalDAV response is larger than 10 MB', {
                code: 'CALDAV_RESPONSE_TOO_LARGE',
              }),
            );
            return;
          }
          chunks.push(chunk);
        });
        response.on('end', () => {
          if (size > MAX_RESPONSE_BYTES) return;
          resolve({
            status: response.statusCode,
            headers: response.headers,
            text: Buffer.concat(chunks).toString('utf8'),
          });
        });
        response.on('error', (err) =>
          reject(
            new CaldavError(`CalDAV response failed: ${err.code ?? 'error'}`, {
              code: 'CALDAV_UNREACHABLE',
            }),
          ),
        );
      },
    );
    request.on('timeout', () => {
      request.destroy(Object.assign(new Error('timeout'), { code: 'CALDAV_TIMEOUT' }));
    });
    request.on('error', (err) => {
      if (err?.code === 'CALDAV_BLOCKED_ADDRESS') {
        reject(
          new CaldavError('The CalDAV server resolves to a private address', {
            code: 'CALDAV_BLOCKED_ADDRESS',
          }),
        );
        return;
      }
      reject(
        new CaldavError(`CalDAV server unreachable (${err?.code ?? 'error'})`, {
          code: 'CALDAV_UNREACHABLE',
        }),
      );
    });
    if (payload) request.write(payload);
    request.end();
  });
}

// ── The client ─────────────────────────────────────────────────────────────

/**
 * @param {{
 *   kind: 'icloud'|'generic',
 *   serverUrl?: string,      // generic: what the user typed (the host policy's anchor)
 *   username: string,
 *   password: string,
 *   config: { allowPrivateHosts: boolean, icloudUrl: string, timeoutMs: number },
 * }} options
 */
export function createCaldavClient({ kind, serverUrl, username, password, config }) {
  const allowed = hostPolicy({ kind, serverUrl, icloudUrl: config.icloudUrl });
  const authorization = `Basic ${Buffer.from(`${username}:${password}`, 'utf8').toString('base64')}`;

  /** Throws unless `url` may be contacted with this account's credential. */
  function vet(url) {
    if (url.username || url.password) {
      throw new CaldavError('CalDAV URLs may not carry credentials', {
        code: 'CALDAV_BLOCKED_ADDRESS',
      });
    }
    if (url.protocol !== 'https:' && !(config.allowPrivateHosts && url.protocol === 'http:')) {
      throw new CaldavError('CalDAV needs an https:// address', {
        code: 'CALDAV_BLOCKED_ADDRESS',
      });
    }
    if (!allowed(url)) {
      throw new CaldavError('CalDAV server redirected to another host', {
        code: 'CALDAV_REDIRECT_OFF_HOST',
      });
    }
    const literal = url.hostname.replace(/^\[|\]$/g, '');
    if (!config.allowPrivateHosts && net.isIP(literal) !== 0 && isBlockedAddress(literal)) {
      throw new CaldavError('The CalDAV server is a private address', {
        code: 'CALDAV_BLOCKED_ADDRESS',
      });
    }
  }

  /**
   * One request, following same-policy redirects and retrying 429/503.
   * Resolves `{ status, headers, text, url }` for every status except 401,
   * which throws `CALDAV_AUTH_FAILED` (the one answer every caller treats the
   * same way: the password is wrong or revoked).
   */
  async function request(method, target, { headers = {}, body = null, depth = null } = {}) {
    let url = new URL(target);
    for (let hop = 0; hop <= MAX_REDIRECTS; hop += 1) {
      vet(url);
      const host = url.host;
      let res;
      await acquire(host);
      try {
        for (let attempt = 0; ; attempt += 1) {
          res = await exchange(url, {
            method,
            headers: {
              authorization,
              'user-agent': 'AllisWell-CalDAV/1',
              ...(body != null ? { 'content-type': 'application/xml; charset=utf-8' } : {}),
              ...(depth != null ? { depth: String(depth) } : {}),
              ...headers,
            },
            body,
            timeoutMs: config.timeoutMs,
            allowPrivateHosts: config.allowPrivateHosts,
          });
          if (RETRY_STATUSES.has(res.status) && attempt < MAX_ATTEMPTS - 1) {
            await sleep(retryAfterMs(res.headers['retry-after'], attempt));
            continue;
          }
          break;
        }
      } finally {
        release(host);
      }
      if ([301, 302, 303, 307, 308].includes(res.status) && res.headers.location) {
        url = new URL(res.headers.location, url);
        continue;
      }
      if (res.status === 401) {
        throw new CaldavError('CalDAV server rejected the credentials', {
          status: 401,
          code: 'CALDAV_AUTH_FAILED',
        });
      }
      return { ...res, url: url.href };
    }
    throw new CaldavError('Too many CalDAV redirects', { code: 'CALDAV_UNREACHABLE' });
  }

  const failed = (res, what) =>
    new CaldavError(`CalDAV ${what} answered ${res.status}`, {
      status: res.status,
      code: 'CALDAV_REQUEST_FAILED',
      davError: parseDavError(res.text),
    });

  async function propfind(url, depth, body) {
    const res = await request('PROPFIND', url, { body, depth });
    if (res.status !== 207) throw failed(res, 'PROPFIND');
    const parsed = parseMultistatus(res.text);
    if (!parsed) throw failed(res, 'PROPFIND');
    return { ...parsed, url: res.url };
  }

  /**
   * RFC 6578 sync-collection, all pages. `changed` members carry their etag;
   * `removed` ones answered 404 (the CalDAV spelling of Google's cancelled).
   * A sync-token rejection throws with `davError` set — callers decide.
   */
  async function syncCollection(calendarUrl, token) {
    const changed = new Map();
    const removed = new Set();
    let cursor = token ?? '';
    for (let page = 0; page < MAX_SYNC_PAGES; page += 1) {
      const res = await request('REPORT', calendarUrl, {
        body: bodies.syncCollection(cursor),
        depth: 0,
      });
      if (res.status !== 207) throw failed(res, 'sync-collection');
      const parsed = parseMultistatus(res.text);
      if (!parsed) throw failed(res, 'sync-collection');
      const self = new URL(calendarUrl).pathname;
      let truncated = false;
      for (const entry of parsed.responses) {
        const path = new URL(entry.href, calendarUrl).pathname;
        if (path === self || path === `${self}/` || `${path}/` === self) {
          // RFC 6578 §3.6: the request-URI itself answering 507 = more pages.
          if (entry.status === 507) truncated = true;
          continue;
        }
        if (entry.status === 404) {
          removed.add(path);
          changed.delete(path);
        } else {
          changed.set(path, textOf(entry.props.getetag));
          removed.delete(path);
        }
      }
      cursor = parsed.syncToken ?? cursor;
      if (!truncated) break;
    }
    return {
      changed: [...changed].map(([href, etag]) => ({ href, etag })),
      removed: [...removed],
      token: cursor || null,
    };
  }

  /** calendar-multiget in batches → `[{ href, etag, ics }]` (absent ones skipped). */
  async function multiget(calendarUrl, hrefs) {
    const out = [];
    for (let i = 0; i < hrefs.length; i += MULTIGET_BATCH) {
      const batch = hrefs.slice(i, i + MULTIGET_BATCH);
      const res = await request('REPORT', calendarUrl, {
        body: bodies.multiget(batch),
        depth: 1,
      });
      if (res.status !== 207) throw failed(res, 'calendar-multiget');
      const parsed = parseMultistatus(res.text);
      if (!parsed) throw failed(res, 'calendar-multiget');
      for (const entry of parsed.responses) {
        const ics = textOf(entry.props['calendar-data']);
        if (!ics || entry.status === 404) continue;
        out.push({
          href: new URL(entry.href, calendarUrl).pathname,
          etag: textOf(entry.props.getetag),
          ics,
        });
      }
    }
    return out;
  }

  /** GET one resource → `{ ics, etag }`, or null when it is gone. */
  async function get(url) {
    const res = await request('GET', url, { headers: { accept: 'text/calendar' } });
    if (res.status === 404 || res.status === 410) return null;
    if (res.status !== 200) throw failed(res, 'GET');
    return { ics: res.text, etag: res.headers.etag ?? null };
  }

  /** The etag of one resource, via PROPFIND (servers may omit ETag on PUT). */
  async function etagOf(url) {
    const res = await propfind(url, 0, bodies.getetag());
    return textOf(res.responses[0]?.props?.getetag) ?? null;
  }

  /**
   * PUT a whole VCALENDAR. `ifNoneMatch: '*'` creates only; `ifMatch` updates
   * only that version — a 412 throws with `status: 412` (the "someone else
   * wrote it" signal, CALDAV.md §4.3). Resolves the new etag.
   */
  async function put(url, ics, { ifMatch = null, ifNoneMatch = null } = {}) {
    const res = await request('PUT', url, {
      headers: {
        'content-type': 'text/calendar; charset=utf-8',
        ...(ifMatch ? { 'if-match': ifMatch } : {}),
        ...(ifNoneMatch ? { 'if-none-match': ifNoneMatch } : {}),
      },
      body: ics,
    });
    if (![200, 201, 204].includes(res.status)) throw failed(res, 'PUT');
    // An unknown etag breaks echo suppression (ADR-0007 §4) — ask for it.
    return res.headers.etag ?? (await etagOf(url));
  }

  /** DELETE, tolerating "already gone". A 412 throws (someone changed it). */
  async function remove(url, ifMatch = null) {
    const res = await request('DELETE', url, {
      headers: ifMatch ? { 'if-match': ifMatch } : {},
    });
    if (res.status === 404 || res.status === 410) return;
    if (![200, 202, 204].includes(res.status)) throw failed(res, 'DELETE');
  }

  return { request, propfind, syncCollection, multiget, get, put, delete: remove, etagOf };
}
