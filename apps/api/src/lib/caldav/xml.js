import { XMLParser } from 'fast-xml-parser';

/**
 * WebDAV/CalDAV XML, both ways (OPH-380, ADR-0059).
 *
 * Requests are static templates — the only values interpolated are sync tokens
 * and hrefs, and both go through `escapeXml`. Responses are parsed with
 * namespace PREFIXES stripped: Radicale answers in the default namespace
 * (`<multistatus xmlns="DAV:">`), Nextcloud with `d:`/`cal:`, iCloud with
 * upper-case `D:`/`C:` — the local names are what all three agree on.
 *
 * A server's response is untrusted input: any document carrying a DTD is
 * refused before the parser sees it, so no entity it declares can expand.
 */

export const NS = {
  dav: 'DAV:',
  caldav: 'urn:ietf:params:xml:ns:caldav',
  cs: 'http://calendarserver.org/ns/',
  apple: 'http://apple.com/ns/ical/',
};

/** XML text/attribute escaping for the few values we interpolate. */
export function escapeXml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

const HEADER = '<?xml version="1.0" encoding="utf-8"?>\n';

export const bodies = {
  currentUserPrincipal: () =>
    `${HEADER}<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>`,
  calendarHomeSet: () =>
    `${HEADER}<d:propfind xmlns:d="DAV:" xmlns:c="${NS.caldav}"><d:prop><c:calendar-home-set/></d:prop></d:propfind>`,
  calendarList: () =>
    `${HEADER}<d:propfind xmlns:d="DAV:" xmlns:c="${NS.caldav}" xmlns:cs="${NS.cs}" xmlns:a="${NS.apple}">` +
    '<d:prop><d:displayname/><d:resourcetype/><c:supported-calendar-component-set/>' +
    '<cs:getctag/><a:calendar-color/></d:prop></d:propfind>',
  getetag: () => `${HEADER}<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/></d:prop></d:propfind>`,
  syncCollection: (token) =>
    `${HEADER}<d:sync-collection xmlns:d="DAV:">` +
    `<d:sync-token>${token ? escapeXml(token) : ''}</d:sync-token>` +
    '<d:sync-level>1</d:sync-level><d:prop><d:getetag/></d:prop></d:sync-collection>',
  multiget: (hrefs) =>
    `${HEADER}<c:calendar-multiget xmlns:d="DAV:" xmlns:c="${NS.caldav}">` +
    '<d:prop><d:getetag/><c:calendar-data/></d:prop>' +
    hrefs.map((href) => `<d:href>${escapeXml(href)}</d:href>`).join('') +
    '</c:calendar-multiget>',
};

const ARRAYS = new Set(['response', 'propstat', 'href', 'comp']);

const parser = new XMLParser({
  removeNSPrefix: true,
  ignoreAttributes: false,
  processEntities: true,
  // Numeric character references — sabre/Nextcloud write every CR inside
  // calendar-data as `&#13;`.
  htmlEntities: true,
  parseTagValue: false,
  parseAttributeValue: false,
  trimValues: true,
  isArray: (name) => ARRAYS.has(name),
});

/** Parses a DAV XML body; null for empty or unparsable input, never a DTD. */
export function parseXml(text) {
  if (typeof text !== 'string' || !text.trim()) return null;
  if (/<!DOCTYPE|<!ENTITY/i.test(text)) return null;
  try {
    return parser.parse(text);
  } catch {
    return null;
  }
}

/** The text of a parsed element, whatever shape the parser gave it. */
export function textOf(node) {
  if (node == null) return null;
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return textOf(node[0]);
  if (typeof node === 'object' && '#text' in node) return String(node['#text']);
  return null;
}

/** The first `<href>` inside a property such as current-user-principal. */
export function hrefOf(node) {
  if (node == null || typeof node !== 'object') return null;
  const href = node.href;
  return href == null ? null : textOf(href);
}

const statusCode = (line) => {
  const match = /\s(\d{3})(?:\s|$)/.exec(String(line ?? ''));
  return match ? Number(match[1]) : null;
};

/**
 * A `207 Multi-Status` body → one entry per `<response>`.
 *
 * - `props` merges every propstat that answered 2xx (a 404 propstat lists the
 *   properties the server does not have — absent, not empty);
 * - `status` is the response-level status: a sync-collection reports a deleted
 *   member as `<status>404</status>` with no propstat (RFC 6578 §3.5);
 * - `syncToken` is the top-level `<sync-token>` (sync-collection only).
 *
 * @returns {{ responses: {href: string, status: number|null, props: object}[],
 *             syncToken: string|null } | null}
 */
export function parseMultistatus(text) {
  const doc = parseXml(text);
  const root = doc?.multistatus;
  if (!root || typeof root !== 'object') return null;
  const responses = [];
  for (const response of root.response ?? []) {
    const href = textOf(response.href);
    if (!href) continue;
    const props = {};
    for (const propstat of response.propstat ?? []) {
      const code = statusCode(propstat.status);
      if (code != null && (code < 200 || code > 299)) continue;
      if (propstat.prop && typeof propstat.prop === 'object') Object.assign(props, propstat.prop);
    }
    responses.push({ href, status: statusCode(response.status), props });
  }
  return { responses, syncToken: textOf(root['sync-token']) };
}

/**
 * The precondition a DAV `<error>` body names — its first child's local name,
 * e.g. `valid-sync-token` (RFC 6578 §3.2). Null when the body is not one.
 */
export function parseDavError(text) {
  const doc = parseXml(text);
  const root = doc?.error;
  if (!root || typeof root !== 'object') return null;
  const name = Object.keys(root).find((key) => !key.startsWith('@_') && key !== '#text');
  return name ?? null;
}

/** Does a `<resourcetype>` mark a calendar collection? */
export function isCalendarCollection(props) {
  const type = props?.resourcetype;
  return Boolean(type && typeof type === 'object' && 'calendar' in type);
}

/**
 * The component names a collection accepts, upper-cased; null when it does
 * not say (RFC 4791 §5.2.3: absent means every component type).
 */
export function supportedComponents(props) {
  const set = props?.['supported-calendar-component-set'];
  if (set == null) return null;
  if (typeof set !== 'object') return [];
  return (set.comp ?? [])
    .map((comp) => (comp && typeof comp === 'object' ? comp['@_name'] : null))
    .filter(Boolean)
    .map((name) => String(name).toUpperCase());
}
