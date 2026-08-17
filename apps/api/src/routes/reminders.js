// OPH-262: the transition rules live in the domain layer so the MCP
// `acknowledge_reminder` tool and REST are one implementation (ADR-0022 §4).
import { acknowledgeReminder, loadReminder } from '../db/reminders.js';
import { serializeReminder } from './sync.js';

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const reminderSchema = {
  type: 'object',
  required: ['id', 'taskId', 'status'],
  properties: {
    id: { type: 'string' },
    taskId: { type: 'string' },
    kind: { type: 'string' },
    snoozeCount: { type: 'integer' },
    remindAt: { type: 'string' },
    timezone: { type: 'string' },
    alarmLevel: { type: 'string' },
    requiresAcknowledgement: { type: 'boolean' },
    repeatRule: { type: ['string', 'null'] },
    status: { type: 'string' },
    snoozedUntil: { type: ['string', 'null'] },
    deliveredAt: { type: ['string', 'null'] },
    acknowledgedAt: { type: ['string', 'null'] },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

/**
 * Reminder lifecycle endpoints (OPH-063, BLUEPRINT §4.9/§8.2). v1 exposes
 * exactly one verb: acknowledging an urgent alarm — everything else about
 * reminders is managed through task writes (and the sync push accepts the
 * same acknowledge offline).
 */
export default async function reminderRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  app.post(
    '/reminders/:reminderId/acknowledge',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { reminderId: ULID_PARAM } },
        response: {
          200: reminderSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadReminder(app, request.params.reminderId);
      const task = await app.db('tasks').where({ id: row.task_id }).first('workspace_id');
      await app.requireWorkspaceMember(request, task.workspace_id);

      await acknowledgeReminder(app, { row, workspaceId: task.workspace_id });

      return serializeReminder(await app.db('reminders').where({ id: row.id }).first());
    },
  );
}
