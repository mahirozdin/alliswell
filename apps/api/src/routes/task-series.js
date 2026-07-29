import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { recordSyncWrite } from '../db/sync.js';
import {
  adoptTaskIntoSeries,
  listLiveSeries,
  materializeSeries,
  normalizeTemplate,
  parseJsonColumn,
  plannedDays,
  rebuildFuture,
  softDeleteSeries,
  validateSeriesInput,
} from '../db/task-series.js';

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

// The rule and the template are validated semantically in db/task-series.js —
// the sync push bypasses Ajv entirely, so the real rules cannot live here.
// Ajv's job is to keep the payload's SHAPE sane before it reaches them.
const ruleSchema = { type: 'object', additionalProperties: true };
const templateSchema = { type: 'object', additionalProperties: true };

const taskSeriesSchema = {
  type: 'object',
  required: ['id', 'workspaceId', 'rule', 'template', 'timezone', 'anchorAt', 'revision'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    rule: ruleSchema,
    template: templateSchema,
    timezone: { type: 'string' },
    anchorAt: { type: 'string' },
    revision: { type: 'integer' },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

export function serializeTaskSeries(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    rule: parseJsonColumn(row.rule),
    template: parseJsonColumn(row.template) ?? {},
    timezone: row.timezone,
    anchorAt: toIso(row.anchor_at),
    revision: Number(row.revision),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/**
 * Task series (OPH-205, ADR-0020) — the REST face of recurring tasks.
 *
 * A series is metadata; the occurrences it creates are ordinary tasks, so there
 * is deliberately no "list occurrences" endpoint: `GET /tasks` already returns
 * them, and inventing a second door would be the first step toward two
 * different truths.
 */
export default async function taskSeriesRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  const CODE_STATUS = {
    TASK_SERIES_RULE_INVALID: 'badRequest',
    TASK_SERIES_TEMPLATE_INVALID: 'badRequest',
    TASK_SERIES_TOO_DENSE: 'unprocessableEntity',
  };

  const CODE_MESSAGE = {
    TASK_SERIES_TOO_DENSE: 'This repeat rule would create too many tasks',
  };

  function fail(code, message) {
    const status = CODE_STATUS[code] ?? 'badRequest';
    return coded(app.httpErrors[status](message ?? CODE_MESSAGE[code] ?? 'Invalid series'), code);
  }

  /** Loads a live series and proves the caller is in its workspace. */
  async function loadSeries(request, seriesId) {
    const row = await app.db('task_series').where({ id: seriesId }).whereNull('deleted_at').first();
    if (!row) {
      throw coded(app.httpErrors.notFound('Series not found'), 'TASK_SERIES_NOT_FOUND');
    }
    await app.requireWorkspaceMember(request, row.workspace_id);
    return row;
  }

  /** Everything a create/patch needs to agree on before it touches the database. */
  function validatedInput({ rule, template, timezone, anchorAt }) {
    const problem = validateSeriesInput({ rule, template, timezone, anchorAt });
    if (problem) throw fail(problem.code, problem.message);
    return { rule, template: normalizeTemplate(template), timezone, anchorAt: new Date(anchorAt) };
  }

  /** Refuses an impossible rule BEFORE any row is written (ADR-0020 §4). */
  function assertMaterializable(series, now) {
    try {
      return plannedDays(series, now);
    } catch (err) {
      throw fail(err.code ?? 'TASK_SERIES_RULE_INVALID', err.message);
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────
  app.post(
    '/workspaces/:workspaceId/task-series',
    {
      ...auth,
      schema: {
        params: {
          type: 'object',
          required: ['workspaceId'],
          properties: { workspaceId: ULID_PARAM },
        },
        body: {
          type: 'object',
          required: ['rule', 'template', 'timezone', 'anchorAt'],
          properties: {
            rule: ruleSchema,
            template: templateSchema,
            timezone: { type: 'string', minLength: 1, maxLength: 64 },
            anchorAt: { type: 'string', format: 'date-time' },
            // The task the user flipped the Repeat switch on. When its own day
            // is part of the pattern it BECOMES the first occurrence instead of
            // being duplicated beside one.
            fromTaskId: { anyOf: [{ type: 'null' }, ULID_PARAM] },
          },
        },
        response: {
          201: {
            type: 'object',
            required: ['series', 'created'],
            properties: {
              series: taskSeriesSchema,
              created: { type: 'integer' },
              adoptedTaskId: { type: ['string', 'null'] },
            },
          },
          400: errorResponseSchema,
          422: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const input = validatedInput(request.body);

      const now = new Date();
      const id = newId();
      const series = {
        id,
        workspace_id: workspaceId,
        rule: input.rule,
        template: input.template,
        timezone: input.timezone,
        anchor_at: input.anchorAt,
        created_by: request.user.id,
      };
      assertMaterializable(series, now);

      let created = 0;
      let adoptedTaskId = null;
      let stored;
      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId,
          entityType: 'task_series',
          entityId: id,
          operation: 'create',
        });
        await trx('task_series').insert({
          ...series,
          rule: JSON.stringify(input.rule),
          template: JSON.stringify(input.template),
          revision,
        });
        stored = await trx('task_series').where({ id }).first();

        if (request.body.fromTaskId) {
          adoptedTaskId = await adoptTaskIntoSeries(trx, {
            workspaceId,
            series: stored,
            taskId: request.body.fromTaskId,
            now,
          });
        }
        ({ created } = await materializeSeries(trx, { workspaceId, series: stored, now }));
      });

      return reply.code(201).send({
        series: serializeTaskSeries(stored),
        created,
        adoptedTaskId,
      });
    },
  );

  // ── List ──────────────────────────────────────────────────────────────────
  app.get(
    '/workspaces/:workspaceId/task-series',
    {
      ...auth,
      schema: {
        params: {
          type: 'object',
          required: ['workspaceId'],
          properties: { workspaceId: ULID_PARAM },
        },
        response: {
          200: {
            type: 'object',
            required: ['series'],
            properties: { series: { type: 'array', items: taskSeriesSchema } },
          },
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const rows = await listLiveSeries(app.db, { workspaceId });
      return { series: rows.map(serializeTaskSeries) };
    },
  );

  // ── Read one ──────────────────────────────────────────────────────────────
  app.get(
    '/task-series/:seriesId',
    {
      ...auth,
      schema: {
        params: { type: 'object', required: ['seriesId'], properties: { seriesId: ULID_PARAM } },
        response: { 200: taskSeriesSchema, 404: errorResponseSchema },
      },
    },
    async (request) => serializeTaskSeries(await loadSeries(request, request.params.seriesId)),
  );

  // ── Update: the rule changes, the future is rebuilt ───────────────────────
  app.patch(
    '/task-series/:seriesId',
    {
      ...auth,
      schema: {
        params: { type: 'object', required: ['seriesId'], properties: { seriesId: ULID_PARAM } },
        body: {
          type: 'object',
          properties: {
            rule: ruleSchema,
            template: templateSchema,
            timezone: { type: 'string', minLength: 1, maxLength: 64 },
            anchorAt: { type: 'string', format: 'date-time' },
          },
        },
        response: {
          200: {
            type: 'object',
            required: ['series', 'created', 'removed'],
            properties: {
              series: taskSeriesSchema,
              created: { type: 'integer' },
              removed: { type: 'integer' },
            },
          },
          400: errorResponseSchema,
          404: errorResponseSchema,
          422: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadSeries(request, request.params.seriesId);
      const merged = {
        rule: request.body.rule ?? parseJsonColumn(row.rule),
        template: request.body.template ?? parseJsonColumn(row.template) ?? {},
        timezone: request.body.timezone ?? row.timezone,
        anchorAt: request.body.anchorAt ?? row.anchor_at,
      };
      const input = validatedInput(merged);

      const now = new Date();
      const next = {
        ...row,
        rule: input.rule,
        template: input.template,
        timezone: input.timezone,
        anchor_at: input.anchorAt,
      };
      assertMaterializable(next, now);

      let result = { created: 0, removed: 0 };
      let stored;
      await app.db.transaction(async (trx) => {
        const revision = await recordSyncWrite(trx, {
          workspaceId: row.workspace_id,
          entityType: 'task_series',
          entityId: row.id,
          operation: 'update',
          changedFields: Object.keys(request.body),
        });
        await trx('task_series')
          .where({ id: row.id })
          .update({
            rule: JSON.stringify(input.rule),
            template: JSON.stringify(input.template),
            timezone: input.timezone,
            anchor_at: input.anchorAt,
            revision,
            updated_at: new Date(),
          });
        stored = await trx('task_series').where({ id: row.id }).first();
        result = await rebuildFuture(trx, {
          workspaceId: row.workspace_id,
          series: stored,
          now,
        });
      });

      return { series: serializeTaskSeries(stored), ...result };
    },
  );

  // ── Delete: stop repeating, keep what already happened ────────────────────
  app.delete(
    '/task-series/:seriesId',
    {
      ...auth,
      schema: {
        params: { type: 'object', required: ['seriesId'], properties: { seriesId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            required: ['removed'],
            properties: { removed: { type: 'integer' } },
          },
          404: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await loadSeries(request, request.params.seriesId);
      let removed = 0;
      await app.db.transaction(async (trx) => {
        ({ removed } = await softDeleteSeries(trx, {
          workspaceId: row.workspace_id,
          series: row,
        }));
      });
      return { removed };
    },
  );
}
