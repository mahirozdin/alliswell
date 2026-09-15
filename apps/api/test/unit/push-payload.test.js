import { describe, it, expect } from 'vitest';
import {
  PUSH_PAYLOAD_KEYS,
  PUSH_ALERT_IDS,
  buildWakePayload,
  buildReminderPayload,
  assertPushPayload,
  PushPayloadError,
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
