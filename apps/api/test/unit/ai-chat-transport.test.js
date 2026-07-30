import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { io as ioClient } from 'socket.io-client';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeAi } from '../helpers/fakeai.js';
import { parseSseStream } from '../../src/lib/ai/sse.js';
import { newId } from '../../src/lib/ids.js';

/**
 * OPH-217 — the transports, against a REAL listener: SSE frames arrive
 * incrementally, a client disconnect aborts the upstream, the cancel
 * endpoint ends a stream as done{cancelled} (owner-only), and the socket
 * transport lands in the caller's personal room and nobody else's.
 */

let fake;
let app;
let owner;
let baseUrl;
let sockets;

const bearerToken = (user) => user.headers.authorization.replace('Bearer ', '');

beforeEach(async () => {
  sockets = [];
  fake = await startFakeAi();
  ({ app } = await buildTestApp());
  owner = await registerUser(app, { email: 'ai-transport@example.com' });
  await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/ai/connections`,
    headers: owner.headers,
    payload: {
      provider: 'anthropic',
      apiKey: 'sk-transport-123',
      baseUrl: `${fake.url}/anthropic`,
      consentAcknowledged: true,
    },
  });
  await app.listen({ port: 0, host: '127.0.0.1' });
  baseUrl = `http://127.0.0.1:${app.server.address().port}`;
});

afterEach(async () => {
  for (const socket of sockets) socket.disconnect();
  await app.close();
  await fake.app.close();
});

function chatFetch({ requestId, signal, body = {} }) {
  return fetch(`${baseUrl}/api/v1/workspaces/${owner.workspace.id}/ai/chat`, {
    method: 'POST',
    headers: { ...owner.headers, 'content-type': 'application/json' },
    body: JSON.stringify({
      requestId,
      messages: [{ role: 'user', content: 'merhaba' }],
      ...body,
    }),
    signal,
  });
}

async function cancelChat(requestId, headers = owner.headers) {
  return fetch(`${baseUrl}/api/v1/workspaces/${owner.workspace.id}/ai/chat/${requestId}/cancel`, {
    method: 'POST',
    headers,
  });
}

describe('SSE transport', () => {
  it('streams start → text → usage → done as event-stream frames', async () => {
    const res = await chatFetch({ requestId: newId() });
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('text/event-stream');

    const events = [];
    for await (const event of parseSseStream(res.body)) {
      events.push({ name: event.event, data: JSON.parse(event.data) });
    }
    expect(events.map((e) => e.name)).toEqual(['start', 'text', 'text', 'usage', 'done']);
    expect(events[0].data.requestId).toBeDefined();
    expect(events[1].data.text).toBe('Merhaba ');
    expect(events.at(-1).data.stopReason).toBe('stop');
  });

  it('delivers frames INCREMENTALLY and a client abort kills the upstream', async () => {
    fake.state.stall = true; // upstream never finishes on its own
    const ac = new AbortController();
    const res = await chatFetch({ requestId: newId(), signal: ac.signal });

    // The first frames arrive while the upstream is still hanging — that IS
    // the incrementality proof (a buffered stream would never yield here).
    const reader = parseSseStream(res.body)[Symbol.asyncIterator]();
    const first = await reader.next();
    expect(first.value.event).toBe('start');
    const second = await reader.next();
    expect(second.value.event).toBe('text');

    ac.abort();
    await vi.waitFor(() => expect(fake.state.aborted).toBeGreaterThan(0));
  });

  it('the cancel endpoint ends the stream with done{cancelled} — owner only', async () => {
    fake.state.stall = true;
    const requestId = newId();
    const res = await chatFetch({ requestId });
    const reader = parseSseStream(res.body)[Symbol.asyncIterator]();
    await reader.next(); // start

    // A co-member's cancel is a 204 no-op: ownership guards the abort.
    const mate = await registerUser(app, { email: 'ai-transport-mate@example.com' });
    await app.db('workspace_members').insert({
      id: newId(),
      workspace_id: owner.workspace.id,
      user_id: mate.user.id,
      role: 'member',
    });
    const mateCancel = await cancelChat(requestId, mate.headers);
    expect(mateCancel.status).toBe(204);

    const ownerCancel = await cancelChat(requestId);
    expect(ownerCancel.status).toBe(204);

    const rest = [];
    for (let step = await reader.next(); !step.done; step = await reader.next()) {
      rest.push({ name: step.value.event, data: JSON.parse(step.value.data) });
    }
    const done = rest.at(-1);
    expect(done.name).toBe('done');
    expect(done.data.cancelled).toBe(true);
    await vi.waitFor(() => expect(fake.state.aborted).toBeGreaterThan(0));
  });

  it('cancelling an unknown requestId is a quiet 204', async () => {
    const res = await cancelChat(newId());
    expect(res.status).toBe(204);
  });
});

describe('socket transport', () => {
  function connectSocket(token) {
    const socket = ioClient(baseUrl, {
      auth: { token },
      transports: ['websocket'],
      reconnection: false,
      timeout: 2000,
    });
    sockets.push(socket);
    const streams = [];
    socket.on('ai:stream', (event) => streams.push(event));
    const ready = new Promise((resolve) => socket.once('sync:ready', resolve));
    return { socket, streams, ready };
  }

  it('acks immediately, streams into the personal room, leaks to nobody', async () => {
    const mate = await registerUser(app, { email: 'ai-socket-mate@example.com' });
    addMemberRow(mate);
    const ownerClient = connectSocket(bearerToken(owner));
    const mateClient = connectSocket(bearerToken(mate));
    await ownerClient.ready;
    await mateClient.ready;

    const requestId = newId();
    const res = await chatFetch({ requestId, body: { transport: 'socket' } });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ requestId, transport: 'socket' });

    await vi.waitFor(() => {
      expect(ownerClient.streams.some((e) => e.type === 'done')).toBe(true);
    });
    expect(ownerClient.streams.map((e) => e.type)).toEqual([
      'start',
      'text',
      'text',
      'usage',
      'done',
    ]);
    expect(ownerClient.streams.every((e) => e.requestId === requestId)).toBe(true);
    // The other member's socket heard NOTHING — chat is personal, not ws:*.
    expect(mateClient.streams).toHaveLength(0);
  });

  function addMemberRow(user) {
    return app.db('workspace_members').insert({
      id: newId(),
      workspace_id: owner.workspace.id,
      user_id: user.user.id,
      role: 'member',
    });
  }
});
