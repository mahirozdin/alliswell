import crypto from 'node:crypto';
import Ajv from 'ajv';
import { coded } from '../lib/errors.js';
import { findLiveAccessToken } from '../db/oauth.js';
import { buildTaskViewResource } from '../lib/ai/context.js';
import {
  RPC,
  PROTOCOL_VERSIONS,
  LATEST_PROTOCOL,
  rpcResult,
  rpcError,
  isValidRequest,
  isNotification,
  toolResult,
  McpToolError,
} from '../lib/mcp/jsonrpc.js';
import { MCP_TOOLS, TASK_VIEW_QUERIES } from '../lib/mcp/tools.js';

/**
 * The remote MCP server (OPH-218, ADR-0022): stateless Streamable HTTP —
 * POST /mcp carries one JSON-RPC message, the answer is plain JSON. No
 * sessions, no server push, GET/DELETE answer 405. Bearer tokens are the
 * OAuth server's opaque access tokens; membership is re-checked on every
 * request (consent-time membership may have been revoked since).
 */

const RESOURCES = [
  {
    uri: 'alliswell://views/today',
    name: 'today',
    title: 'Tasks due today',
    description: 'Open tasks due today in the account owner’s timezone.',
    mimeType: 'application/json',
  },
  {
    uri: 'alliswell://views/overdue',
    name: 'overdue',
    title: 'Overdue tasks',
    description: 'Open tasks whose due time is already in the past.',
    mimeType: 'application/json',
  },
  {
    uri: 'alliswell://views/inbox',
    name: 'inbox',
    title: 'Inbox',
    description: 'Captured tasks that have not been triaged yet.',
    mimeType: 'application/json',
  },
];

export default async function mcpRoutes(app) {
  const { mcp } = app.config;
  const publicUrl =
    mcp.publicUrl ??
    (app.config.env !== 'production' ? `http://localhost:${app.config.port}` : null);
  const configured =
    mcp.enabled &&
    Boolean(publicUrl) &&
    (app.config.env !== 'production' || publicUrl.startsWith('https://'));

  const ajv = new Ajv({ allErrors: true, strict: false });
  // EE-002: overlay tools join the surface before schemas compile — the
  // loader runs before this plugin registers, so the list is complete here.
  // Name collisions are the seam's problem (registration rejects them).
  const allTools = [...MCP_TOOLS, ...(app.ee?.mcpTools ?? [])];
  const toolIndex = new Map(
    allTools.map((tool) => [tool.name, { ...tool, validate: ajv.compile(tool.inputSchema) }]),
  );

  function assertConfigured() {
    if (!configured) {
      throw coded(
        app.httpErrors.notFound('MCP is not configured on this instance'),
        'MCP_NOT_CONFIGURED',
      );
    }
  }

  function unauthorized(reply, description) {
    reply.header(
      'www-authenticate',
      `Bearer resource_metadata="${publicUrl}/.well-known/oauth-protected-resource", error="invalid_token"` +
        (description ? `, error_description="${description}"` : ''),
    );
    const err = app.httpErrors.unauthorized(description ?? 'A valid MCP access token is required');
    err.code = 'MCP_UNAUTHORIZED';
    throw err;
  }

  /** Bearer → live token row → user + workspace context on the request. */
  async function authenticateMcp(request, reply) {
    assertConfigured();
    const header = request.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) return unauthorized(reply, 'missing bearer token');
    const row = await findLiveAccessToken(app.db, app.config.auth.refreshSecret, token);
    if (!row) return unauthorized(reply, 'token is expired or revoked');
    const user = await app
      .db('users')
      .where({ id: row.user_id })
      .whereNull('deleted_at')
      .first('id', 'email');
    if (!user) return unauthorized(reply, 'account no longer exists');
    const member = await app
      .db('workspace_members')
      .where({ workspace_id: row.workspace_id, user_id: user.id })
      .first('id');
    if (!member) return unauthorized(reply, 'workspace membership was revoked');
    request.user = { id: user.id, email: user.email };
    request.mcpAuth = {
      userId: user.id,
      workspaceId: row.workspace_id,
      scope: String(row.scope).split(' '),
      clientId: row.client_id,
      tokenId: row.id,
    };
    // Throttled liveness stamp (~1/min) — visibility without write amplification.
    const last = row.last_used_at ? new Date(row.last_used_at).getTime() : 0;
    if (Date.now() - last > 60000) {
      app
        .db('oauth_tokens')
        .where({ id: row.id })
        .update({ last_used_at: new Date() })
        .catch(() => {});
    }
  }

  /** DNS-rebinding guard (spec security section): browsers send Origin. */
  function assertOriginAllowed(request) {
    const origin = request.headers.origin;
    if (!origin) return; // server-side clients (Claude, ChatGPT) send none
    let host;
    try {
      host = new URL(origin).hostname;
    } catch {
      throw coded(app.httpErrors.forbidden('Origin not allowed'), 'MCP_ORIGIN_FORBIDDEN');
    }
    if (host === 'localhost' || host === '127.0.0.1') return; // MCP Inspector
    const allowed = app.config.corsOrigin;
    if (allowed === true) return;
    if (Array.isArray(allowed) && allowed.includes(origin)) return;
    throw coded(app.httpErrors.forbidden('Origin not allowed'), 'MCP_ORIGIN_FORBIDDEN');
  }

  async function readResource(request, uri) {
    const auth = request.mcpAuth;
    const now = new Date();
    const bounds = await TASK_VIEW_QUERIES.dayBounds(app, auth.userId, now);
    let rows;
    let view;
    if (uri === 'alliswell://views/today') {
      view = 'today';
      rows = await TASK_VIEW_QUERIES.queryToday(app, auth.workspaceId, bounds);
    } else if (uri === 'alliswell://views/overdue') {
      view = 'overdue';
      rows = await TASK_VIEW_QUERIES.queryOverdue(app, auth.workspaceId, now);
    } else if (uri === 'alliswell://views/inbox') {
      view = 'inbox';
      rows = await TASK_VIEW_QUERIES.queryInbox(app, auth.workspaceId);
    } else {
      return null;
    }
    const payload = buildTaskViewResource({ view, rows, now, timezone: bounds.timezone });
    return {
      contents: [{ uri, mimeType: 'application/json', text: JSON.stringify(payload) }],
    };
  }

  async function dispatch(request, message) {
    const { id, method, params = {} } = message;
    switch (method) {
      case 'initialize': {
        const asked = params.protocolVersion;
        const negotiated = PROTOCOL_VERSIONS.includes(asked) ? asked : LATEST_PROTOCOL;
        return rpcResult(id, {
          protocolVersion: negotiated,
          capabilities: {
            tools: { listChanged: false },
            resources: { subscribe: false, listChanged: false },
          },
          serverInfo: { name: 'alliswell', title: 'AllisWell', version: app.pkg.version },
          instructions:
            'AllisWell is a personal task/notes workspace. Read tools are free to use; ' +
            'the create_/update_/complete_/reopen_/snooze_ tools, the checklist tools and ' +
            'acknowledge_reminder modify the workspace and should follow the user’s intent. ' +
            'There is no delete tool, by design.',
        });
      }
      case 'ping':
        return rpcResult(id, {});
      case 'tools/list':
        return rpcResult(id, {
          tools: allTools.map((tool) => ({
            name: tool.name,
            title: tool.title,
            description: tool.description,
            inputSchema: tool.inputSchema,
            annotations: tool.annotations,
          })),
        });
      case 'tools/call': {
        const tool = toolIndex.get(params.name);
        if (!tool) return rpcError(id, RPC.INVALID_PARAMS, `Unknown tool: ${params.name}`);
        const args = params.arguments ?? {};
        if (typeof args !== 'object' || Array.isArray(args)) {
          return rpcError(id, RPC.INVALID_PARAMS, 'arguments must be an object');
        }
        if (!tool.validate(args)) {
          // Ajv failure is a TOOL result — the model can read it and retry.
          const detail = (tool.validate.errors ?? [])
            .slice(0, 6)
            .map((e) => `${e.instancePath || '(root)'} ${e.message}`)
            .join('; ');
          return rpcResult(
            id,
            toolResult({ code: 'INVALID_ARGUMENTS', message: detail }, { isError: true }),
          );
        }
        try {
          const payload = await tool.handler(app, request.mcpAuth, args);
          return rpcResult(id, toolResult(payload));
        } catch (err) {
          if (err instanceof McpToolError) {
            return rpcResult(
              id,
              toolResult({ code: err.code, message: err.message }, { isError: true }),
            );
          }
          // OPH-262: the domain layer refuses in HTTP terms (`coded()` +
          // @fastify/sensible) because REST is its other caller. A 4xx from it
          // is a REFUSAL the model can act on — "this task is archived",
          // "only completed tasks can be reopened" — so it becomes a tool
          // result carrying the same stable code, exactly like McpToolError.
          // 5xx stays opaque: an internal failure is not the model's to fix.
          if (err?.statusCode >= 400 && err.statusCode < 500 && typeof err.code === 'string') {
            return rpcResult(
              id,
              toolResult({ code: err.code, message: err.message }, { isError: true }),
            );
          }
          request.log.error({ err: err.message, tool: params.name }, 'mcp tool failed');
          return rpcResult(
            id,
            toolResult(
              { code: 'TOOL_FAILED', message: 'The tool failed unexpectedly' },
              { isError: true },
            ),
          );
        }
      }
      case 'resources/list':
        return rpcResult(id, { resources: RESOURCES });
      case 'resources/templates/list':
        return rpcResult(id, { resourceTemplates: [] });
      case 'resources/read': {
        const contents = await readResource(request, params.uri);
        if (!contents)
          return rpcError(id, RPC.RESOURCE_NOT_FOUND, `Unknown resource: ${params.uri}`);
        return rpcResult(id, contents);
      }
      default:
        return rpcError(id, RPC.METHOD_NOT_FOUND, `Unknown method: ${method}`);
    }
  }

  app.post(
    '/mcp',
    {
      onRequest: [authenticateMcp],
      config: {
        rateLimit: {
          max: mcp.rateLimitMax,
          timeWindow: '1 minute',
          // Per TOKEN, not per IP: Claude/ChatGPT egress collapses many users
          // onto few addresses.
          keyGenerator: (request) =>
            crypto
              .createHash('sha256')
              .update(request.headers.authorization ?? request.ip)
              .digest('hex'),
        },
      },
      schema: {
        // JSON-RPC envelopes are validated by hand — the shape errors must be
        // RPC errors, not fastify 400 envelopes.
        body: {},
      },
    },
    async (request, reply) => {
      assertOriginAllowed(request);
      const requestedVersion = request.headers['mcp-protocol-version'];
      if (requestedVersion && !PROTOCOL_VERSIONS.includes(String(requestedVersion))) {
        throw coded(
          app.httpErrors.badRequest(`Unsupported MCP-Protocol-Version: ${requestedVersion}`),
          'MCP_PROTOCOL_VERSION',
        );
      }

      const message = request.body;
      if (Array.isArray(message)) {
        // Batching was removed in 2025-06-18; refusing it IS the conformance.
        return rpcError(null, RPC.INVALID_REQUEST, 'Batch requests are not supported');
      }
      if (!isValidRequest(message)) {
        return rpcError(message?.id ?? null, RPC.INVALID_REQUEST, 'Not a JSON-RPC 2.0 request');
      }
      if (isNotification(message)) {
        return reply.code(202).send();
      }
      return dispatch(request, message);
    },
  );

  for (const method of ['GET', 'DELETE']) {
    app.route({
      method,
      url: '/mcp',
      handler: async (request, reply) => {
        assertConfigured();
        return reply
          .code(405)
          .header('allow', 'POST')
          .send({ error: 'method_not_allowed', message: 'MCP here is POST-only (stateless)' });
      },
    });
  }
}
