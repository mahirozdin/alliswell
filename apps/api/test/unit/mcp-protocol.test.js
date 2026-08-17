import { describe, it, expect, beforeEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fullDance, rpc } from '../helpers/mcpdance.js';

/** OPH-218 — the hand-rolled Streamable HTTP layer's conformance corners. */

let app;
let access;

beforeEach(async () => {
  ({ app } = await buildTestApp());
  await registerUser(app, { email: 'mcp-proto@example.com' });
  const { tokens } = await fullDance(app, { email: 'mcp-proto@example.com' });
  access = tokens.access_token;
});

describe('authentication', () => {
  it('401s without a token, WITH the WWW-Authenticate pointer', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/mcp',
      payload: { jsonrpc: '2.0', id: 1, method: 'ping' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.headers['www-authenticate']).toContain('resource_metadata=');
    expect(res.headers['www-authenticate']).toContain('/.well-known/oauth-protected-resource');
  });

  it('401s on a garbage bearer', async () => {
    const res = await rpc(app, 'not-a-real-token', 'ping');
    expect(res.statusCode).toBe(401);
  });
});

describe('protocol negotiation and envelope rules', () => {
  it('initialize echoes a supported version and advertises capabilities', async () => {
    const res = await rpc(app, access, 'initialize', {
      protocolVersion: '2025-03-26',
      capabilities: {},
      clientInfo: { name: 'test', version: '0' },
    });
    const result = res.json().result;
    expect(result.protocolVersion).toBe('2025-03-26');
    expect(result.capabilities.tools).toEqual({ listChanged: false });
    expect(result.serverInfo.name).toBe('alliswell');

    const unknown = await rpc(app, access, 'initialize', { protocolVersion: '1999-01-01' });
    expect(unknown.json().result.protocolVersion).toBe('2025-06-18');
  });

  it('unknown method → -32601; batch → -32600; junk → -32600', async () => {
    const unknown = await rpc(app, access, 'no/such/method');
    expect(unknown.json().error.code).toBe(-32601);

    const batch = await app.inject({
      method: 'POST',
      url: '/mcp',
      headers: { authorization: `Bearer ${access}` },
      payload: [{ jsonrpc: '2.0', id: 1, method: 'ping' }],
    });
    expect(batch.json().error.code).toBe(-32600);

    const junk = await app.inject({
      method: 'POST',
      url: '/mcp',
      headers: { authorization: `Bearer ${access}` },
      payload: { hello: 'world' },
    });
    expect(junk.json().error.code).toBe(-32600);
  });

  it('notifications answer 202 with no body', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/mcp',
      headers: { authorization: `Bearer ${access}` },
      payload: { jsonrpc: '2.0', method: 'notifications/initialized' },
    });
    expect(res.statusCode).toBe(202);
    expect(res.body).toBe('');
  });

  it('GET and DELETE answer 405 (stateless server, POST only)', async () => {
    for (const method of ['GET', 'DELETE']) {
      const res = await app.inject({ method, url: '/mcp' });
      expect(res.statusCode).toBe(405);
      expect(res.headers.allow).toBe('POST');
    }
  });

  it('an unsupported MCP-Protocol-Version header is a 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/mcp',
      headers: { authorization: `Bearer ${access}`, 'mcp-protocol-version': '2020-01-01' },
      payload: { jsonrpc: '2.0', id: 1, method: 'ping' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('MCP_PROTOCOL_VERSION');
  });

  it('tools/list carries schemas and annotations; resources/list the two views', async () => {
    const tools = (await rpc(app, access, 'tools/list')).json().result.tools;
    // The allowlist ON THE WIRE — this list IS the surface (ADR-0022 §3), so a
    // tool may only appear here by an epic that meant to add it. OPH-262 added
    // the task write wave.
    expect(tools.map((t) => t.name)).toEqual([
      'search',
      'list_tasks',
      'get_task',
      'get_note',
      'get_project',
      'create_task',
      'complete_task',
      'update_task',
      'reopen_task',
      'snooze_task',
      'add_checklist_item',
      'set_checklist_item',
      'acknowledge_reminder',
    ]);
    const createTool = tools.find((t) => t.name === 'create_task');
    expect(createTool.annotations.destructiveHint).toBe(false);
    expect(createTool.inputSchema.properties.projectName).toBeDefined();
    // Every write tool carries the full annotation quadruple hosts read before
    // showing an approval prompt — an absent hint is not "false", it is
    // "unknown", and a host may then run the tool silently.
    for (const tool of tools.filter((t) => !t.annotations.readOnlyHint)) {
      expect(Object.keys(tool.annotations).sort(), tool.name).toEqual([
        'destructiveHint',
        'idempotentHint',
        'openWorldHint',
        'readOnlyHint',
      ]);
    }
    // Overwriting user-authored text is declared as such (OPH-262).
    expect(tools.find((t) => t.name === 'update_task').annotations.destructiveHint).toBe(true);
    // No delete tool — the permanent decision, visible on the wire.
    expect(tools.some((t) => t.name.includes('delete'))).toBe(false);

    const resources = (await rpc(app, access, 'resources/list')).json().result.resources;
    expect(resources.map((r) => r.uri)).toEqual([
      'alliswell://views/today',
      'alliswell://views/overdue',
    ]);

    const unknown = await rpc(app, access, 'resources/read', { uri: 'alliswell://views/nope' });
    expect(unknown.json().error.code).toBe(-32002);
  });
});

describe('origin allowlist (DNS-rebinding guard)', () => {
  it('no Origin and localhost Origins pass; a foreign Origin fails a strict CORS config', async () => {
    const inspector = await app.inject({
      method: 'POST',
      url: '/mcp',
      headers: { authorization: `Bearer ${access}`, origin: 'http://localhost:6274' },
      payload: { jsonrpc: '2.0', id: 1, method: 'ping' },
    });
    expect(inspector.statusCode).toBe(200);

    const strict = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      CORS_ORIGIN: 'https://app.alliswell.space',
    });
    const { app: strictApp } = await buildTestApp({ config: strict });
    await registerUser(strictApp, { email: 'mcp-origin@example.com' });
    const { tokens } = await fullDance(strictApp, { email: 'mcp-origin@example.com' });
    const evil = await strictApp.inject({
      method: 'POST',
      url: '/mcp',
      headers: { authorization: `Bearer ${tokens.access_token}`, origin: 'https://evil.example' },
      payload: { jsonrpc: '2.0', id: 1, method: 'ping' },
    });
    expect(evil.statusCode).toBe(403);
    const good = await strictApp.inject({
      method: 'POST',
      url: '/mcp',
      headers: {
        authorization: `Bearer ${tokens.access_token}`,
        origin: 'https://app.alliswell.space',
      },
      payload: { jsonrpc: '2.0', id: 1, method: 'ping' },
    });
    expect(good.statusCode).toBe(200);
  });
});
