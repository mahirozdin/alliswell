import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import {
  createTaskSeries,
  listLiveSeries,
  normalizeTemplate,
  parseJsonColumn,
  seriesError,
  softDeleteSeries,
  updateTaskSeries,
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
//
// The properties below DESCRIBE the rule for the API reference; they carry no
// constraint of their own, so a bad value still comes back as the stable
// TASK_SERIES_RULE_INVALID rather than a generic validation error.
const ruleSchema = {
  type: 'object',
  additionalProperties: true,
  description:
    'ADR-0020 repeat rule. `basis` "calendar" (default) repeats on a fixed pattern; "completion" (OPH-375) creates the next task N days/weeks/months after the open one is completed.',
  properties: {
    freq: {
      description: 'daily | weekly | monthly | yearly (completion: daily | weekly | monthly)',
    },
    interval: { description: 'Every N periods, 1..366' },
    basis: {
      description:
        'calendar (default) | completion — "after completion": the next due date is the completion day + interval, at the same time of day; months clamp to month end',
    },
    byWeekday: { description: 'calendar only: [{ day: MO..SU, ordinal: null | 1..5 | -1 }]' },
    byMonthDay: { description: 'calendar only, monthly/yearly: 1..31 or -1 (last day)' },
    byMonth: { description: 'calendar only, yearly: 1..12' },
    end: {
      description:
        '{ type: never } | { type: until, until: YYYY-MM-DD } | { type: count, count: 1..1000 }',
    },
  },
};
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

  function fail(code, message) {
    return seriesError(app, code, message);
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

  /** The user's own timezone — what a series falls back to (OPH-208). */
  async function timezoneOf(userId) {
    const user = await app.db('users').where({ id: userId }).first('timezone');
    return user?.timezone ?? 'Europe/Istanbul';
  }

  /** Everything a create/patch needs to agree on before it touches the database. */
  function validatedInput({ rule, template, timezone, anchorAt }) {
    const problem = validateSeriesInput({ rule, template, timezone, anchorAt });
    if (problem) throw fail(problem.code, problem.message);
    return { rule, template: normalizeTemplate(template), timezone, anchorAt: new Date(anchorAt) };
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
          required: ['rule', 'template', 'anchorAt'],
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
      const input = validatedInput({
        ...request.body,
        timezone: request.body.timezone ?? (await timezoneOf(request.user.id)),
      });

      const { stored, created, adoptedTaskId } = await createTaskSeries(app, {
        workspaceId,
        userId: request.user.id,
        rule: input.rule,
        template: input.template,
        timezone: input.timezone,
        anchorAt: input.anchorAt,
        fromTaskId: request.body.fromTaskId ?? null,
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
      const { stored, created, removed } = await updateTaskSeries(app, {
        row,
        body: request.body,
      });
      return { series: serializeTaskSeries(stored), created, removed };
    },
  );

  // ── Delete: stop repeating, keep what already happened ────────────────────
  app.delete(
    '/task-series/:seriesId',
    {
      ...auth,
      schema: {
        params: { type: 'object', required: ['seriesId'], properties: { seriesId: ULID_PARAM } },
        querystring: {
          type: 'object',
          properties: {
            // "This and future" from a specific occurrence, not from today.
            fromDay: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
          },
        },
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
          fromDay: request.query.fromDay ?? null,
        }));
      });
      return { removed };
    },
  );
}
