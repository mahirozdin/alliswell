import crypto from 'node:crypto';
import ICAL from 'ical.js';
import { zonedWallTimeToUtc } from '../time.js';

/**
 * Tasks ⇄ iCalendar (RFC 5545) for the CalDAV connector (OPH-380, ADR-0059).
 * `ical.js` does the bug-farm parts — line folding, escaping, TZID and RRULE
 * expansion (CALDAV.md §6) — and this file decides what we write and how a
 * VEVENT becomes the provider-neutral event `lib/inbound.js` and
 * `lib/external-events.js` already understand (Google's spelling:
 * `{id, etag, updated, status, start: {dateTime|date}, end, recurrence}`).
 *
 * What we write is deliberately plain: times in UTC (no VTIMEZONE to get
 * wrong), the task id as UID, `URL:alliswell://task/<id>` (ADR-0003) and
 * `X-ALLISWELL-*` properties. Four ways back to the task, in order: the link
 * table, `X-ALLISWELL-TASK-ID`, the URL, the deterministic href
 * `alliswell-<taskId>.ics` — and finally the UID.
 */

export const PRODID = '-//AllisWell//CalDAV mirror//EN';
const ULID = /^[0-9A-HJKMNP-TV-Z]{26}$/;
const TASK_URL = /^alliswell:\/\/task\/([0-9A-HJKMNP-TV-Z]{26})$/;
const TASK_HREF = /(?:^|\/)alliswell-([0-9A-HJKMNP-TV-Z]{26})\.ics$/;
/** A runaway series must not run the sync out of memory (cap per resource). */
export const MAX_INSTANCES = 500;
const MAX_ITERATIONS = 20000;

/** The href a task's event lives at, inside a calendar collection path. */
export function hrefForTask(calendarPath, taskId) {
  const base = calendarPath.endsWith('/') ? calendarPath : `${calendarPath}/`;
  return `${base}alliswell-${taskId}.ics`;
}

/** The stable id of a foreign resource (or of one instance of it) we cache. */
export function externalIdFor(href, instanceKey = null) {
  const digest = crypto.createHash('sha1').update(href).digest('hex');
  return instanceKey ? `${digest}#${instanceKey}` : digest;
}

const utcTime = (date) => ICAL.Time.fromJSDate(new Date(date), true);

function setProp(vevent, name, value) {
  vevent.removeAllProperties(name);
  if (value == null) return;
  vevent.addPropertyWithValue(name, value);
}

/** Writes OUR fields onto a VEVENT; every other property is left alone. */
function applyBlock(vevent, block, now) {
  setProp(vevent, 'summary', block.title);
  setProp(vevent, 'description', block.description ?? null);
  setProp(vevent, 'dtstart', utcTime(block.start));
  vevent.removeAllProperties('duration');
  setProp(vevent, 'dtend', utcTime(block.end));
  setProp(vevent, 'url', `alliswell://task/${block.taskId}`);
  setProp(vevent, 'x-alliswell-task-id', block.taskId);
  setProp(vevent, 'x-alliswell-workspace-id', block.workspaceId);
  setProp(vevent, 'last-modified', utcTime(now));
  setProp(vevent, 'dtstamp', utcTime(now));
}

/**
 * A fresh VCALENDAR for a task's block (`desiredBlockForTask`).
 *
 * @param {object} block
 * @param {{ now?: Date }} [options]
 * @returns {string}
 */
export function veventForTask(block, { now = new Date() } = {}) {
  const calendar = new ICAL.Component('vcalendar');
  calendar.addPropertyWithValue('version', '2.0');
  calendar.addPropertyWithValue('prodid', PRODID);
  calendar.addPropertyWithValue('calscale', 'GREGORIAN');
  const vevent = new ICAL.Component('vevent');
  vevent.addPropertyWithValue('uid', block.taskId);
  applyBlock(vevent, block, now);
  vevent.addPropertyWithValue('sequence', 0);
  calendar.addSubcomponent(vevent);
  return calendar.toString() + '\r\n';
}

function parseCalendar(ics) {
  try {
    const component = new ICAL.Component(ICAL.parse(String(ics)));
    return component.name === 'vcalendar' ? component : null;
  } catch {
    return null;
  }
}

const masterOf = (calendar) => {
  const vevents = calendar.getAllSubcomponents('vevent');
  return vevents.find((v) => !v.hasProperty('recurrence-id')) ?? null;
};

/**
 * There is no PATCH in CalDAV (CALDAV.md §4.3): load, change OUR fields, put
 * the whole thing back. Alarms, colours, locations and every X-APPLE property
 * the user's client added survive. SEQUENCE goes up by one.
 *
 * @returns {string|null} null when the existing resource cannot be parsed
 */
export function mergeTaskIntoIcs(existingIcs, block, { now = new Date() } = {}) {
  const calendar = parseCalendar(existingIcs);
  const master = calendar ? masterOf(calendar) : null;
  if (!master) return null;
  applyBlock(master, block, now);
  const sequence = Number(master.getFirstPropertyValue('sequence')) || 0;
  setProp(master, 'sequence', sequence + 1);
  return calendar.toString() + '\r\n';
}

// ── Reading ────────────────────────────────────────────────────────────────

function ianaZone(name) {
  if (!name) return null;
  const candidates = [String(name)];
  // Some clients prefix Olson names (`/mozilla.org/20050126_1/Europe/Berlin`).
  const parts = String(name).split('/').filter(Boolean);
  if (parts.length >= 2) candidates.push(parts.slice(-2).join('/'));
  if (parts.length >= 3) candidates.push(parts.slice(-3).join('/'));
  for (const candidate of candidates) {
    try {
      new Intl.DateTimeFormat('en', { timeZone: candidate });
      return candidate;
    } catch {
      // not a zone this runtime knows
    }
  }
  return null;
}

const pad = (n, width = 2) => String(n).padStart(width, '0');
const dateOf = (time) => `${pad(time.year, 4)}-${pad(time.month)}-${pad(time.day)}`;

/**
 * An ICAL.Time → an instant (or an all-day date). UTC as-is; a zone the
 * resource defines (VTIMEZONE) through ical.js; a bare TZID through the
 * runtime's IANA data; floating time in the account owner's zone.
 */
function toEdge(time, tzidHint, ownerZone) {
  if (!time) return null;
  if (time.isDate) return { date: dateOf(time) };
  const zone = time.zone;
  if (zone && zone.tzid === 'UTC') {
    return { dateTime: new Date(time.toUnixTime() * 1000).toISOString() };
  }
  if (zone && zone.tzid && zone.tzid !== 'floating' && zone !== ICAL.Timezone.localTimezone) {
    return { dateTime: new Date(time.toUnixTime() * 1000).toISOString() };
  }
  const named = ianaZone(time.timezone ?? tzidHint) ?? ownerZone;
  const instant = zonedWallTimeToUtc(
    { year: time.year, month: time.month, day: time.day, hour: time.hour, minute: time.minute },
    named,
  );
  return { dateTime: new Date(instant.getTime() + (time.second || 0) * 1000).toISOString() };
}

function addDays(dateString, days) {
  const [y, m, d] = dateString.split('-').map(Number);
  const next = new Date(Date.UTC(y, m - 1, d + days));
  return next.toISOString().slice(0, 10);
}

/** DTEND, else DTSTART + DURATION, else the RFC 5545 §3.6.1 defaults. */
function endEdge(vevent, startTime, tzidHint, ownerZone) {
  const dtend = vevent.getFirstPropertyValue('dtend');
  if (dtend)
    return toEdge(
      dtend,
      vevent.getFirstProperty('dtend').getParameter('tzid') ?? tzidHint,
      ownerZone,
    );
  const duration = vevent.getFirstPropertyValue('duration');
  if (duration && startTime) {
    const end = startTime.clone();
    end.addDuration(duration);
    return toEdge(end, tzidHint, ownerZone);
  }
  if (!startTime) return null;
  // A DATE start with no end lasts the day; a DATE-TIME one is an instant.
  if (startTime.isDate) return { date: addDays(dateOf(startTime), 1) };
  return toEdge(startTime, tzidHint, ownerZone);
}

function stampOf(vevent) {
  const value =
    vevent.getFirstPropertyValue('last-modified') ?? vevent.getFirstPropertyValue('dtstamp');
  if (!value) return null;
  try {
    return toEdge(value, null, 'UTC')?.dateTime ?? null;
  } catch {
    return null;
  }
}

const str = (value) => (value == null ? null : String(value));

function taskIdOf(vevent, href) {
  const xprop = str(vevent.getFirstPropertyValue('x-alliswell-task-id'))?.trim();
  if (xprop && ULID.test(xprop)) return xprop;
  const url = str(vevent.getFirstPropertyValue('url'))?.trim();
  const fromUrl = url ? TASK_URL.exec(url) : null;
  if (fromUrl) return fromUrl[1];
  const fromHref = href ? TASK_HREF.exec(href) : null;
  if (fromHref) return fromHref[1];
  const uid = str(vevent.getFirstPropertyValue('uid'))?.trim();
  if (uid && ULID.test(uid)) return uid;
  return null;
}

function eventFields(vevent, { tzidHint, timeZone }) {
  const startTime = vevent.getFirstPropertyValue('dtstart');
  const start = toEdge(startTime, tzidHint, timeZone);
  const end = endEdge(vevent, startTime, tzidHint, timeZone);
  const status = str(vevent.getFirstPropertyValue('status'))?.toUpperCase();
  const transp = str(vevent.getFirstPropertyValue('transp'))?.toUpperCase();
  return {
    start,
    end,
    summary: str(vevent.getFirstPropertyValue('summary')),
    description: str(vevent.getFirstPropertyValue('description')),
    location: str(vevent.getFirstPropertyValue('location')),
    ...(status === 'CANCELLED' ? { status: 'cancelled' } : { status: 'confirmed' }),
    ...(transp === 'TRANSPARENT' ? { transparency: 'transparent' } : {}),
  };
}

/**
 * One calendar resource → what the sync needs to know about it.
 *
 * `master` is the provider-neutral event (`id` = the href). It carries
 * `extendedProperties.private.alliswell_task_id` when the resource is ours, so
 * the shared reconcile and `deriveExternalEvent` ("ours → skip") work
 * unchanged; `recurrence` is set when the master repeats, which the reconcile
 * answers with `time_conflict` for our own events (ADR-0007).
 *
 * @param {string} ics
 * @param {{ href: string, etag: string|null, timeZone: string }} context
 * @returns {null | { master: object, taskId: string|null, recurring: boolean,
 *                    calendar: object, vevent: object, uid: string|null }}
 *   null = not a parsable VEVENT resource (a VTODO, a broken body)
 */
export function parseResource(ics, { href, etag, timeZone }) {
  const calendar = parseCalendar(ics);
  const vevent = calendar ? masterOf(calendar) : null;
  if (!vevent) return null;
  const tzidHint = vevent.getFirstProperty('dtstart')?.getParameter('tzid') ?? null;
  let fields;
  try {
    fields = eventFields(vevent, { tzidHint, timeZone });
  } catch {
    return null;
  }
  if (!fields.start) return null;
  const recurring = vevent.hasProperty('rrule') || vevent.hasProperty('rdate');
  const taskId = taskIdOf(vevent, href);
  const master = {
    id: href,
    etag: etag ?? null,
    updated: stampOf(vevent),
    ...fields,
    ...(recurring
      ? { recurrence: vevent.getAllProperties('rrule').map((p) => `RRULE:${p.getFirstValue()}`) }
      : {}),
    ...(taskId ? { extendedProperties: { private: { alliswell_task_id: taskId } } } : {}),
  };
  if (recurring && master.recurrence.length === 0) master.recurrence = ['RDATE'];
  return {
    master,
    taskId,
    recurring,
    calendar,
    vevent,
    uid: str(vevent.getFirstPropertyValue('uid')),
  };
}

const ms = (edge) =>
  edge?.dateTime
    ? Date.parse(edge.dateTime)
    : edge?.date
      ? Date.parse(`${edge.date}T00:00:00Z`)
      : NaN;

/**
 * Did the resource keep exactly the fields we write? Then a mirror pass has
 * nothing to PUT — only the link's bookkeeping moves.
 */
export function matchesBlock(parsed, block) {
  const event = parsed.master;
  if (!event.start?.dateTime || !event.end?.dateTime) return false;
  return (
    event.summary === block.title &&
    (event.description ?? null) === (block.description ?? null) &&
    ms(event.start) === block.start.getTime() &&
    ms(event.end) === block.end.getTime()
  );
}

function instanceKey(time, tzidHint, timeZone) {
  const edge = toEdge(time, tzidHint, timeZone);
  if (edge?.date) return edge.date.replace(/-/g, '');
  return edge.dateTime.replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}

/**
 * A repeating FOREIGN event → its instances inside [from, to], each a
 * provider-neutral event with a stable id `<sha1(href)>#<recurrence instant>`
 * (ADR-0008: a calendar grid can only draw instances). EXDATEs are honoured,
 * RECURRENCE-ID overrides replace their slot, cancelled overrides drop it.
 *
 * @returns {object[]} at most MAX_INSTANCES events
 */
export function expandInstances(parsed, { from, to, timeZone, max = MAX_INSTANCES }) {
  const { calendar, vevent, master } = parsed;
  const tzidHint = vevent.getFirstProperty('dtstart')?.getParameter('tzid') ?? null;
  const event = new ICAL.Event(vevent);
  for (const other of calendar.getAllSubcomponents('vevent')) {
    if (other !== vevent && other.hasProperty('recurrence-id')) {
      try {
        event.relateException(other);
      } catch {
        // an override for another UID — not part of this series
      }
    }
  }
  const out = [];
  const fromMs = from.getTime();
  const toMs = to.getTime();
  const iterator = event.iterator();
  for (let i = 0; i < MAX_ITERATIONS && out.length < max; i += 1) {
    const next = iterator.next();
    if (!next) break;
    const details = event.getOccurrenceDetails(next);
    const item = details.item;
    const itemHint = item.component.getFirstProperty('dtstart')?.getParameter('tzid') ?? tzidHint;
    const start = toEdge(details.startDate, itemHint, timeZone);
    const end = toEdge(details.endDate, itemHint, timeZone);
    const startMs = ms(start);
    if (startMs > toMs && ms(toEdge(next, tzidHint, timeZone)) > toMs) break;
    if (ms(end) < fromMs || startMs > toMs) continue;
    const fields =
      item === event ? master : eventFields(item.component, { tzidHint: itemHint, timeZone });
    if (fields.status === 'cancelled') continue;
    out.push({
      id: externalIdFor(master.id, instanceKey(next, tzidHint, timeZone)),
      etag: master.etag,
      updated: master.updated,
      status: 'confirmed',
      start,
      end,
      summary: fields.summary,
      location: fields.location,
      ...(fields.transparency ? { transparency: fields.transparency } : {}),
    });
  }
  return out;
}
