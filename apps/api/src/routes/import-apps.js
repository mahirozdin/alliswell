import { runAppImport } from '../db/app-import.js';
import { IMPORT_SOURCES } from '../lib/importers/index.js';

/**
 * Moving in from Todoist or TickTick (OPH-371, ADR-0052).
 *
 *   POST /workspaces/:workspaceId/import/apps
 *
 * The caller sends the export as text — one entry per CSV file (a Todoist
 * backup ZIP is unzipped by the client first, so the server needs no zip
 * dependency). The server parses, plans and writes; `dryRun: true` returns
 * the same summary without writing — the wizard's preview IS this call
 * (DESIGN §37 I1). The same route serves the app, an API key and curl.
 *
 * Batching: at most `options.maxItems` new items are written per call and
 * `remaining` says how many are left; call again until it is 0. The import
 * ledger makes every retry safe.
 *
 * Rule 12, MCP: no tool. An export file is file bytes (AI.md §7), bulk import
 * is a script-shaped operation (LESSONS ai-mcp KARAR), and the assistant
 * already has create_task / add_checklist_item for one thing at a time.
 */

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };

/** 10 MiB: a large TickTick backup is a few MB of text. */
export const IMPORT_BODY_LIMIT = 10 * 1024 * 1024;

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
    detected: { type: 'string' },
  },
};

const countPair = (a, b) => ({
  type: 'object',
  required: [a, b],
  properties: { [a]: { type: 'integer' }, [b]: { type: 'integer' } },
});

const summarySchema = {
  type: 'object',
  required: [
    'source',
    'dryRun',
    'total',
    'projects',
    'tags',
    'tasks',
    'series',
    'checklistItems',
    'notes',
    'completed',
    'alreadyImported',
    'warnings',
    'created',
    'errors',
    'remaining',
  ],
  properties: {
    source: { type: 'string', enum: IMPORT_SOURCES },
    dryRun: { type: 'boolean' },
    timezone: { type: 'string' },
    total: { type: 'integer' },
    projects: countPair('new', 'existing'),
    tags: countPair('new', 'existing'),
    tasks: { type: 'integer' },
    series: { type: 'integer' },
    checklistItems: { type: 'integer' },
    notes: { type: 'integer' },
    completed: countPair('included', 'skipped'),
    alreadyImported: { type: 'integer' },
    googleMirror: {
      type: 'object',
      properties: {
        connected: { type: 'boolean' },
        tasks: { type: 'integer' },
        undated: { type: 'integer' },
      },
    },
    projectList: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          existing: { type: 'boolean' },
          tasks: { type: 'integer' },
        },
      },
    },
    tagList: {
      type: 'array',
      items: {
        type: 'object',
        properties: { name: { type: 'string' }, existing: { type: 'boolean' } },
      },
    },
    mapping: {
      type: 'object',
      properties: {
        priority: {
          type: 'array',
          items: {
            type: 'object',
            properties: { from: { type: 'string' }, to: { type: 'string' } },
          },
        },
        sectionsAs: { type: 'string' },
        subItemsAs: { type: 'string' },
      },
    },
    warnings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          code: { type: 'string' },
          count: { type: 'integer' },
          examples: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                file: { type: ['string', 'null'] },
                row: { type: ['integer', 'null'] },
                title: { type: ['string', 'null'] },
                value: { type: ['string', 'null'] },
              },
            },
          },
        },
      },
    },
    created: {
      type: 'object',
      properties: {
        projects: { type: 'integer' },
        tags: { type: 'integer' },
        tasks: { type: 'integer' },
        checklistItems: { type: 'integer' },
        notes: { type: 'integer' },
        series: { type: 'integer' },
      },
    },
    errors: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: ['string', 'null'] },
          row: { type: ['integer', 'null'] },
          code: { type: 'string' },
          message: { type: 'string' },
        },
      },
    },
    remaining: { type: 'integer' },
  },
};

export default async function importAppsRoutes(app) {
  app.post(
    '/workspaces/:workspaceId/import/apps',
    {
      onRequest: [app.authenticate],
      bodyLimit: IMPORT_BODY_LIMIT,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['source', 'files'],
          properties: {
            source: { type: 'string', enum: IMPORT_SOURCES },
            files: {
              type: 'array',
              minItems: 1,
              maxItems: 200,
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['name', 'content'],
                properties: {
                  name: { type: 'string', minLength: 1, maxLength: 255 },
                  content: { type: 'string', maxLength: 10000000 },
                },
              },
            },
            dryRun: { type: 'boolean', default: false },
            options: {
              type: 'object',
              additionalProperties: false,
              properties: {
                includeCompleted: { type: 'boolean', default: false },
                defaultTaskTime: {
                  type: 'string',
                  pattern: '^([01]\\d|2[0-3]):[0-5]\\d$',
                  default: '23:59',
                },
                timezone: { type: 'string', minLength: 1, maxLength: 64 },
                locale: { type: 'string', enum: ['en', 'tr'], default: 'en' },
                maxItems: { type: 'integer', minimum: 1, maximum: 500, default: 250 },
              },
            },
          },
        },
        response: {
          200: summarySchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          413: errorResponseSchema,
          422: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      try {
        return await runAppImport(app, {
          workspaceId,
          userId: request.user.id,
          source: request.body.source,
          files: request.body.files,
          options: request.body.options ?? {},
          dryRun: request.body.dryRun ?? false,
          log: request.log,
        });
      } catch (err) {
        // The importers' own refusals carry fields the default error
        // serializer would drop (`detected`), so they are sent as written.
        if (typeof err?.code === 'string' && err.code.startsWith('IMPORT_') && err.statusCode) {
          return reply.code(err.statusCode).send({
            statusCode: err.statusCode,
            code: err.code,
            error: err.statusCode === 413 ? 'Payload Too Large' : 'Unprocessable Entity',
            message: err.message,
            ...(err.detected ? { detected: err.detected } : {}),
          });
        }
        throw err;
      }
    },
  );
}
