import Fastify from 'fastify';

/**
 * In-process Google (OAuth token endpoint + Calendar v3 slice) for tests —
 * the real client talks to it over HTTP because every base URL is
 * configurable. State is exposed for assertions.
 */
export async function startFakeGoogle() {
  const state = {
    issuedTokens: new Set(),
    refreshCalls: 0,
    exchangeCalls: 0,
    revoked: [],
    calendars: new Map(), // calendarId → Map(eventId → event)
    failRefresh: false,
    seq: 0,
    // Push channels (OPH-074): id → {id, resourceId, address, token, calendarId}
    channels: new Map(),
    stopped: [],
    watchCalls: 0,
    // Sync feed (OPH-075). The fake models Google's contract rather than its
    // storage: `changes` is the change log a syncToken indexes into, and
    // `expireSyncToken` forces the 410 → full-resync path.
    changes: [], // {calendarId, event}
    expireSyncToken: false,
  };

  const eventsIn = (calendarId) => {
    if (!state.calendars.has(calendarId)) state.calendars.set(calendarId, new Map());
    return state.calendars.get(calendarId);
  };
  state.eventsIn = eventsIn;

  // Real time: last-write-wins compares this against the task's updated_at, so
  // tests that care about the outcome pass `updated` explicitly instead.
  const stamp = () => new Date().toISOString();

  /** Records a change the way Google would surface it on the sync feed. */
  const logChange = (calendarId, event) => {
    state.changes.push({ calendarId, event });
  };
  state.logChange = logChange;

  /** Test-side helper: a foreign edit, as if the user dragged the event. */
  state.userEdits = (calendarId, eventId, patch) => {
    const events = eventsIn(calendarId);
    const existing = events.get(eventId);
    const updated = {
      ...existing,
      ...patch,
      etag: `"user-${(state.seq += 1)}"`,
      updated: patch.updated ?? stamp(),
    };
    events.set(eventId, updated);
    logChange(calendarId, updated);
    return updated;
  };

  /** Test-side helper: the user deletes the event in Google. */
  state.userDeletes = (calendarId, eventId) => {
    const events = eventsIn(calendarId);
    const existing = events.get(eventId);
    events.delete(eventId);
    logChange(calendarId, {
      id: eventId,
      status: 'cancelled',
      etag: `"cancel-${(state.seq += 1)}"`,
      updated: stamp(),
      extendedProperties: existing?.extendedProperties,
    });
  };

  const idToken = (payload) =>
    ['e30', Buffer.from(JSON.stringify(payload)).toString('base64url'), 'sig'].join('.');

  const app = Fastify({ logger: false });
  app.addContentTypeParser(
    'application/x-www-form-urlencoded',
    { parseAs: 'string' },
    (req, body, done) => done(null, Object.fromEntries(new URLSearchParams(body))),
  );

  app.post('/token', async (request, reply) => {
    const body = request.body ?? {};
    if (body.grant_type === 'authorization_code') {
      if (!body.code || body.code === 'bad-code') {
        return reply.code(400).send({ error: 'invalid_grant' });
      }
      state.exchangeCalls += 1;
      const accessToken = `at-${(state.seq += 1)}`;
      state.issuedTokens.add(accessToken);
      return {
        access_token: accessToken,
        refresh_token: 'rt-1',
        expires_in: 3600,
        scope: 'openid email https://www.googleapis.com/auth/calendar',
        id_token: idToken({ email: 'takvim@example.com', sub: 'google-sub-1' }),
      };
    }
    if (body.grant_type === 'refresh_token') {
      state.refreshCalls += 1;
      if (state.failRefresh || body.refresh_token !== 'rt-1') {
        return reply.code(400).send({ error: 'invalid_grant' });
      }
      const accessToken = `at-${(state.seq += 1)}`;
      state.issuedTokens.add(accessToken);
      return { access_token: accessToken, expires_in: 3600 };
    }
    return reply.code(400).send({ error: 'unsupported_grant_type' });
  });

  app.post('/revoke', async (request) => {
    state.revoked.push(request.body?.token);
    return {};
  });

  const requireAuth = (request, reply) => {
    const token = String(request.headers.authorization ?? '').replace('Bearer ', '');
    if (!state.issuedTokens.has(token)) {
      reply.code(401).send({ error: { code: 401 } });
      return false;
    }
    return true;
  };

  app.get('/calendar/v3/users/me/calendarList', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    return {
      items: [
        { id: 'primary', summary: 'Ana Takvim', primary: true },
        { id: 'is-takvimi', summary: 'İş' },
      ],
    };
  });

  app.get('/calendar/v3/calendars/:calendarId/events', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const { calendarId } = request.params;

    // OPH-073 duplicate detection: a filtered lookup, not a sync pass.
    const wanted = request.query.privateExtendedProperty; // alliswell_task_id=X
    if (wanted) {
      const [key, value] = String(wanted).split('=');
      return {
        items: [...eventsIn(calendarId).values()].filter(
          (e) => e.extendedProperties?.private?.[key] === value,
        ),
      };
    }

    const syncToken = request.query.syncToken ?? null;
    if (syncToken && state.expireSyncToken) {
      return reply.code(410).send({
        error: {
          code: 410,
          message: 'Sync token is no longer valid',
          errors: [{ reason: 'fullSyncRequired' }],
        },
      });
    }

    // With a token: everything logged since it was issued (cancellations
    // included, as Google guarantees). Without: the calendar as it stands.
    const all = syncToken
      ? state.changes
          .slice(Number(String(syncToken).replace('sync-', '')))
          .filter((c) => c.calendarId === calendarId)
          .map((c) => c.event)
      : [...eventsIn(calendarId).values()];

    const pageSize = state.pageSize ?? Math.max(all.length, 1);
    const from = request.query.pageToken ? Number(request.query.pageToken) : 0;
    const to = from + pageSize;
    return {
      items: all.slice(from, to),
      // nextSyncToken rides on the LAST page only — the client must paginate
      // to the end before it may store a cursor.
      ...(to >= all.length
        ? { nextSyncToken: `sync-${state.changes.length}` }
        : { nextPageToken: String(to) }),
    };
  });

  app.post('/calendar/v3/calendars/:calendarId/events', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const id = `ev-${(state.seq += 1)}`;
    const event = {
      ...request.body,
      id,
      etag: `"e${state.seq}"`,
      iCalUID: `${id}@fake.google`,
      updated: stamp(),
    };
    eventsIn(request.params.calendarId).set(id, event);
    logChange(request.params.calendarId, event);
    return reply.code(200).send(event);
  });

  app.patch('/calendar/v3/calendars/:calendarId/events/:eventId', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const events = eventsIn(request.params.calendarId);
    const existing = events.get(request.params.eventId);
    if (!existing) return reply.code(404).send({ error: { code: 404 } });
    const updated = {
      ...existing,
      ...request.body,
      etag: `"e${(state.seq += 1)}"`,
      updated: stamp(),
    };
    events.set(request.params.eventId, updated);
    logChange(request.params.calendarId, updated);
    return updated;
  });

  app.delete('/calendar/v3/calendars/:calendarId/events/:eventId', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const events = eventsIn(request.params.calendarId);
    const existing = events.get(request.params.eventId);
    const removed = events.delete(request.params.eventId);
    if (removed) {
      logChange(request.params.calendarId, {
        id: request.params.eventId,
        status: 'cancelled',
        etag: `"d${(state.seq += 1)}"`,
        updated: stamp(),
        extendedProperties: existing?.extendedProperties,
      });
    }
    return reply.code(removed ? 204 : 404).send();
  });

  // ── Push channels (OPH-074) ──────────────────────────────────────────────

  app.post('/calendar/v3/calendars/:calendarId/events/watch', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    state.watchCalls += 1;
    const { id, address, token, params } = request.body ?? {};
    const resourceId = `res-${(state.seq += 1)}`;
    state.channels.set(id, {
      id,
      resourceId,
      address,
      token,
      calendarId: request.params.calendarId,
    });
    return {
      kind: 'api#channel',
      id,
      resourceId,
      token,
      // Google answers with the real expiration, capped at its own limit —
      // the client must renew off THIS, not off what it asked for.
      expiration: String(Date.now() + Math.min(Number(params?.ttl ?? 604800), 604800) * 1000),
    };
  });

  app.post('/calendar/v3/channels/stop', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const { id, resourceId } = request.body ?? {};
    const channel = state.channels.get(id);
    if (!channel || channel.resourceId !== resourceId) {
      return reply.code(404).send({ error: { code: 404 } });
    }
    state.channels.delete(id);
    state.stopped.push(id);
    return reply.code(204).send();
  });

  await app.listen({ port: 0, host: '127.0.0.1' });
  const url = `http://127.0.0.1:${app.server.address().port}`;
  return { app, url, state };
}

/**
 * A plausible public webhook address (OPH-074). Google demands https, and the
 * fake never calls it — tests inject the notification themselves, which is
 * exactly what Google's contract makes possible: the headers ARE the message.
 */
export const FAKE_WEBHOOK_URL = 'https://alliswell.test/api/v1/integrations/google/webhook';

/** Config env pointing every Google base URL at the fake. */
export function fakeGoogleEnv(url) {
  return {
    GOOGLE_CLIENT_ID: 'fake-client-id',
    GOOGLE_CLIENT_SECRET: 'fake-client-secret-value-long-enough',
    GOOGLE_REDIRECT_URI: 'http://localhost:3000/api/v1/integrations/google/callback',
    GOOGLE_AUTH_BASE_URL: url,
    GOOGLE_TOKEN_BASE_URL: url,
    GOOGLE_API_BASE_URL: url,
  };
}
