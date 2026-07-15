import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { io as ioClient } from 'socket.io-client';
import { buildTestApp, registerUser } from '../helpers/authed.js';

let app;
let owner;
let baseUrl;
let sockets;

const bearerToken = (user) => user.headers.authorization.replace('Bearer ', '');

/**
 * Opens a client with the listeners attached BEFORE the handshake finishes —
 * `sync:ready` can share a TCP segment with the connect ack, so subscribing
 * after `connect` resolves would race the event.
 */
function connect(token) {
  const socket = ioClient(baseUrl, {
    auth: { token },
    transports: ['websocket'],
    reconnection: false,
    timeout: 2000,
  });
  sockets.push(socket);
  const events = [];
  socket.on('sync:changed', (event) => events.push(event));
  const ready = new Promise((resolve) => socket.once('sync:ready', resolve));
  const connected = new Promise((resolve, reject) => {
    socket.on('connect', () => resolve(socket));
    socket.on('connect_error', reject);
  });
  return { socket, events, ready, connected };
}

const waitForEvent = (socket, event) => new Promise((resolve) => socket.once(event, resolve));

beforeEach(async () => {
  sockets = [];
  ({ app } = await buildTestApp());
  owner = await registerUser(app, { email: 'owner@example.com' });
  await app.listen({ port: 0, host: '127.0.0.1' });
  baseUrl = `http://127.0.0.1:${app.server.address().port}`;
});

afterEach(async () => {
  for (const socket of sockets) socket.disconnect();
  await app.close();
});

describe('socket.io sync fanout (OPH-057)', () => {
  it('authenticates, joins the workspace room and hears committed writes', async () => {
    const client = connect(bearerToken(owner));
    const socket = await client.connected;
    const ready = await client.ready;
    expect(ready.workspaceIds).toEqual([owner.workspace.id]);

    const changed = waitForEvent(socket, 'sync:changed');
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: { title: 'Canlı görev' },
    });
    expect(res.statusCode).toBe(201);

    expect(await changed).toEqual({
      workspaceId: owner.workspace.id,
      toRevision: 1,
    });
    expect(client.events).toHaveLength(1);
  });

  it('coalesces a multi-revision request into one event with the top revision', async () => {
    const client = connect(bearerToken(owner));
    await client.connected;
    await client.ready;
    const events = client.events;

    // Task + its reminder commit two revisions in one transaction.
    await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: { title: 'Alarmlı görev', remindAt: '2030-06-01T09:00:00.000Z' },
    });

    await vi.waitFor(() => expect(events.length).toBeGreaterThan(0));
    // Give a straggler event a beat to show up — there must be none.
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(events).toEqual([{ workspaceId: owner.workspace.id, toRevision: 2 }]);
  });

  it('refuses missing or garbage tokens', async () => {
    await expect(connect('not-a-jwt').connected).rejects.toThrow(/unauthorized/);
    await expect(connect(undefined).connected).rejects.toThrow(/unauthorized/);
  });

  it('scopes events to workspace rooms', async () => {
    const outsider = await registerUser(app, { email: 'outsider@example.com' });
    const ownerClient = connect(bearerToken(owner));
    const outsiderClient = connect(bearerToken(outsider));
    const [ownerSocket, outsiderSocket] = await Promise.all([
      ownerClient.connected,
      outsiderClient.connected,
    ]);
    await Promise.all([ownerClient.ready, outsiderClient.ready]);
    const outsiderEvents = outsiderClient.events;

    const ownerChanged = waitForEvent(ownerSocket, 'sync:changed');
    await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: owner.headers,
      payload: { title: 'Sadece owner duysun' },
    });
    await ownerChanged;

    // The foreign workspace never hears it…
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(outsiderEvents).toHaveLength(0);

    // …but its own writes arrive with its own workspace id.
    const outsiderChanged = waitForEvent(outsiderSocket, 'sync:changed');
    await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${outsider.workspace.id}/tasks`,
      headers: outsider.headers,
      payload: { title: 'Outsider görevi' },
    });
    expect((await outsiderChanged).workspaceId).toBe(outsider.workspace.id);
  });

  it('announces sync-push mutations too (offline batch → live fanout)', async () => {
    const client = connect(bearerToken(owner));
    const socket = await client.connected;
    await client.ready;

    const changed = waitForEvent(socket, 'sync:changed');
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId: 'C'.padEnd(26, '0'),
        workspaceId: owner.workspace.id,
        baseRevision: 0,
        mutations: [
          {
            clientMutationId: 'M'.padEnd(26, '0'),
            entityType: 'task',
            entityId: '01TASKAAAAAAAAAAAAAAAAAAAA',
            operation: 'create',
            patch: { title: 'Offline’dan gelen' },
          },
        ],
      },
    });
    expect(res.statusCode).toBe(200);
    expect(await changed).toEqual({
      workspaceId: owner.workspace.id,
      toRevision: 1,
    });
  });
});
