import { describe, it, expect } from 'vitest';
import {
  expandInstances,
  externalIdFor,
  hrefForTask,
  matchesBlock,
  mergeTaskIntoIcs,
  parseResource,
  veventForTask,
} from '../../src/lib/caldav/ical.js';
import { blockForTask, desiredBlockForTask } from '../../src/lib/mirror.js';
import { reconcileProviderEvent, CONFLICT } from '../../src/lib/inbound.js';

const TASK_ID = '01JTASK0000000000000000000';
const WS_ID = '01JWS00000000000000000000A';

const task = (over = {}) => ({
  id: TASK_ID,
  workspace_id: WS_ID,
  project_id: null,
  title: 'Sunum, hazırla; ✓ test',
  description: 'Satır 1\nSatır 2',
  status: 'open',
  revision: 4,
  deleted_at: null,
  timezone: 'Europe/Istanbul',
  due_at: '2030-06-01T09:00:00.000Z',
  scheduled_start_at: null,
  scheduled_end_at: null,
  created_at: '2030-05-01T09:00:00.000Z',
  updated_at: '2030-05-02T09:00:00.000Z',
  ...over,
});

const wrap = (vevent, extra = '') =>
  `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n${extra}BEGIN:VEVENT\r\n${vevent}END:VEVENT\r\nEND:VCALENDAR\r\n`;

const ctx = { href: '/cal/x.ics', etag: '"1"', timeZone: 'Europe/Istanbul' };

describe('veventForTask (OPH-380)', () => {
  it('writes UID, URL, X-props and UTC times equal to the block', () => {
    const block = desiredBlockForTask(task());
    const ics = veventForTask(block, { now: new Date('2030-05-02T10:00:00Z') });
    expect(ics).toContain(`UID:${TASK_ID}`);
    expect(ics).toContain(`URL:alliswell://task/${TASK_ID}`);
    expect(ics).toContain(`X-ALLISWELL-TASK-ID:${TASK_ID}`);
    expect(ics).toContain(`X-ALLISWELL-WORKSPACE-ID:${WS_ID}`);
    expect(ics).toContain('PRODID:-//AllisWell//CalDAV mirror//EN');
    expect(ics).toContain('DTSTART:20300601T090000Z');
    expect(ics).toContain('DTEND:20300601T093000Z');
    // RFC 5545 escaping of , ; and newlines in TEXT.
    expect(ics).toContain('SUMMARY:[Task] Sunum\\, hazırla\\; ✓ test');
    expect(ics).toContain('DESCRIPTION:Satır 1\\nSatır 2');

    const parsed = parseResource(ics, { ...ctx, href: hrefForTask('/cal/', TASK_ID) });
    const block2 = blockForTask(task(), 'Europe/Istanbul');
    expect(parsed.master.start.dateTime).toBe(block2.start.toISOString());
    expect(parsed.master.end.dateTime).toBe(block2.end.toISOString());
    expect(parsed.taskId).toBe(TASK_ID);
    expect(matchesBlock(parsed, block)).toBe(true);
  });

  it('marks a completed task with ✓, like the Google mirror', () => {
    const block = desiredBlockForTask(task({ status: 'completed' }));
    expect(veventForTask(block)).toContain('SUMMARY:✓ [Task] Sunum');
  });

  it('hrefs are deterministic: <calendar>/alliswell-<taskId>.ics', () => {
    expect(hrefForTask('/a/b/', TASK_ID)).toBe(`/a/b/alliswell-${TASK_ID}.ics`);
    expect(hrefForTask('/a/b', TASK_ID)).toBe(`/a/b/alliswell-${TASK_ID}.ics`);
  });
});

describe('mergeTaskIntoIcs: no PATCH, keep what is not ours (CALDAV.md §4.3)', () => {
  it('replaces only our fields, drops DURATION, keeps VALARM/LOCATION/X-APPLE, bumps SEQUENCE', () => {
    const existing = wrap(
      `UID:${TASK_ID}\r\nDTSTAMP:20300101T000000Z\r\nDTSTART;TZID=Europe/Istanbul:20300601T120000\r\nDURATION:PT2H\r\nSUMMARY:old\r\nLOCATION:Ofis\r\nX-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC\r\nSEQUENCE:3\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:hey\r\nEND:VALARM\r\n`,
    );
    const block = desiredBlockForTask(task({ description: null }));
    const merged = mergeTaskIntoIcs(existing, block);
    expect(merged).toContain('LOCATION:Ofis');
    expect(merged).toContain('X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC');
    expect(merged).toContain('BEGIN:VALARM');
    expect(merged).toContain('TRIGGER:-PT15M');
    expect(merged).not.toContain('DURATION');
    expect(merged).toContain('DTSTART:20300601T090000Z');
    expect(merged).toContain('SEQUENCE:4');
    expect(merged).toContain('SUMMARY:[Task] Sunum');
    expect(merged).not.toMatch(/SUMMARY:old/);
    // The alarm's own DESCRIPTION survives; the event's is gone (task has none).
    const parsed = parseResource(merged, ctx);
    expect(parsed.master.description).toBeNull();
    expect(merged).toContain('DESCRIPTION:hey');
    expect(matchesBlock(parsed, block)).toBe(true);
  });

  it('answers null for a body it cannot read', () => {
    expect(mergeTaskIntoIcs('not ics', desiredBlockForTask(task()))).toBeNull();
  });
});

describe('parseResource → the provider-neutral event', () => {
  it('UTC times', () => {
    const p = parseResource(
      wrap(
        'UID:a\r\nDTSTART:20301001T090000Z\r\nDTEND:20301001T100000Z\r\nLAST-MODIFIED:20300901T000000Z\r\nSUMMARY:x\r\n',
      ),
      ctx,
    );
    expect(p.master).toMatchObject({
      id: '/cal/x.ics',
      etag: '"1"',
      updated: '2030-09-01T00:00:00.000Z',
      start: { dateTime: '2030-10-01T09:00:00.000Z' },
      end: { dateTime: '2030-10-01T10:00:00.000Z' },
      status: 'confirmed',
    });
    expect(p.taskId).toBeNull();
    expect(p.master.extendedProperties).toBeUndefined();
  });

  it('a TZID the resource defines with its own VTIMEZONE', () => {
    const tz =
      'BEGIN:VTIMEZONE\r\nTZID:Custom/Plus5\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\nTZOFFSETFROM:+0500\r\nTZOFFSETTO:+0500\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n';
    const p = parseResource(
      wrap(
        'UID:a\r\nDTSTART;TZID=Custom/Plus5:20301001T090000\r\nDTEND;TZID=Custom/Plus5:20301001T100000\r\n',
        tz,
      ),
      ctx,
    );
    expect(p.master.start.dateTime).toBe('2030-10-01T04:00:00.000Z');
    expect(p.master.end.dateTime).toBe('2030-10-01T05:00:00.000Z');
  });

  it('a bare TZID resolves through IANA data (no VTIMEZONE)', () => {
    const p = parseResource(
      wrap(
        'UID:a\r\nDTSTART;TZID=America/New_York:20300101T090000\r\nDTEND;TZID=America/New_York:20300101T100000\r\n',
      ),
      ctx,
    );
    expect(p.master.start.dateTime).toBe('2030-01-01T14:00:00.000Z');
    const prefixed = parseResource(
      wrap(
        'UID:a\r\nDTSTART;TZID=/mozilla.org/20050126_1/Europe/Berlin:20300101T090000\r\nDTEND;TZID=/mozilla.org/20050126_1/Europe/Berlin:20300101T100000\r\n',
      ),
      ctx,
    );
    expect(prefixed.master.start.dateTime).toBe('2030-01-01T08:00:00.000Z');
  });

  it('floating time belongs to the account owner’s zone', () => {
    const p = parseResource(
      wrap('UID:a\r\nDTSTART:20300101T090000\r\nDTEND:20300101T100000\r\n'),
      ctx,
    );
    expect(p.master.start.dateTime).toBe('2030-01-01T06:00:00.000Z'); // Istanbul +3
  });

  it('all-day: exclusive DTEND, and a missing DTEND lasts the day', () => {
    const p = parseResource(
      wrap('UID:a\r\nDTSTART;VALUE=DATE:20300101\r\nDTEND;VALUE=DATE:20300103\r\n'),
      ctx,
    );
    expect(p.master.start).toEqual({ date: '2030-01-01' });
    expect(p.master.end).toEqual({ date: '2030-01-03' });
    const single = parseResource(wrap('UID:a\r\nDTSTART;VALUE=DATE:20301231\r\n'), ctx);
    expect(single.master.end).toEqual({ date: '2031-01-01' });
  });

  it('DURATION instead of DTEND', () => {
    const p = parseResource(wrap('UID:a\r\nDTSTART:20301001T090000Z\r\nDURATION:PT1H30M\r\n'), ctx);
    expect(p.master.end.dateTime).toBe('2030-10-01T10:30:00.000Z');
  });

  it('RRULE → recurrence, so the reconcile flags our block turned into a series', () => {
    const p = parseResource(
      wrap('UID:a\r\nDTSTART:20301001T090000Z\r\nDTEND:20301001T100000Z\r\nRRULE:FREQ=WEEKLY\r\n'),
      ctx,
    );
    expect(p.recurring).toBe(true);
    expect(p.master.recurrence).toEqual(['RRULE:FREQ=WEEKLY']);
  });

  it('finds the task: X-prop → URL → href → ULID UID; malformed → null', () => {
    const body = (lines) => wrap(`UID:foreign\r\nDTSTART:20301001T090000Z\r\n${lines}`);
    const other = '01JOTHER000000000000000000';
    expect(
      parseResource(
        body(`X-ALLISWELL-TASK-ID:${TASK_ID}\r\nURL:alliswell://task/${other}\r\n`),
        ctx,
      ).taskId,
    ).toBe(TASK_ID);
    expect(parseResource(body(`URL:alliswell://task/${TASK_ID}\r\n`), ctx).taskId).toBe(TASK_ID);
    expect(parseResource(body(''), { ...ctx, href: `/cal/alliswell-${TASK_ID}.ics` }).taskId).toBe(
      TASK_ID,
    );
    expect(parseResource(wrap(`UID:${TASK_ID}\r\nDTSTART:20301001T090000Z\r\n`), ctx).taskId).toBe(
      TASK_ID,
    );
    const ours = parseResource(body(`X-ALLISWELL-TASK-ID:${TASK_ID}\r\n`), ctx);
    expect(ours.master.extendedProperties.private.alliswell_task_id).toBe(TASK_ID);
    expect(parseResource('garbage', ctx)).toBeNull();
    expect(
      parseResource(
        'BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:t\r\nEND:VTODO\r\nEND:VCALENDAR\r\n',
        ctx,
      ),
    ).toBeNull();
  });
});

describe('expandInstances: a foreign series → instances in the window (ADR-0008)', () => {
  const window = { from: new Date('2030-01-01T00:00:00Z'), to: new Date('2030-03-01T00:00:00Z') };

  it('weekly series, an EXDATE, a moved override, stable ids', () => {
    const ics =
      'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n' +
      'BEGIN:VEVENT\r\nUID:s\r\nDTSTART;TZID=Europe/Istanbul:20300107T100000\r\nDTEND;TZID=Europe/Istanbul:20300107T110000\r\nRRULE:FREQ=WEEKLY;COUNT=5\r\nEXDATE;TZID=Europe/Istanbul:20300114T100000\r\nSUMMARY:Standup\r\nEND:VEVENT\r\n' +
      'BEGIN:VEVENT\r\nUID:s\r\nRECURRENCE-ID;TZID=Europe/Istanbul:20300121T100000\r\nDTSTART;TZID=Europe/Istanbul:20300121T150000\r\nDTEND;TZID=Europe/Istanbul:20300121T160000\r\nSUMMARY:Standup (moved)\r\nEND:VEVENT\r\n' +
      'END:VCALENDAR\r\n';
    const parsed = parseResource(ics, { ...ctx, href: '/cal/s.ics' });
    const instances = expandInstances(parsed, { ...window, timeZone: 'Europe/Istanbul' });
    expect(instances.map((i) => i.start.dateTime)).toEqual([
      '2030-01-07T07:00:00.000Z',
      '2030-01-21T12:00:00.000Z',
      '2030-01-28T07:00:00.000Z',
      '2030-02-04T07:00:00.000Z',
    ]);
    expect(instances[1].summary).toBe('Standup (moved)');
    // The id is the ORIGINAL slot, so moving an override keeps its row.
    expect(instances[1].id).toBe(`${externalIdFor('/cal/s.ics')}#20300121T070000Z`);
    expect(instances.every((i) => i.etag === '"1"')).toBe(true);
  });

  it('only what falls inside the window, and never more than the cap', () => {
    const ics = wrap(
      'UID:d\r\nDTSTART:20290101T090000Z\r\nDTEND:20290101T100000Z\r\nRRULE:FREQ=DAILY\r\n',
    );
    const parsed = parseResource(ics, { ...ctx, href: '/cal/d.ics' });
    const all = expandInstances(parsed, { ...window, timeZone: 'UTC' });
    expect(all).toHaveLength(59);
    expect(all[0].start.dateTime).toBe('2030-01-01T09:00:00.000Z');
    expect(expandInstances(parsed, { ...window, timeZone: 'UTC', max: 10 })).toHaveLength(10);
  });
});

describe('the ADR-0007 matrix on CalDAV-normalised events', () => {
  const t = task({ scheduled_start_at: null });
  const block = desiredBlockForTask(t);
  const ours = (lines, etag = '"2"') =>
    parseResource(wrap(`UID:${TASK_ID}\r\nX-ALLISWELL-TASK-ID:${TASK_ID}\r\n${lines}`), {
      ...ctx,
      etag,
    }).master;
  const link = {
    etag: '"1"',
    last_local_updated_at: t.updated_at,
  };

  it('cancelled (a 404 member) → stop mirroring, keep the task', () => {
    const outcome = reconcileProviderEvent({
      event: { id: '/cal/x.ics', status: 'cancelled', etag: null },
      link,
      task: t,
    });
    expect(outcome.decision).toBe('stop-mirror');
    expect(outcome.conflictStatus).toBe(CONFLICT.PROVIDER_DELETED);
  });

  it('our own etag → echo', () => {
    const event = ours('DTSTART:20300601T120000Z\r\nDTEND:20300601T130000Z\r\n', '"1"');
    expect(reconcileProviderEvent({ event, link, task: t }).decision).toBe('touch');
  });

  it('a drag → apply scheduled_*, never due_at', () => {
    const event = ours('DTSTART:20300601T120000Z\r\nDTEND:20300601T130000Z\r\n');
    const outcome = reconcileProviderEvent({ event, link, task: t });
    expect(outcome.decision).toBe('apply');
    expect(outcome.taskPatch).toEqual({
      scheduled_start_at: new Date('2030-06-01T12:00:00Z'),
      scheduled_end_at: new Date('2030-06-01T13:00:00Z'),
    });
  });

  it('a cosmetic edit with our times → touch', () => {
    const event = ours(
      `DTSTART:${block.start.toISOString().replace(/[-:]|\.\d{3}/g, '')}\r\nDTEND:${block.end.toISOString().replace(/[-:]|\.\d{3}/g, '')}\r\nLOCATION:new\r\n`,
    );
    expect(reconcileProviderEvent({ event, link, task: t }).decision).toBe('touch');
  });

  it('both changed → last write wins on the wall clock', () => {
    const edited = { ...t, updated_at: '2030-05-03T09:00:00.000Z' };
    const newer = ours(
      'DTSTART:20300601T120000Z\r\nDTEND:20300601T130000Z\r\nLAST-MODIFIED:20300504T000000Z\r\n',
    );
    expect(reconcileProviderEvent({ event: newer, link, task: edited }).decision).toBe('apply');
    const older = ours(
      'DTSTART:20300601T120000Z\r\nDTEND:20300601T130000Z\r\nLAST-MODIFIED:20300502T120000Z\r\n',
    );
    expect(reconcileProviderEvent({ event: older, link, task: edited }).decision).toBe('push');
  });

  it('turned into a series → flag time_conflict', () => {
    const event = ours(
      'DTSTART:20300601T120000Z\r\nDTEND:20300601T130000Z\r\nRRULE:FREQ=DAILY\r\n',
    );
    const outcome = reconcileProviderEvent({ event, link, task: t });
    expect(outcome.decision).toBe('flag');
    expect(outcome.conflictStatus).toBe(CONFLICT.TIME);
  });
});
