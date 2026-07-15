import { coded } from '../lib/errors.js';
import { recordSyncWrite } from '../db/sync.js';
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
      const row = await app
        .db('reminders')
        .where({ id: request.params.reminderId })
        .whereNull('deleted_at')
        .first();
      if (!row) {
        throw coded(app.httpErrors.notFound('Reminder not found'), 'REMINDER_NOT_FOUND');
      }
      const task = await app.db('tasks').where({ id: row.task_id }).first('workspace_id');
      await app.requireWorkspaceMember(request, task.workspace_id);

      if (row.status === 'cancelled' || row.status === 'completed') {
        throw coded(
          app.httpErrors.conflict('This alarm is no longer active'),
          'REMINDER_INVALID_TRANSITION',
        );
      }

      // Idempotent: acknowledging twice changes nothing and costs no revision.
      if (row.status !== 'acknowledged') {
        await app.db.transaction(async (trx) => {
          const revision = await recordSyncWrite(trx, {
            workspaceId: task.workspace_id,
            entityType: 'reminder',
            entityId: row.id,
            operation: 'update',
            changedFields: ['status', 'acknowledged_at'],
          });
          await trx('reminders').where({ id: row.id }).update({
            status: 'acknowledged',
            acknowledged_at: new Date(),
            revision,
            updated_at: new Date(),
          });
        });
      }

      return serializeReminder(await app.db('reminders').where({ id: row.id }).first());
    },
  );
}
