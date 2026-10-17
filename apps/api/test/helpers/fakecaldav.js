import http from 'node:http';

/**
 * In-process CalDAV server for unit tests (OPH-380, CALDAV.md §7.4) — models
 * the DOCUMENTED contract (RFC 4791 / 6578 / 4918) plus switches for the
 * iCloud quirks the connector must survive:
 *
 * - the calendar home on a "partition" path different from the principal's
 *   (`homePath`), discovered rather than assumed;
 * - a PUT that answers without an ETag (`omitEtagOnPut`);
 * - a sync-token rejection answered `403 <valid-sync-token/>` (Radicale and
 *   iCloud never send Google's 410);
 * - `429 Retry-After: 0` (`throttleNext`);
 * - a redirect off the host (`redirectOffHost`).
 *
 * The "user" edits through `userPut` / `userDelete`, which bump the etag and
 * the sync log exactly as a phone would. Every request is recorded, with the
 * Authorization header it carried, so tests can prove where a credential went.
 */
export async function startFakeCaldav({
  username = 'alice@example.com',
  password = 'abcd-efgh-ijkl-mnop',
  homePath = '/1234/calendars/',
  calendars = [
    { path: '/1234/calendars/home/', name: 'Home', components: ['VEVENT'] },
    { path: '/1234/calendars/tasks/', name: 'Reminders', components: ['VTODO'] },
  ],
} = {}) {
  const state = {
    username,
    password,
    homePath,
    principalPath: '/1234/principal/',
    calendars: new Map(),
    requests: [],
    omitEtagOnPut: false,
    throttleNext: 0,
    redirectOffHost: null,
    rejectAllTokens: false,
    pageSize: 0,
    seq: 0,
  };
  for (const c of calendars) {
    state.calendars.set(c.path, {
      ...c,
      resources: new Map(), // href → { ics, etag }
      log: [], // { href, deleted }
    });
  }

  const nextEtag = () => `"e${(state.seq += 1)}"`;
  const calendarOf = (href) => {
    for (const [path, calendar] of state.calendars) {
      if (href.startsWith(path) && href !== path) return calendar;
    }
    return null;
  };
  const record = (calendar, href, deleted = false) => calendar.log.push({ href, deleted });

  /** The "user" writes through their own client: new etag, new log entry. */
  state.userPut = (href, ics) => {
    const calendar = calendarOf(href);
    const etag = nextEtag();
    calendar.resources.set(href, { ics, etag });
    record(calendar, href);
    return etag;
  };
  state.userDelete = (href) => {
    const calendar = calendarOf(href);
    calendar.resources.delete(href);
    record(calendar, href, true);
  };
  state.resource = (href) => calendarOf(href)?.resources.get(href) ?? null;
  state.resourcesIn = (path) => state.calendars.get(path).resources;

  const multistatus = (inner) =>
    `<?xml version="1.0" encoding="utf-8"?>\n<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:CS="http://calendarserver.org/ns/" xmlns:A="http://apple.com/ns/ical/">${inner}</D:multistatus>`;
  const propResponse = (href, props) =>
    `<D:response><D:href>${href}</D:href><D:propstat><D:prop>${props}</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>`;
  const xmlEscape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      const url = new URL(req.url, 'http://fake');
      const path = url.pathname;
      state.requests.push({
        method: req.method,
        path,
        host: req.headers.host,
        authorization: req.headers.authorization ?? null,
        headers: req.headers,
        body,
      });
      const send = (status, text = '', headers = {}) => {
        res.writeHead(status, { 'content-type': 'application/xml; charset=utf-8', ...headers });
        res.end(text);
      };

      if (state.throttleNext > 0) {
        state.throttleNext -= 1;
        return send(429, '', { 'retry-after': '0' });
      }
      if (path === '/.well-known/caldav') {
        if (state.redirectOffHost) return send(301, '', { location: state.redirectOffHost });
        return send(301, '', { location: '/' });
      }
      const expected = `Basic ${Buffer.from(`${state.username}:${state.password}`).toString('base64')}`;
      if (req.headers.authorization !== expected) {
        return send(401, '', { 'www-authenticate': 'Basic realm="fake"' });
      }

      if (req.method === 'PROPFIND') {
        if (path === '/' || path === '') {
          return send(
            207,
            multistatus(
              propResponse(
                '/',
                `<D:current-user-principal><D:href>${state.principalPath}</D:href></D:current-user-principal>`,
              ),
            ),
          );
        }
        if (path === state.principalPath) {
          return send(
            207,
            multistatus(
              propResponse(
                path,
                `<C:calendar-home-set><D:href>${state.homePath}</D:href></C:calendar-home-set>`,
              ),
            ),
          );
        }
        if (path === state.homePath) {
          let inner = propResponse(path, '<D:resourcetype><D:collection/></D:resourcetype>');
          for (const [calPath, c] of state.calendars) {
            const comps = c.components.map((n) => `<C:comp name="${n}"/>`).join('');
            inner += propResponse(
              calPath,
              `<D:displayname>${xmlEscape(c.name)}</D:displayname>` +
                '<D:resourcetype><D:collection/><C:calendar/></D:resourcetype>' +
                `<C:supported-calendar-component-set>${comps}</C:supported-calendar-component-set>` +
                `<CS:getctag>${c.log.length}</CS:getctag><A:calendar-color>#FF2968FF</A:calendar-color>`,
            );
          }
          return send(207, multistatus(inner));
        }
        const resource = state.resource(path);
        if (resource) {
          return send(
            207,
            multistatus(propResponse(path, `<D:getetag>${resource.etag}</D:getetag>`)),
          );
        }
        return send(404);
      }

      if (req.method === 'REPORT') {
        const calendar = state.calendars.get(path);
        if (!calendar) return send(404);
        if (body.includes('sync-collection')) {
          const token = /<d:sync-token>([^<]*)<\/d:sync-token>/i.exec(body)?.[1] ?? '';
          let from = 0;
          if (token) {
            const match = /^http:\/\/fake\/sync\/(\d+)$/.exec(token);
            if (!match || Number(match[1]) > calendar.log.length || state.rejectAllTokens) {
              return send(
                403,
                '<?xml version="1.0"?><D:error xmlns:D="DAV:"><D:valid-sync-token/></D:error>',
              );
            }
            from = Number(match[1]);
          }
          let to = calendar.log.length;
          let truncated = false;
          if (state.pageSize && to - from > state.pageSize) {
            to = from + state.pageSize;
            truncated = true;
          }
          let inner = '';
          if (!token) {
            for (const [href, r] of calendar.resources) {
              inner += propResponse(href, `<D:getetag>${r.etag}</D:getetag>`);
            }
          } else {
            const latest = new Map();
            for (const entry of calendar.log.slice(from, to)) latest.set(entry.href, entry);
            for (const [href, entry] of latest) {
              const r = calendar.resources.get(href);
              if (entry.deleted || !r) {
                inner += `<D:response><D:href>${href}</D:href><D:status>HTTP/1.1 404 Not Found</D:status></D:response>`;
              } else {
                inner += propResponse(href, `<D:getetag>${r.etag}</D:getetag>`);
              }
            }
          }
          if (truncated) {
            inner += `<D:response><D:href>${path}</D:href><D:status>HTTP/1.1 507 Insufficient Storage</D:status></D:response>`;
          }
          inner += `<D:sync-token>http://fake/sync/${to}</D:sync-token>`;
          return send(207, multistatus(inner));
        }
        if (body.includes('calendar-multiget')) {
          state.multigets = (state.multigets ?? 0) + 1;
          const hrefs = [...body.matchAll(/<d:href>([^<]*)<\/d:href>/gi)].map((m) => m[1]);
          let inner = '';
          for (const href of hrefs) {
            const r = calendar.resources.get(href);
            if (!r) {
              inner += `<D:response><D:href>${href}</D:href><D:status>HTTP/1.1 404 Not Found</D:status></D:response>`;
              continue;
            }
            inner += propResponse(
              href,
              `<D:getetag>${r.etag}</D:getetag><C:calendar-data>${xmlEscape(r.ics).replace(/\r/g, '&#13;')}</C:calendar-data>`,
            );
          }
          return send(207, multistatus(inner));
        }
        return send(400);
      }

      if (req.method === 'GET') {
        const r = state.resource(path);
        if (!r) return send(404);
        res.writeHead(200, { 'content-type': 'text/calendar', etag: r.etag });
        return res.end(r.ics);
      }

      if (req.method === 'PUT') {
        const calendar = calendarOf(path);
        if (!calendar) return send(409);
        const current = calendar.resources.get(path);
        if (req.headers['if-none-match'] === '*' && current) return send(412);
        const ifMatch = req.headers['if-match'];
        if (ifMatch && ifMatch !== '*' && ifMatch !== current?.etag) return send(412);
        if (ifMatch && !current) return send(412);
        const etag = nextEtag();
        calendar.resources.set(path, { ics: body, etag });
        record(calendar, path);
        return send(current ? 204 : 201, '', state.omitEtagOnPut ? {} : { etag });
      }

      if (req.method === 'DELETE') {
        const calendar = calendarOf(path);
        const current = calendar?.resources.get(path);
        if (!current) return send(404);
        const ifMatch = req.headers['if-match'];
        if (ifMatch && ifMatch !== current.etag) return send(412);
        calendar.resources.delete(path);
        record(calendar, path, true);
        return send(204);
      }

      return send(405);
    });
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    url: `http://127.0.0.1:${port}`,
    state,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

/** Config env for an app that talks to the fake as if it were iCloud. */
export function fakeCaldavEnv(url) {
  return {
    CALDAV_ENABLED: 'true',
    CALDAV_ALLOW_PRIVATE_HOSTS: 'true',
    CALDAV_ICLOUD_URL: url,
  };
}
