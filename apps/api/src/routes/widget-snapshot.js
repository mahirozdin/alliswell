import crypto from 'node:crypto';
import { coded } from '../lib/errors.js';
import { widgetScopeFacts } from '../lib/ee.js';
import { isValidTimeZone } from '../lib/importers/dates.js';
import {
  WIDGET_HORIZON_DAYS,
  WIDGET_PLANNING_STATUSES,
  WIDGET_SNAPSHOT_DAYS,
  buildWidgetServerDays,
  localDayOf,
  scopeShowsEvents,
  selectWidgetTasks,
  startOfLocalDay,
} from '../lib/widget-grouping.js';
import { widgetRateLimit } from './widget-tokens.js';

/**
 * `GET /widget/snapshot` (OPH-460, issue #50, WIDGETS §3.2, ADR-0070).
 *
 * The iOS widget extension's own read while the app is swiped away: the v6
 * per-day views (`days[]`) for the device's remembered list, built by
 * `lib/widget-grouping.js` — the server port of the app's grouping, locked to
 * the shared Dart fixture — in the client's time zone.
 *
 * - Opened by the widget token alone (`authenticateWidget`); a session or an
 *   API key is the same 401 as no token.
 * - Words-free: bucket keys, instants and `timeStyle` names. Labels, date
 *   formats and every other word come from the app's last snapshot.
 * - `private=1` (the default, fail-closed) sends no `title` key anywhere; an
 *   event's summary never leaves as anything but a `title`.
 * - Scope: every workspace in `workspaceIds` must be the user's membership
 *   (403 otherwise, existence not leaked); `mine=1` narrows to the user's own
 *   work; the calendar only for one workspace and not `mine` (a person's
 *   calendar never reaches a shared workspace's list).
 * - `ETag` over the body without `generatedAt` plus the normalised query;
 *   `If-None-Match` equal → 304. `Cache-Control: no-store` either way.
 *
 * REST only (I-12): device infrastructure; the same data is readable through
 * REST and MCP already. Not a push (I-13).
 */

const ULID = '[0-9A-HJKMNP-TV-Z]{26}';
const MAX_WORKSPACES = 20;

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const nextSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['id', 'bucket'],
  properties: {
    id: { type: 'string' },
    title: { type: 'string', description: 'Absent with private=1.' },
    bucket: { type: 'string' },
    dueAt: { type: 'string' },
    timeStyle: { type: 'string' },
  },
};

const itemSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['id', 'done', 'priority'],
  properties: {
    id: { type: 'string' },
    title: { type: 'string', description: 'Absent with private=1.' },
    done: { type: 'boolean' },
    priority: { type: 'string', enum: ['none', 'low', 'medium', 'high', 'urgent'] },
    projectColor: { type: 'string', description: '#RRGGBB; absent when none.' },
    kind: { type: 'string', enum: ['event'], description: 'Absent for a task.' },
    day: { type: 'string', description: 'yyyy-MM-dd, the day an event is filed under.' },
    dueAt: { type: 'string', description: "A task's due instant, an event's start." },
    endAt: { type: 'string', description: 'Events only.' },
    allDay: { type: 'boolean', description: 'Events only.' },
    timeStyle: {
      type: 'string',
      enum: ['time', 'day', 'allDay', 'range', 'start', 'end', 'dayTime'],
      description: 'How the widget words the time; absent = no label.',
    },
  },
};

const bucketSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['key', 'count', 'items'],
  properties: {
    key: { type: 'string', enum: ['overdue', 'noDate', 'today', 'thisWeek', 'thisMonth'] },
    count: { type: 'integer', description: 'Open rows in the bucket.' },
    more: { type: 'integer', description: 'Open entries past the rows carried; absent at 0.' },
    items: { type: 'array', items: itemSchema },
  },
};

const viewSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['openToday', 'buckets'],
  properties: {
    openToday: { type: 'integer' },
    next: nextSchema,
    buckets: { type: 'array', items: bucketSchema },
  },
};

const daySchema = {
  type: 'object',
  additionalProperties: false,
  required: ['date', 'openToday', 'buckets', 'views'],
  properties: {
    date: { type: 'string', description: 'The local day in tz, yyyy-MM-dd; days[0] is today.' },
    ...viewSchema.properties,
    views: {
      type: 'object',
      description: 'One per non-archived project of the scope, keyed by project id; tasks only.',
      additionalProperties: viewSchema,
    },
  },
};

/** The query as the ETag sees it: every parameter, defaults filled in. */
function normalisedQuery({ tz, workspaceIds, mine, private: hide, days }) {
  return new URLSearchParams({
    tz,
    workspaceIds: workspaceIds.join(','),
    mine: mine ? '1' : '0',
    private: hide ? '1' : '0',
    days: String(days),
  }).toString();
}

/** Whether an `If-None-Match` header names this tag (a list, `*` or weak forms alike). */
function matches(header, etag) {
  if (!header) return false;
  return String(header)
    .split(',')
    .map((part) => part.trim().replace(/^W\//, ''))
    .some((part) => part === '*' || part === etag);
}

const toTask = (row, facts) => ({
  id: row.id,
  workspaceId: row.workspace_id,
  projectId: row.project_id ?? null,
  title: row.title,
  status: row.status,
  priority: row.priority,
  colorRgb: row.color_rgb ?? null,
  startAt: row.start_at,
  dueAt: row.due_at,
  completedAt: row.completed_at,
  sortOrder: row.sort_order ?? 0,
  createdBy: row.created_by ?? null,
  assignees: facts?.assignees ?? [],
  isRequestWork: facts?.isRequestWork ?? false,
});

export default async function widgetSnapshotRoutes(app) {
  app.get(
    '/widget/snapshot',
    {
      onRequest: [app.authenticateWidget],
      config: widgetRateLimit,
      schema: {
        description:
          "The home-screen widget's per-day views (today and the next days) for the widget token's user, in the client's time zone. Widget token (`aww_…`) only; words-free (bucket keys, instants, time styles); `private=1` (the default) sends no title. `ETag` + `If-None-Match` → 304; `Cache-Control: no-store`.",
        querystring: {
          type: 'object',
          required: ['tz', 'workspaceIds'],
          properties: {
            tz: {
              type: 'string',
              minLength: 1,
              maxLength: 64,
              description: 'IANA time zone; day boundaries and every local date use it.',
            },
            workspaceIds: {
              type: 'string',
              pattern: `^${ULID}(,${ULID}){0,${MAX_WORKSPACES - 1}}$`,
              description: `1–${MAX_WORKSPACES} comma-separated workspace ids, each one you are a member of.`,
            },
            mine: {
              type: 'string',
              enum: ['0', '1'],
              default: '0',
              description:
                '1 = only your own work (assigned to you, or yours with nobody assigned).',
            },
            private: {
              type: 'string',
              enum: ['0', '1'],
              default: '1',
              description: '1 (default) = no title anywhere in the body.',
            },
            days: {
              type: 'integer',
              minimum: 1,
              maximum: WIDGET_SNAPSHOT_DAYS,
              default: WIDGET_SNAPSHOT_DAYS,
            },
          },
        },
        response: {
          200: {
            type: 'object',
            additionalProperties: false,
            required: ['v', 'generatedAt', 'tz', 'days'],
            properties: {
              v: { type: 'integer', enum: [1] },
              generatedAt: { type: 'string', description: 'Server clock; informative only.' },
              tz: { type: 'string' },
              days: { type: 'array', items: daySchema },
            },
          },
          304: { type: 'null', description: 'Not modified: If-None-Match named the ETag.' },
          400: errorResponseSchema,
          401: errorResponseSchema,
          403: errorResponseSchema,
          429: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const q = request.query;
      if (!isValidTimeZone(q.tz)) {
        throw coded(app.httpErrors.badRequest(`Unknown time zone: ${q.tz}`), 'WIDGET_INVALID_TZ');
      }
      const params = {
        tz: q.tz,
        workspaceIds: [...new Set(q.workspaceIds.split(','))],
        mine: q.mine === '1',
        private: q.private !== '0',
        days: q.days,
      };
      const userId = request.user.id;

      // Membership, every workspace: one outsider is the whole request's 403.
      const members = await app
        .db('workspace_members')
        .where({ user_id: userId })
        .whereIn('workspace_id', params.workspaceIds)
        .pluck('workspace_id');
      if (new Set(members).size !== params.workspaceIds.length) {
        throw coded(
          app.httpErrors.forbidden('You do not have access to this workspace'),
          'AUTH_WORKSPACE_FORBIDDEN',
        );
      }

      const now = new Date();
      const { tz } = params;
      const today = localDayOf(now, tz);
      const since = new Date(startOfLocalDay(today, tz));
      const scope = {
        workspaceIds: params.workspaceIds,
        ...(params.mine ? { mineFor: userId } : {}),
      };

      // The replica's selection (`selectWidgetTasks` is the rule; SQL only
      // narrows to its candidates): a planning status, or completed today
      // and not due before today.
      const rows = await app
        .db('tasks')
        .whereIn('workspace_id', params.workspaceIds)
        .whereNull('deleted_at')
        .where((w) => {
          w.whereIn('status', WIDGET_PLANNING_STATUSES).orWhere((c) => {
            c.where('status', 'completed')
              .where('completed_at', '>=', since)
              .where((d) => d.whereNull('due_at').orWhere('due_at', '>=', since));
          });
        })
        .select(
          'id',
          'workspace_id',
          'project_id',
          'title',
          'status',
          'priority',
          'color_rgb',
          'start_at',
          'due_at',
          'completed_at',
          'sort_order',
          'created_by',
        );
      const facts = params.mine
        ? await widgetScopeFacts(app, app.db, {
            userId,
            tasks: rows.map((r) => ({ id: r.id, workspace_id: r.workspace_id })),
          })
        : new Map();
      const tasks = selectWidgetTasks(
        rows.map((row) => toTask(row, facts.get(row.id))),
        { scope, now, tz },
      );

      const projects = (
        await app
          .db('projects')
          .whereIn('workspace_id', params.workspaceIds)
          .whereNull('deleted_at')
          .orderBy([
            { column: 'sort_order', order: 'asc' },
            { column: 'created_at', order: 'asc' },
            { column: 'id', order: 'asc' },
          ])
          .select('id', 'color_rgb', 'status')
      ).map((p) => ({ id: p.id, colorRgb: p.color_rgb, status: p.status }));

      let events = [];
      if (scopeShowsEvents(scope)) {
        // Only what the days can draw: not finished before today, starting
        // before the last day's horizon ends.
        const until = new Date(startOfLocalDay(today + params.days + WIDGET_HORIZON_DAYS, tz));
        events = (
          await app
            .db('calendar_external_events')
            .where({ workspace_id: params.workspaceIds[0] })
            .whereNull('deleted_at')
            .where('ends_at', '>', since)
            .where('starts_at', '<', until)
            .orderBy([
              { column: 'starts_at', order: 'asc' },
              { column: 'id', order: 'asc' },
            ])
            .select('id', 'summary', 'starts_at', 'ends_at', 'is_all_day')
        ).map((e) => ({
          id: e.id,
          summary: e.summary,
          startsAt: e.starts_at,
          endsAt: e.ends_at,
          allDay: Boolean(e.is_all_day),
        }));
      }

      const days = buildWidgetServerDays(tasks, {
        events,
        projects,
        now,
        tz,
        private: params.private,
        days: params.days,
      });

      const query = normalisedQuery(params);
      const digest = crypto
        .createHash('sha256')
        .update(JSON.stringify({ v: 1, tz, days, query }))
        .digest('hex')
        .slice(0, 32);
      const etag = `"${digest}"`;
      reply.header('Cache-Control', 'no-store').header('ETag', etag);
      if (matches(request.headers['if-none-match'], etag)) {
        return reply.code(304).send();
      }
      return { v: 1, generatedAt: now.toISOString(), tz, days };
    },
  );
}
