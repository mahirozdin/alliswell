import { CaldavError } from './client.js';
import { bodies, hrefOf, isCalendarCollection, supportedComponents, textOf } from './xml.js';

/**
 * CalDAV discovery (CALDAV.md §4.1, RFC 4791 §6 / RFC 6764): principal →
 * calendar home → the calendars in it. Run on connect BEFORE anything is
 * stored (CALDAV.md §3.5: never keep a credential we have not proven works),
 * and again when a stored home stops answering — iCloud's per-account
 * partition host is persisted, not hardcoded, and it can move.
 */

/** Calendars this connector can mirror into: VEVENT collections. */
function calendarsIn(multistatus, homeUrl) {
  const home = new URL(homeUrl);
  const calendars = [];
  for (const entry of multistatus.responses) {
    const url = new URL(entry.href, home);
    if (url.pathname === home.pathname) continue;
    if (!isCalendarCollection(entry.props)) continue;
    const components = supportedComponents(entry.props);
    // No component set = every component type (RFC 4791 §5.2.3).
    if (components && !components.includes('VEVENT')) continue;
    const path = url.pathname.endsWith('/') ? url.pathname : `${url.pathname}/`;
    const name = textOf(entry.props.displayname)?.trim();
    const color = textOf(entry.props['calendar-color'])?.trim() || null;
    calendars.push({
      url: path,
      name: name || decodeURIComponent(path.split('/').filter(Boolean).pop() ?? path),
      color: color && /^#[0-9a-f]{6,8}$/i.test(color) ? color.slice(0, 7) : null,
    });
  }
  return calendars;
}

/** PROPFIND Depth 1 on a calendar home → its VEVENT calendars. */
export async function listCalendarsAt(client, homeUrl) {
  const listed = await client.propfind(homeUrl, 1, bodies.calendarList());
  return calendarsIn(listed, homeUrl);
}

async function principalFrom(client, startUrl) {
  const res = await client.propfind(startUrl, 0, bodies.currentUserPrincipal());
  for (const entry of res.responses) {
    const href = hrefOf(entry.props['current-user-principal']);
    if (href) return new URL(href, res.url).href;
  }
  return null;
}

/** A PROPFIND that answered with something other than 207 — try the next door. */
const tolerable = (err) => err instanceof CaldavError && err.code === 'CALDAV_REQUEST_FAILED';

/**
 * @param {ReturnType<import('./client.js').createCaldavClient>} client
 * @param {{ startUrl: string }} input  the iCloud URL, or what the user typed
 * @returns {Promise<{ principalUrl: string, homeUrl: string,
 *                     calendars: {url: string, name: string, color: string|null}[] }>}
 */
export async function discover(client, { startUrl }) {
  const start = new URL(startUrl);
  const wellKnown = new URL('/.well-known/caldav', start).href;
  // A bare host → RFC 6764 well-known first. A path the user typed (a
  // Nextcloud `/remote.php/dav`) → that path first, well-known as the fallback.
  const candidates =
    start.pathname === '/' || start.pathname === ''
      ? [wellKnown, start.href]
      : [start.href, wellKnown];

  let principalUrl = null;
  for (const candidate of candidates) {
    try {
      principalUrl = await principalFrom(client, candidate);
    } catch (err) {
      if (!tolerable(err)) throw err;
    }
    if (principalUrl) break;
  }
  if (!principalUrl) {
    throw new CaldavError('That address does not answer like a CalDAV server', {
      code: 'CALDAV_NOT_CALDAV',
    });
  }

  let homeUrl = null;
  try {
    const res = await client.propfind(principalUrl, 0, bodies.calendarHomeSet());
    for (const entry of res.responses) {
      const href = hrefOf(entry.props['calendar-home-set']);
      if (href) {
        homeUrl = new URL(href, res.url).href;
        break;
      }
    }
  } catch (err) {
    if (!tolerable(err)) throw err;
  }
  if (!homeUrl) {
    throw new CaldavError('The server has no calendar home for this account', {
      code: 'CALDAV_NOT_CALDAV',
    });
  }

  const calendars = await listCalendarsAt(client, homeUrl);
  if (calendars.length === 0) {
    throw new CaldavError('The account has no calendar that can hold events', {
      code: 'CALDAV_NO_CALENDARS',
    });
  }
  return { principalUrl, homeUrl, calendars };
}
