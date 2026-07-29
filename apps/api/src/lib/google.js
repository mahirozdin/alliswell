/**
 * Thin Google OAuth2 + Calendar v3 client (OPH-070…073). No SDK: the surface
 * we need is five endpoints, and configurable base URLs let tests run against
 * an in-process fake Google (`test/helpers/fakegoogle.js`).
 *
 * Every method throws GoogleApiError on non-2xx so callers can branch on
 * status (404 → recreate/re-link, 401 → refresh, 410 → full resync later).
 */

export const GOOGLE_CALENDAR_SCOPE = 'openid email https://www.googleapis.com/auth/calendar';

export class GoogleApiError extends Error {
  constructor(status, body, message) {
    super(message ?? `Google API error ${status}`);
    this.name = 'GoogleApiError';
    this.status = status;
    this.body = body;
  }
}

/**
 * Outbound throttle (OPH-210, ADR-0021 §5).
 *
 * Round 12 made EVERY task mirror, and one recurring series can own ~366 of
 * them — so the first large backfill would have walked straight into Google's
 * quota with nothing but BullMQ's five retries behind it. Two mechanisms, both
 * deliberately small:
 *
 * 1. a concurrency gate, so a backfill cannot open fifty sockets at once;
 * 2. 429/5xx retries that OBEY `Retry-After` when Google sends one and fall
 *    back to exponential backoff (with jitter) when it does not.
 *
 * A process-wide gate is the right scope here: quota is per project, not per
 * job, and every caller in this file shares the same credentials.
 */
const MAX_CONCURRENT = 6;
const MAX_ATTEMPTS = 4;
const BASE_BACKOFF_MS = 500;
const RETRY_STATUSES = new Set([429, 500, 502, 503, 504]);

let inFlight = 0;
const waiting = [];

function acquire() {
  if (inFlight < MAX_CONCURRENT) {
    inFlight += 1;
    return Promise.resolve();
  }
  return new Promise((resolve) => waiting.push(resolve));
}

function release() {
  const next = waiting.shift();
  if (next) {
    next();
    return;
  }
  inFlight -= 1;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** `Retry-After` is seconds or an HTTP date; both are worth obeying. */
function retryAfterMs(header, attempt) {
  if (header) {
    const seconds = Number(header);
    if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, 60000);
    const when = Date.parse(header);
    if (!Number.isNaN(when)) return Math.max(0, Math.min(when - Date.now(), 60000));
  }
  // Full jitter: a fleet of retries that all wake together is a second spike.
  return Math.round(BASE_BACKOFF_MS * 2 ** attempt * (0.5 + Math.random() / 2));
}

async function request(url, options) {
  await acquire();
  try {
    for (let attempt = 0; ; attempt += 1) {
      const res = await fetch(url, options);
      if (RETRY_STATUSES.has(res.status) && attempt < MAX_ATTEMPTS - 1) {
        await res.text().catch(() => null); // drain, so the socket is reusable
        await sleep(retryAfterMs(res.headers?.get?.('retry-after'), attempt));
        continue;
      }
      if (res.status === 204) return null;
      const text = await res.text();
      const body = text ? JSON.parse(text) : null;
      if (!res.ok) throw new GoogleApiError(res.status, body);
      return body;
    }
  } finally {
    release();
  }
}

const form = (fields) => new URLSearchParams(fields).toString();

/** Decodes a JWT payload WITHOUT verification — only ever used on id_tokens
 * received directly from Google's token endpoint over TLS (ADR-0006). */
export function decodeJwtPayload(jwt) {
  const payload = String(jwt).split('.')[1];
  if (!payload) throw new Error('Malformed JWT');
  return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
}

export class GoogleClient {
  /** @param {{ clientId: string, clientSecret: string, redirectUri: string,
   *            authBaseUrl: string, tokenBaseUrl: string, apiBaseUrl: string }} config */
  constructor(config) {
    this.config = config;
  }

  buildAuthUrl(state) {
    const params = new URLSearchParams({
      client_id: this.config.clientId,
      redirect_uri: this.config.redirectUri,
      response_type: 'code',
      scope: GOOGLE_CALENDAR_SCOPE,
      access_type: 'offline', // refresh token — the whole point (§7.2)
      prompt: 'consent', // re-consent re-issues the refresh token
      state,
    });
    return `${this.config.authBaseUrl}/o/oauth2/v2/auth?${params}`;
  }

  exchangeCode(code) {
    return request(`${this.config.tokenBaseUrl}/token`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: form({
        code,
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        redirect_uri: this.config.redirectUri,
        grant_type: 'authorization_code',
      }),
    });
  }

  refreshAccessToken(refreshToken) {
    return request(`${this.config.tokenBaseUrl}/token`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: form({
        refresh_token: refreshToken,
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        grant_type: 'refresh_token',
      }),
    });
  }

  /** Best effort — a dead token must never block a disconnect. */
  async revokeToken(token) {
    try {
      await request(`${this.config.tokenBaseUrl}/revoke`, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: form({ token }),
      });
    } catch {
      /* already revoked/expired — fine */
    }
  }

  #calendarUrl(path) {
    return `${this.config.apiBaseUrl}/calendar/v3${path}`;
  }

  #authorized(accessToken, extra = {}) {
    return {
      ...extra,
      headers: {
        authorization: `Bearer ${accessToken}`,
        // Only claim JSON when we actually send a body — strict servers
        // reject an empty body under a JSON content-type (DELETE!).
        ...(extra.body ? { 'content-type': 'application/json' } : {}),
        ...extra.headers,
      },
    };
  }

  listCalendars(accessToken) {
    return request(this.#calendarUrl('/users/me/calendarList'), this.#authorized(accessToken));
  }

  insertEvent(accessToken, calendarId, event) {
    return request(
      this.#calendarUrl(`/calendars/${encodeURIComponent(calendarId)}/events`),
      this.#authorized(accessToken, { method: 'POST', body: JSON.stringify(event) }),
    );
  }

  patchEvent(accessToken, calendarId, eventId, event) {
    return request(
      this.#calendarUrl(
        `/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
      ),
      this.#authorized(accessToken, { method: 'PATCH', body: JSON.stringify(event) }),
    );
  }

  deleteEvent(accessToken, calendarId, eventId) {
    return request(
      this.#calendarUrl(
        `/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
      ),
      this.#authorized(accessToken, { method: 'DELETE' }),
    );
  }

  /** Duplicate detection (OPH-073): find events already carrying our task id. */
  findEventsByTaskId(accessToken, calendarId, taskId) {
    const params = new URLSearchParams({
      privateExtendedProperty: `alliswell_task_id=${taskId}`,
      showDeleted: 'false',
      maxResults: '5',
    });
    return request(
      this.#calendarUrl(`/calendars/${encodeURIComponent(calendarId)}/events?${params}`),
      this.#authorized(accessToken),
    );
  }

  /**
   * One page of a sync feed (OPH-075). `syncToken` makes it incremental — an
   * expired one answers 410, which the worker turns into a full resync. Every
   * page of a sync MUST carry the same filters as the first request (Google's
   * rule), hence the fixed `showDeleted`.
   *
   * `singleEvents` picks WHICH feed (ADR-0008 §3): false expands nothing and
   * shows recurrence masters — what the task mirror needs to spot a series;
   * true expands recurring events into instances — what a calendar grid needs.
   * The two cannot share a cursor, which is why they are separate syncs.
   * `timeMin`/`timeMax` are deliberately absent: Google forbids them alongside
   * a syncToken, so windowing happens when storing instead.
   *
   * @param {{ syncToken?: string|null, pageToken?: string|null, singleEvents?: boolean }} cursor
   */
  listEvents(accessToken, calendarId, { syncToken, pageToken, singleEvents } = {}) {
    const params = new URLSearchParams({ showDeleted: 'true', maxResults: '250' });
    if (singleEvents) params.set('singleEvents', 'true');
    if (syncToken) params.set('syncToken', syncToken);
    if (pageToken) params.set('pageToken', pageToken);
    return request(
      this.#calendarUrl(`/calendars/${encodeURIComponent(calendarId)}/events?${params}`),
      this.#authorized(accessToken),
    );
  }

  /**
   * Opens a push channel on a calendar (OPH-074, §7.2 step 6). `address` must
   * be public HTTPS with a certificate Google trusts; `token` comes back to us
   * in every notification's `X-Goog-Channel-Token`. The requested ttl is a
   * ceiling request — the response's `expiration` (unix ms) is the truth.
   *
   * @returns {Promise<{ id: string, resourceId: string, expiration?: string }>}
   */
  watchEvents(accessToken, calendarId, { channelId, address, token, ttlSeconds }) {
    return request(
      this.#calendarUrl(`/calendars/${encodeURIComponent(calendarId)}/events/watch`),
      this.#authorized(accessToken, {
        method: 'POST',
        body: JSON.stringify({
          id: channelId,
          type: 'web_hook',
          address,
          token,
          params: { ttl: String(ttlSeconds) },
        }),
      }),
    );
  }

  /** Closes a push channel. Best effort — an already-dead channel is fine. */
  async stopChannel(accessToken, { channelId, resourceId }) {
    try {
      await request(
        this.#calendarUrl('/channels/stop'),
        this.#authorized(accessToken, {
          method: 'POST',
          body: JSON.stringify({ id: channelId, resourceId }),
        }),
      );
    } catch (err) {
      if (err?.status !== 404 && err?.status !== 400) throw err;
    }
  }
}
