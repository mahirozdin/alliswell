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

  it('an explicit remindAt wins over the deadline', async () => {
    await createTask({
      title: 'Önden haber ver',
      dueAt: DUE_AT,
      remindAt: REMIND_AT,
      isUrgent: true,
    });
    expect(activeReminders()).toHaveLength(1);
    expect(new Date(activeReminders()[0].remind_at).toISOString()).toBe(REMIND_AT);
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
