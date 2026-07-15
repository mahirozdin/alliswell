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
  };

  const eventsIn = (calendarId) => {
    if (!state.calendars.has(calendarId)) state.calendars.set(calendarId, new Map());
    return state.calendars.get(calendarId);
  };
  state.eventsIn = eventsIn;

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
    const wanted = request.query.privateExtendedProperty; // alliswell_task_id=X
    let items = [...eventsIn(request.params.calendarId).values()];
    if (wanted) {
      const [key, value] = String(wanted).split('=');
      items = items.filter((e) => e.extendedProperties?.private?.[key] === value);
    }
    return { items };
  });

  app.post('/calendar/v3/calendars/:calendarId/events', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const id = `ev-${(state.seq += 1)}`;
    const event = { ...request.body, id, etag: `"e${state.seq}"`, iCalUID: `${id}@fake.google` };
    eventsIn(request.params.calendarId).set(id, event);
    return reply.code(200).send(event);
  });

  app.patch('/calendar/v3/calendars/:calendarId/events/:eventId', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const events = eventsIn(request.params.calendarId);
    const existing = events.get(request.params.eventId);
    if (!existing) return reply.code(404).send({ error: { code: 404 } });
    const updated = { ...existing, ...request.body, etag: `"e${(state.seq += 1)}"` };
    events.set(request.params.eventId, updated);
    return updated;
  });

  app.delete('/calendar/v3/calendars/:calendarId/events/:eventId', async (request, reply) => {
    if (!requireAuth(request, reply)) return reply;
    const removed = eventsIn(request.params.calendarId).delete(request.params.eventId);
    return reply.code(removed ? 204 : 404).send();
  });

  await app.listen({ port: 0, host: '127.0.0.1' });
  const url = `http://127.0.0.1:${app.server.address().port}`;
  return { app, url, state };
}

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
