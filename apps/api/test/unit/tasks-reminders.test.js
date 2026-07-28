import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
});

afterEach(async () => {
  await app.close();
});

const REMIND_AT = '2026-07-20T08:30:00.000Z';

const createTask = (payload) =>
  app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
    headers: owner.headers,
    payload,
  });

const patchTask = (taskId, payload) =>
  app.inject({ method: 'PATCH', url: `/api/v1/tasks/${taskId}`, headers: owner.headers, payload });

const activeReminders = () =>
  tables.reminders.filter((r) => ['scheduled', 'snoozed', 'delivered'].includes(r.status));

describe('urgent/remind validation (OPH-034)', () => {
  it('rejects unknown timezones with TASK_INVALID_TIMEZONE', async () => {
    const res = await createTask({
      title: 'X',
      remindAt: REMIND_AT,
      timezone: 'Mars/Olympus_Mons',
    });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ code: 'TASK_INVALID_TIMEZONE' });
    expect(tables.tasks).toHaveLength(0);

    // Aliases must pass (Intl resolves them even off the canonical list).
    expect(
      (await createTask({ title: 'Y', remindAt: REMIND_AT, timezone: 'Asia/Istanbul' })).statusCode,
    ).toBe(201);
  });

  it('urgent implies requiresAcknowledgement unless explicitly declined', async () => {
    const defaulted = (await createTask({ title: 'Acil', isUrgent: true })).json();
    expect(defaulted.requiresAcknowledgement).toBe(true);

    const declined = (
      await createTask({ title: 'Acil ama sessiz', isUrgent: true, requiresAcknowledgement: false })
    ).json();
    expect(declined.requiresAcknowledgement).toBe(false);

    // Same default when a PATCH turns the task urgent.
    const plain = (await createTask({ title: 'Sıradan' })).json();
    const urgentified = (await patchTask(plain.id, { isUrgent: true })).json();
    expect(urgentified.requiresAcknowledgement).toBe(true);
  });
});

describe('reminder row lifecycle (OPH-034)', () => {
  it('create with remindAt spawns a scheduled reminder mirroring the task', async () => {
    const task = (
      await createTask({ title: 'Alarmlı', remindAt: REMIND_AT, isUrgent: true })
    ).json();

    expect(tables.reminders).toHaveLength(1);
    const reminder = tables.reminders[0];
    expect(reminder).toMatchObject({
      task_id: task.id,
      status: 'scheduled',
      alarm_level: 'urgent',
      requires_acknowledgement: true,
      timezone: 'Europe/Istanbul',
    });
    expect(new Date(reminder.remind_at).toISOString()).toBe(REMIND_AT);
    expect(tables.sync_revisions.filter((r) => r.entity_type === 'reminder')).toHaveLength(1);
  });

  it('creates no reminder without remindAt; title patches leave reminders alone', async () => {
    const task = (await createTask({ title: 'Sessiz' })).json();
    expect(tables.reminders).toHaveLength(0);

    const withAlarm = (await createTask({ title: 'Alarmlı', remindAt: REMIND_AT })).json();
    const before = JSON.stringify(tables.reminders);
    await patchTask(withAlarm.id, { title: 'Sadece başlık' });
    expect(JSON.stringify(tables.reminders)).toBe(before);
    expect(task.remindAt).toBeNull();
  });

  it('re-arms the SAME reminder row when remindAt moves, and mirrors urgency', async () => {
    const task = (await createTask({ title: 'Kayan alarm', remindAt: REMIND_AT })).json();
    const later = '2026-07-21T10:00:00.000Z';

    await patchTask(task.id, { remindAt: later, isUrgent: true });

    expect(tables.reminders).toHaveLength(1); // updated in place, not duplicated
    const reminder = tables.reminders[0];
    expect(new Date(reminder.remind_at).toISOString()).toBe(later);
    expect(reminder.alarm_level).toBe('urgent');
    expect(reminder.requires_acknowledgement).toBe(true);
    expect(reminder.status).toBe('scheduled');
  });

  it('clearing remindAt cancels; completing completes; reopening re-arms', async () => {
    const task = (await createTask({ title: 'Döngü', remindAt: REMIND_AT })).json();

    await patchTask(task.id, { remindAt: null });
    expect(tables.reminders[0].status).toBe('cancelled');
    expect(activeReminders()).toHaveLength(0);

    await patchTask(task.id, { remindAt: REMIND_AT });
    expect(activeReminders()).toHaveLength(1); // fresh row — old one stays cancelled
    expect(tables.reminders).toHaveLength(2);

    const complete = await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/complete`,
      headers: owner.headers,
    });
    expect(complete.statusCode).toBe(200);
    expect(activeReminders()).toHaveLength(0);
    expect(tables.reminders.at(-1).status).toBe('completed');

    const reopen = await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/reopen`,
      headers: owner.headers,
    });
    expect(reopen.statusCode).toBe(200);
    // remind_at survived completion, so reopening re-arms an alarm.
    expect(activeReminders()).toHaveLength(1);
  });

  it('soft-deleting the task cancels its reminder', async () => {
    const task = (await createTask({ title: 'Silinecek', remindAt: REMIND_AT })).json();
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(204);
    expect(activeReminders()).toHaveLength(0);
    expect(tables.reminders[0].status).toBe('cancelled');
  });
});

describe('urgent tasks alarm at their deadline (feedback round 6)', () => {
  const DUE_AT = '2026-07-22T14:00:00.000Z';

  it('urgent + dueAt without remindAt spawns an urgent reminder at the deadline', async () => {
    await createTask({ title: 'Acil işin saati', dueAt: DUE_AT, isUrgent: true });

    expect(activeReminders()).toHaveLength(1);
    const reminder = activeReminders()[0];
    expect(reminder.alarm_level).toBe('urgent');
    expect(reminder.requires_acknowledgement).toBe(true);
    expect(new Date(reminder.remind_at).toISOString()).toBe(DUE_AT);
  });

  it('a plain task with only a dueAt still gets no reminder', async () => {
    await createTask({ title: 'Sakin', dueAt: DUE_AT });
    expect(tables.reminders).toHaveLength(0);
  });

  // ── Round 9 (OPH-175): a reminder is a nudge BEFORE the deadline, never a
  // replacement for it. Round 6's `remind_at ?? due_at` is reversed here.
  it('an explicit remindAt does NOT swallow the deadline alarm', async () => {
    await createTask({
      title: 'Önden haber ver',
      dueAt: DUE_AT,
      remindAt: REMIND_AT,
      isUrgent: true,
    });

    const alarms = activeReminders();
    expect(alarms).toHaveLength(2);
    const byKind = Object.fromEntries(alarms.map((a) => [a.kind, a]));
    expect(new Date(byKind.remind.remind_at).toISOString()).toBe(REMIND_AT);
    expect(new Date(byKind.due.remind_at).toISOString()).toBe(DUE_AT);
    // Both are the urgent lane: the deadline of an urgent task IS an alarm.
    expect(byKind.due.alarm_level).toBe('urgent');
  });

  it('one instant never rings twice: an equal remindAt collapses to `remind`', async () => {
    await createTask({
      title: 'Aynı an',
      dueAt: DUE_AT,
      remindAt: DUE_AT,
      isUrgent: true,
    });
    const alarms = activeReminders();
    expect(alarms).toHaveLength(1);
    expect(alarms[0].kind).toBe('remind');
  });

  it('a non-urgent task with both times gets only its reminder', async () => {
    await createTask({ title: 'Sakin ama hatırlat', dueAt: DUE_AT, remindAt: REMIND_AT });
    const alarms = activeReminders();
    expect(alarms).toHaveLength(1);
    expect(alarms[0].kind).toBe('remind');
    expect(alarms[0].alarm_level).toBe('normal');
  });

  it('the two rows move independently, and completing terminalizes both', async () => {
    const task = (
      await createTask({
        title: 'İki alarmlı',
        dueAt: DUE_AT,
        remindAt: REMIND_AT,
        isUrgent: true,
      })
    ).json();

    // Moving the deadline re-arms ONLY the deadline row.
    const later = '2026-07-23T09:00:00.000Z';
    const remindRevisionBefore = activeReminders().find((a) => a.kind === 'remind').revision;
    await patchTask(task.id, { dueAt: later });
    const afterMove = Object.fromEntries(activeReminders().map((a) => [a.kind, a]));
    expect(new Date(afterMove.due.remind_at).toISOString()).toBe(later);
    expect(new Date(afterMove.remind.remind_at).toISOString()).toBe(REMIND_AT);
    expect(afterMove.remind.revision).toBe(remindRevisionBefore);

    // Dropping urgency kills the deadline alarm and leaves the reminder.
    await patchTask(task.id, { isUrgent: false });
    expect(activeReminders().map((a) => a.kind)).toEqual(['remind']);

    // Completing the task terminalizes what is left.
    await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/complete`,
      headers: owner.headers,
    });
    expect(activeReminders()).toHaveLength(0);
  });

  it('moving the deadline moves the alarm; dropping urgency cancels it', async () => {
    const task = (await createTask({ title: 'Kayan acil', dueAt: DUE_AT, isUrgent: true })).json();
    const later = '2026-07-23T09:00:00.000Z';

    await patchTask(task.id, { dueAt: later });
    expect(activeReminders()).toHaveLength(1);
    expect(new Date(activeReminders()[0].remind_at).toISOString()).toBe(later);
    expect(activeReminders()[0].status).toBe('scheduled');

    await patchTask(task.id, { isUrgent: false });
    expect(activeReminders()).toHaveLength(0);
    expect(tables.reminders.at(-1).status).toBe('cancelled');
  });
});

describe('silencing a task without completing it (OPH-178, round 9 #6.7)', () => {
  const DUE_AT = '2026-07-22T14:00:00.000Z';

  const activeReminders = () =>
    tables.reminders.filter((r) => ['scheduled', 'snoozed', 'delivered'].includes(r.status));

  const mute = (taskId, at) =>
    app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${taskId}`,
      headers: owner.headers,
      payload: { alarmsMutedAt: at },
    });

  it('muting cancels every alarm and leaves the task OPEN', async () => {
    const task = (
      await createTask({
        title: 'Sustur beni',
        dueAt: DUE_AT,
        remindAt: REMIND_AT,
        isUrgent: true,
      })
    ).json();
    expect(activeReminders()).toHaveLength(2);

    const res = await mute(task.id, '2026-07-21T10:00:00.000Z');
    expect(res.statusCode).toBe(200);
    expect(res.json().alarmsMutedAt).toBe('2026-07-21T10:00:00.000Z');

    // No alarm survives…
    expect(activeReminders()).toHaveLength(0);
    expect(tables.reminders.every((r) => r.status === 'cancelled')).toBe(true);
    // …and the task is still an open task with its dates intact.
    expect(res.json().status).toBe('open');
    expect(res.json().dueAt).toBe(DUE_AT);
    expect(res.json().remindAt).toBe(REMIND_AT);
  });

  it('un-muting re-arms the alarms it silenced', async () => {
    const task = (await createTask({ title: 'Geri aç', dueAt: DUE_AT, isUrgent: true })).json();
    await mute(task.id, '2026-07-21T10:00:00.000Z');
    expect(activeReminders()).toHaveLength(0);

    const back = await mute(task.id, null);
    expect(back.statusCode).toBe(200);
    expect(back.json().alarmsMutedAt).toBeNull();
    const alarms = activeReminders();
    expect(alarms).toHaveLength(1);
    expect(alarms[0].kind).toBe('due');
    expect(new Date(alarms[0].remind_at).toISOString()).toBe(DUE_AT);
  });
});
