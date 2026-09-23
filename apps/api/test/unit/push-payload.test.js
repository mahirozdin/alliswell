import { describe, it, test, expect } from 'vitest';
import {
  PUSH_PAYLOAD_KEYS,
  PUSH_ALERT_IDS,
  PUSH_ALERT_TEXT,
  alertTextFor,
  buildWakePayload,
  buildReminderPayload,
  assertPushPayload,
  PushPayloadError,
  PUSH_PROTOCOL_VERSION,
} from '../../src/lib/push/payload.js';

const REMINDER = '01HZRMNDRAAAAAAAAAAAAAAAAA';
const TASK = '01HZTASKAAAAAAAAAAAAAAAAAA';
const FIRE_AT = '2026-09-20T07:30:00.000Z';

describe('push payload contract — ids only, never content (OPH-308, BLUEPRINT §8.3)', () => {
  it('a wake payload says only that something changed', () => {
    expect(buildWakePayload()).toEqual({ v: 1, type: 'wake' });
  });

  it('a reminder payload carries ids and a time, and nothing else', () => {
    expect(buildReminderPayload({ reminderId: REMINDER, taskId: TASK, fireAt: FIRE_AT })).toEqual({
      v: 1,
      type: 'reminder',
      reminderId: REMINDER,
      taskId: TASK,
      fireAt: FIRE_AT,
    });
  });

  it('a visible reminder names a fixed message, it does not carry one', () => {
    const payload = buildReminderPayload({
      reminderId: REMINDER,
      taskId: TASK,
      fireAt: FIRE_AT,
      alert: 'reminder_due',
    });
    expect(payload.alert).toBe('reminder_due');
    expect(PUSH_ALERT_IDS).toContain('reminder_due');
  });

  it('every builder stays inside the declared key set', () => {
    const declared = (type) => [...PUSH_PAYLOAD_KEYS[type]].sort();
    for (const payload of [
      buildWakePayload(),
      buildReminderPayload({ reminderId: REMINDER, taskId: TASK, fireAt: FIRE_AT }),
      buildReminderPayload({
        reminderId: REMINDER,
        taskId: TASK,
        fireAt: FIRE_AT,
        alert: 'reminder_due',
      }),
    ]) {
      const unknown = Object.keys(payload).filter((k) => !declared(payload.type).includes(k));
      expect(unknown).toEqual([]);
    }
  });
});

describe('assertPushPayload is the guard every transport must pass through', () => {
  it('accepts what the builders produce', () => {
    expect(() => assertPushPayload(buildWakePayload())).not.toThrow();
    expect(() =>
      assertPushPayload(
        buildReminderPayload({ reminderId: REMINDER, taskId: TASK, fireAt: FIRE_AT }),
      ),
    ).not.toThrow();
  });

  it('refuses a key the contract does not declare', () => {
    const payload = {
      ...buildReminderPayload({ reminderId: REMINDER, taskId: TASK, fireAt: FIRE_AT }),
      title: 'Pay the invoice',
    };
    expect(() => assertPushPayload(payload)).toThrow(PushPayloadError);
    expect(() => assertPushPayload(payload)).toThrow(/title/);
  });

  it('refuses text smuggled into an id field', () => {
    // The obvious leak is a new key; the quiet one is a known key holding prose.
    const payload = {
      ...buildReminderPayload({ reminderId: REMINDER, taskId: TASK, fireAt: FIRE_AT }),
      taskId: 'Pay the invoice',
    };
    expect(() => assertPushPayload(payload)).toThrow(PushPayloadError);
  });

  it('refuses an alert id that is not one of the fixed messages', () => {
    const payload = {
      ...buildReminderPayload({ reminderId: REMINDER, taskId: TASK, fireAt: FIRE_AT }),
      alert: 'Your task "Pay the invoice" is due',
    };
    expect(() => assertPushPayload(payload)).toThrow(PushPayloadError);
  });

  it('refuses an unknown payload type', () => {
    expect(() => assertPushPayload({ v: 1, type: 'digest' })).toThrow(PushPayloadError);
  });

  it('refuses a payload that is missing a required key', () => {
    expect(() => assertPushPayload({ v: 1, type: 'reminder', reminderId: REMINDER })).toThrow(
      PushPayloadError,
    );
  });
});

describe('no part of a task can reach a push provider', () => {
  // The negative control for this suite is recorded in TASKS.md (OPH-308):
  // adding the title to a builder turns these red.
  const task = {
    id: TASK,
    title: 'Ameliyat sonucu — Dr. Yılmaz',
    description: 'biopsy results, call the clinic',
    notes: 'SECRET',
  };
  const reminder = { id: REMINDER, task_id: task.id, remind_at: FIRE_AT };

  const fragments = [task.title, task.description, task.notes, 'Yılmaz', 'biopsy', 'SECRET'];

  it('a payload built beside a content-bearing task contains none of it', () => {
    const wire = JSON.stringify(
      buildReminderPayload({
        reminderId: reminder.id,
        taskId: reminder.task_id,
        fireAt: reminder.remind_at,
        alert: 'reminder_due',
      }),
    );
    for (const fragment of fragments) {
      expect(wire).not.toContain(fragment);
    }
  });

  it('the builder ignores content handed to it by mistake', () => {
    const wire = JSON.stringify(
      buildReminderPayload({
        reminderId: reminder.id,
        taskId: reminder.task_id,
        fireAt: reminder.remind_at,
        title: task.title,
        body: task.description,
      }),
    );
    for (const fragment of fragments) {
      expect(wire).not.toContain(fragment);
    }
  });
});

describe('OPH-320 — the only words a push may carry', () => {
  it('answers in the language the device asked for, region and all', () => {
    expect(alertTextFor('reminder_due', 'tr').body).toBe('1 hatırlatıcın var');
    // A catalogue keyed by language: `tr-TR`, `tr_TR` and `TR` are one entry,
    // because a fixed sentence has no regional variants.
    expect(alertTextFor('reminder_due', 'tr-TR').body).toBe('1 hatırlatıcın var');
    expect(alertTextFor('reminder_due', 'tr_TR').body).toBe('1 hatırlatıcın var');
    expect(alertTextFor('reminder_due', 'TR').body).toBe('1 hatırlatıcın var');
  });

  it('falls back rather than sending nothing', () => {
    // A language we do not ship, and a device that never said. Both get a
    // sentence: an empty notification is worse than an English one.
    expect(alertTextFor('reminder_due', 'fr').body).toBe('You have 1 reminder');
    expect(alertTextFor('reminder_due', null).body).toBe('You have 1 reminder');
    expect(alertTextFor('reminder_due', undefined).body).toBe('You have 1 reminder');
    expect(alertTextFor('reminder_due', '').body).toBe('You have 1 reminder');
  });

  it('has nothing to say about an alert that is not meant to be seen', () => {
    // A wake-up hint names no alert, and an unknown one must not invent words.
    expect(alertTextFor(undefined, 'tr')).toBeNull();
    expect(alertTextFor('made_up', 'tr')).toBeNull();
  });

  it('says the same thing to everyone, which is what makes it safe', () => {
    // The catalogue is static data, not a template. If this ever stops being
    // true the gate notices too (scripts/push/payload.mjs), but the rule is
    // worth stating where the strings live.
    for (const byLanguage of Object.values(PUSH_ALERT_TEXT)) {
      for (const text of Object.values(byLanguage)) {
        expect(text.body).not.toMatch(/\$\{|%s|\{\{/);
        expect(Object.isFrozen(text)).toBe(true);
      }
    }
  });

  it('names every alert id the contract declares', () => {
    // A visible alert with no words would render as an empty notification on
    // a phone; the catalogue and the id list have to move together.
    for (const id of PUSH_ALERT_IDS) {
      expect(alertTextFor(id, 'en')).not.toBeNull();
    }
  });
});

describe("OPH-329 — the third type, for an extension's notification", () => {
  test('a notify payload is accepted with an id, and an alert is optional', () => {
    expect(() =>
      assertPushPayload({
        v: PUSH_PROTOCOL_VERSION,
        type: 'notify',
        notificationId: '01J9Z4K8QK7B2N0M3XG5T6WQ7A',
      }),
    ).not.toThrow();
    expect(() =>
      assertPushPayload({
        v: PUSH_PROTOCOL_VERSION,
        type: 'notify',
        notificationId: '01J9Z4K8QK7B2N0M3XG5T6WQ7A',
        alert: 'notification_waiting',
      }),
    ).not.toThrow();
  });

  test('it refuses the event class, which is a fact about the customer', () => {
    // Not content — but "this company had an SLA breach at 14:02" is still
    // theirs, and the device does not need it to render the row it pulls.
    expect(() =>
      assertPushPayload({
        v: PUSH_PROTOCOL_VERSION,
        type: 'notify',
        notificationId: '01J9Z4K8QK7B2N0M3XG5T6WQ7A',
        eventClass: 'sla.breached',
      }),
    ).toThrow(/eventClass/);
  });

  test('and it refuses a sentence, like every other type', () => {
    expect(() =>
      assertPushPayload({
        v: PUSH_PROTOCOL_VERSION,
        type: 'notify',
        notificationId: '01J9Z4K8QK7B2N0M3XG5T6WQ7A',
        body: 'SLA missed on request #1042',
      }),
    ).toThrow();
  });

  test('its alert resolves to a line that names nothing', () => {
    const text = alertTextFor('notification_waiting', 'tr');
    expect(text.body).toBe('Yeni bir bildirimin var');
    expect(alertTextFor('notification_waiting', 'de').body).toBe('You have a new notification');
  });
});
