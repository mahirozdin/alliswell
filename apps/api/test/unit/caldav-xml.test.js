import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  bodies,
  escapeXml,
  isCalendarCollection,
  parseDavError,
  parseMultistatus,
  parseXml,
  supportedComponents,
  textOf,
} from '../../src/lib/caldav/xml.js';

const fixture = (name) =>
  readFileSync(new URL(`../fixtures/caldav/${name}`, import.meta.url), 'utf8');

const calendarsOf = (parsed) =>
  parsed.responses
    .filter((r) => isCalendarCollection(r.props))
    .filter((r) => {
      const comps = supportedComponents(r.props);
      return !comps || comps.includes('VEVENT');
    })
    .map((r) => ({ href: r.href, name: textOf(r.props.displayname) }));

describe('caldav xml: three servers, one reading (OPH-380)', () => {
  it('reads Radicale’s default-namespace multistatus, ignoring 404 propstats', () => {
    const parsed = parseMultistatus(fixture('radicale-multistatus.xml'));
    expect(parsed.responses).toHaveLength(4);
    // The principal's 404 propstat names properties it LACKS — absent, not empty.
    expect(parsed.responses[0].props).not.toHaveProperty('getctag');
    expect(calendarsOf(parsed)).toEqual([{ href: '/alice/work/', name: 'Work & Life' }]);
    expect(supportedComponents(parsed.responses[1].props)).toEqual(['VEVENT', 'VTODO', 'VJOURNAL']);
  });

  it('reads Nextcloud’s d:/cal: prefixes and decodes &#13; inside calendar-data', () => {
    const parsed = parseMultistatus(fixture('nextcloud-multistatus.xml'));
    expect(calendarsOf(parsed)).toEqual([
      { href: '/remote.php/dav/calendars/alice/personal/', name: 'Personal' },
    ]);
    const event = parsed.responses[1];
    expect(textOf(event.props.getetag)).toBe('"8f2a"');
    const ics = textOf(event.props['calendar-data']);
    expect(ics).toContain('BEGIN:VCALENDAR\r\n');
    expect(ics).toContain('SUMMARY:Lunch & learn <3');
  });

  it('reads iCloud’s per-element namespaces, ctag and Apple colour', () => {
    const parsed = parseMultistatus(fixture('icloud-multistatus.xml'));
    expect(calendarsOf(parsed)).toEqual([{ href: '/1234567/calendars/home/', name: 'Home' }]);
    expect(textOf(parsed.responses[0].props.getctag)).toBe('HwoQEgwAAA');
    expect(textOf(parsed.responses[0].props['calendar-color'])).toBe('#FF2968FF');
    // A scheduling inbox is a collection, not a calendar.
    expect(isCalendarCollection(parsed.responses[2].props)).toBe(false);
  });

  it('reads upper-case prefixes the way iCloud writes them', () => {
    const parsed = parseMultistatus(
      '<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:response><D:href>/c/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/><C:calendar/></D:resourcetype></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>',
    );
    expect(isCalendarCollection(parsed.responses[0].props)).toBe(true);
    // No component set = every component (RFC 4791 §5.2.3).
    expect(supportedComponents(parsed.responses[0].props)).toBeNull();
  });

  it('a sync-collection report: changed members, a 404 member, the new token', () => {
    const parsed = parseMultistatus(
      '<multistatus xmlns="DAV:"><response><href>/c/a.ics</href><propstat><prop><getetag>"1"</getetag></prop><status>HTTP/1.1 200 OK</status></propstat></response>' +
        '<response><href>/c/gone.ics</href><status>HTTP/1.1 404 Not Found</status></response>' +
        '<sync-token>http://radicale.org/ns/sync/abc</sync-token></multistatus>',
    );
    expect(parsed.responses.map((r) => [r.href, r.status])).toEqual([
      ['/c/a.ics', null],
      ['/c/gone.ics', 404],
    ]);
    expect(parsed.syncToken).toBe('http://radicale.org/ns/sync/abc');
  });

  it('names the precondition of a DAV error body', () => {
    expect(
      parseDavError('<?xml version="1.0"?><D:error xmlns:D="DAV:"><D:valid-sync-token/></D:error>'),
    ).toBe('valid-sync-token');
    expect(parseDavError('<html>nope</html>')).toBeNull();
    expect(parseDavError('')).toBeNull();
  });

  it('keeps CDATA calendar-data intact', () => {
    const parsed = parseMultistatus(
      '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><response><href>/c/x.ics</href><propstat><prop><C:calendar-data><![CDATA[BEGIN:VCALENDAR\nSUMMARY:a<b\nEND:VCALENDAR]]></C:calendar-data></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>',
    );
    expect(textOf(parsed.responses[0].props['calendar-data'])).toBe(
      'BEGIN:VCALENDAR\nSUMMARY:a<b\nEND:VCALENDAR',
    );
  });

  it('refuses any document with a DTD — no entity it declares can expand', () => {
    expect(
      parseXml('<!DOCTYPE x [<!ENTITY a "AAAA">]><multistatus xmlns="DAV:">&a;</multistatus>'),
    ).toBeNull();
    expect(parseMultistatus('<!DOCTYPE multistatus><multistatus xmlns="DAV:"/>')).toBeNull();
  });

  it('escapes the values it interpolates into request bodies', () => {
    expect(escapeXml(`a&b<c>"d'`)).toBe('a&amp;b&lt;c&gt;&quot;d&apos;');
    const sync = bodies.syncCollection('tok</d:sync-token><evil/>');
    expect(sync).toContain('tok&lt;/d:sync-token&gt;&lt;evil/&gt;');
    expect(bodies.syncCollection(null)).toContain('<d:sync-token></d:sync-token>');
    expect(bodies.multiget(['/c/a&b.ics'])).toContain('<d:href>/c/a&amp;b.ics</d:href>');
  });
});
