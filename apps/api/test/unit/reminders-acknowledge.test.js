import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { newId } from '../../src/lib/ids.js';

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

const api = (method, url, payload) => app.inject({ method, url, headers: owner.headers, payload });

/** Creates an urgent task with an alarm; returns { task, reminder }. */
async function seedAlarm() {
  const task = (
    await api('POST', `/api/v1/workspaces/${owner.workspace.id}/tasks`, {
      title: 'Acil iş',
      isUrgent: true,
      remindAt: '2030-06-01T09:00:00.000Z',
    })
  ).json();
  return { task, reminder: tables.reminders.at(-1) };
}

describe('POST /reminders/:id/acknowledge (OPH-063)', () => {
  it('acknowledges an active alarm once, idempotently after', async () => {
    const { reminder } = await seedAlarm();
    const revisionsBefore = tables.sync_revisions.length;

    const first = await api('POST', `/api/v1/reminders/${reminder.id}/acknowledge`);
    expect(first.statusCode).toBe(200);
    expect(first.json()).toMatchObject({ status: 'acknowledged' });
    expect(first.json().acknowledgedAt).toBeTruthy();
    expect(tables.sync_revisions.length).toBe(revisionsBefore + 1);

    const again = await api('POST', `/api/v1/reminders/${reminder.id}/acknowledge`);
    expect(again.statusCode).toBe(200);
    // No new revision for the no-op.
    expect(tables.sync_revisions.length).toBe(revisionsBefore + 1);
  });

  it('refuses silenced alarms and hides foreign/missing ones', async () => {
    const { task, reminder } = await seedAlarm();
    await api('POST', `/api/v1/tasks/${task.id}/complete`);
    const gone = await api('POST', `/api/v1/reminders/${reminder.id}/acknowledge`);
    expect(gone.statusCode).toBe(409);
    expect(gone.json().code).toBe('REMINDER_INVALID_TRANSITION');

    const missing = await api('POST', `/api/v1/reminders/${newId()}/acknowledge`);
    expect(missing.statusCode).toBe(404);

    const outsider = await registerUser(app, { email: 'outsider@example.com' });
    const { reminder: mine } = await seedAlarm();
    const forbidden = await app.inject({
      method: 'POST',
      url: `/api/v1/reminders/${mine.id}/acknowledge`,
      headers: outsider.headers,
    });
    expect(forbidden.statusCode).toBe(403);
  });
});

describe('sync push: offline snooze and acknowledge (OPH-062/063)', () => {
  const push = (mutations, clientId = newId()) =>
    api('POST', '/api/v1/sync/push', {
      clientId,
      workspaceId: owner.workspace.id,
      baseRevision: 0,
      mutations,
    });

  const mut = (overrides) => ({
    clientMutationId: newId(),
    operation: 'update',
    localUpdatedAt: new Date(Date.now() + 3600000).toISOString(),
    ...overrides,
  });

  it('a pushed snoozedUntil silences the active alarm in the same transaction', async () => {
    const { task, reminder } = await seedAlarm();

    const res = await push([
      mut({
        entityType: 'task',
        entityId: task.id,
        patch: { snoozedUntil: '2030-06-01T09:30:00.000Z' },
      }),
    ]);
    expect(res.json().results[0].status).toBe('applied');

    const taskRow = tables.tasks.find((t) => t.id === task.id);
    expect(taskRow.snoozed_until).toBeInstanceOf(Date);
    const remRow = tables.reminders.find((r) => r.id === reminder.id);
    expect(remRow.status).toBe('snoozed');
    expect(remRow.snoozed_until).toBeInstanceOf(Date);

    // Clearing the snooze re-arms the alarm.
    const cleared = await push([
      mut({ entityType: 'task', entityId: task.id, patch: { snoozedUntil: null } }),
    ]);
    expect(cleared.json().results[0].status).toBe('applied');
    expect(tables.reminders.find((r) => r.id === reminder.id).status).toBe('scheduled');
  });

  it('rejects snoozing a finished task, and snoozedUntil on create', async () => {
    const { task } = await seedAlarm();
    await api('POST', `/api/v1/tasks/${task.id}/complete`);

    const finished = await push([
      mut({
        entityType: 'task',
        entityId: task.id,
        patch: { snoozedUntil: '2030-06-01T09:30:00.000Z' },
      }),
    ]);
    expect(finished.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'TASK_INVALID_TRANSITION',
    });

    const onCreate = await push([
      mut({
        entityType: 'task',
        entityId: newId(),
        operation: 'create',
        patch: { title: 'x', snoozedUntil: '2030-06-01T09:30:00.000Z' },
      }),
    ]);
    expect(onCreate.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_UNKNOWN_FIELD',
    });
  });

  it('acknowledges a reminder offline; other reminder writes stay closed', async () => {
    const { reminder } = await seedAlarm();

    const ack = await push([
      mut({
        entityType: 'reminder',
        entityId: reminder.id,
        patch: { status: 'acknowledged' },
      }),
    ]);
    expect(ack.json().results[0].status).toBe('applied');
    const remRow = tables.reminders.find((r) => r.id === reminder.id);
    expect(remRow.status).toBe('acknowledged');
    expect(remRow.acknowledged_at).toBeInstanceOf(Date);

    const badStatus = await push([
      mut({
        entityType: 'reminder',
        entityId: reminder.id,
        patch: { status: 'cancelled' },
      }),
    ]);
    expect(badStatus.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_INVALID_VALUE',
    });

    const create = await push([
      mut({
        entityType: 'reminder',
        entityId: newId(),
        operation: 'create',
        patch: { status: 'acknowledged' },
      }),
    ]);
    expect(create.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SYNC_UNSUPPORTED_OPERATION',
    });

    // Acknowledging a completed task's silenced alarm is refused.
    const { task: t2, reminder: r2 } = await seedAlarm();
    await api('POST', `/api/v1/tasks/${t2.id}/complete`);
    const silenced = await push([
      mut({ entityType: 'reminder', entityId: r2.id, patch: { status: 'acknowledged' } }),
    ]);
    expect(silenced.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'REMINDER_INVALID_TRANSITION',
    });
  });
});
