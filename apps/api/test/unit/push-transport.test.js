import { describe, it, expect, beforeEach } from 'vitest';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { createFcmSender } from '../../src/lib/push/fcm.js';
import { createWebPushSender } from '../../src/lib/push/webpush.js';
import { createPushTransport } from '../../src/lib/push/transport.js';
import { buildReminderPayload } from '../../src/lib/push/payload.js';
import { fakeDb } from '../helpers/fakedb.js';

const REMINDER = '01HZRMNDRAAAAAAAAAAAAAAAAA';
const TASK = '01HZTASKAAAAAAAAAAAAAAAAAA';
const PAYLOAD = buildReminderPayload({
  reminderId: REMINDER,
  taskId: TASK,
  fireAt: '2026-09-20T07:30:00.000Z',
});

/** A real browser subscription — web-push validates the keys it is given. */
function subscription(endpoint = 'https://push.example/one') {
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = privateKey.export({ format: 'jwk' });
  return {
    endpoint,
    p256dh: Buffer.concat([
      Buffer.from([0x04]),
      Buffer.from(jwk.x, 'base64url'),
      Buffer.from(jwk.y, 'base64url'),
    ]).toString('base64url'),
    auth: crypto.randomBytes(16).toString('base64url'),
  };
}

function vapid() {
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = privateKey.export({ format: 'jwk' });
  return {
    publicKey: Buffer.concat([
      Buffer.from([0x04]),
      Buffer.from(jwk.x, 'base64url'),
      Buffer.from(jwk.y, 'base64url'),
    ]).toString('base64url'),
    privateKey: Buffer.from(jwk.d, 'base64url').toString('base64url'),
    subject: 'mailto:ops@alliswell.space',
  };
}

/** A service-account file with a real RSA key, so the JWT actually signs. */
function serviceAccount() {
  const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'aw-fcm-')), 'sa.json');
  fs.writeFileSync(
    file,
    JSON.stringify({
      type: 'service_account',
      project_id: 'alliswell-test',
      client_email: 'push@alliswell-test.iam.gserviceaccount.com',
      private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    }),
  );
  return { serviceAccountFile: file, projectId: 'alliswell-test' };
}

/** Queues canned responses and records every request. */
function fakeFetch(responses) {
  const calls = [];
  const queue = [...responses];
  const impl = async (url, init) => {
    calls.push({ url: String(url), init });
    const next = queue.length > 1 ? queue.shift() : queue[0];
    if (typeof next === 'function') return next();
    return {
      ok: next.status >= 200 && next.status < 300,
      status: next.status,
      text: async () => next.body ?? '',
      json: async () => JSON.parse(next.body ?? '{}'),
    };
  };
  impl.calls = calls;
  return impl;
}

const tokenResponse = {
  status: 200,
  body: JSON.stringify({ access_token: 'at-1', expires_in: 3600 }),
};

describe('web push sends what the browser can decrypt (OPH-312)', () => {
  it('posts to the endpoint and reports it sent', async () => {
    const fetchImpl = fakeFetch([{ status: 201 }]);
    const sender = createWebPushSender({ ...vapid(), fetchImpl });
    const sub = subscription();

    const result = await sender.send(sub, PAYLOAD);

    expect(result).toMatchObject({ outcome: 'sent' });
    const call = fetchImpl.calls[0];
    expect(call.url).toBe(sub.endpoint);
    expect(call.init.method).toBe('POST');
    // Encrypted, so the ids must not be readable on the wire.
    expect(String(call.init.body)).not.toContain(REMINDER);
    expect(call.init.headers.Authorization ?? call.init.headers.authorization).toMatch(/vapid/i);
  });

  it('calls a revoked subscription gone, not failed', async () => {
    for (const status of [404, 410]) {
      const sender = createWebPushSender({ ...vapid(), fetchImpl: fakeFetch([{ status }]) });
      expect(await sender.send(subscription(), PAYLOAD)).toMatchObject({ outcome: 'gone' });
    }
  });

  it('separates "try again" from "never again"', async () => {
    const retry = createWebPushSender({ ...vapid(), fetchImpl: fakeFetch([{ status: 429 }]) });
    expect(await retry.send(subscription(), PAYLOAD)).toMatchObject({
      outcome: 'failed',
      retryable: true,
    });

    const never = createWebPushSender({ ...vapid(), fetchImpl: fakeFetch([{ status: 400 }]) });
    expect(await never.send(subscription(), PAYLOAD)).toMatchObject({
      outcome: 'failed',
      retryable: false,
    });
  });

  it('turns a dead network into a result, never a throw', async () => {
    const sender = createWebPushSender({
      ...vapid(),
      fetchImpl: fakeFetch([
        () => {
          throw new Error('ECONNREFUSED');
        },
      ]),
    });
    await expect(sender.send(subscription(), PAYLOAD)).resolves.toMatchObject({
      outcome: 'failed',
      retryable: true,
    });
  });
});

describe('FCM signs its own JWT (OPH-312)', () => {
  it('exchanges a signed assertion, then posts the message', async () => {
    const fetchImpl = fakeFetch([
      tokenResponse,
      { status: 200, body: '{"name":"projects/x/messages/1"}' },
    ]);
    const sender = createFcmSender({ ...serviceAccount(), fetchImpl });

    const result = await sender.send('device-token-1', PAYLOAD);

    expect(result).toMatchObject({ outcome: 'sent' });
    expect(fetchImpl.calls[0].url).toBe('https://oauth2.googleapis.com/token');
    expect(fetchImpl.calls[1].url).toBe(
      'https://fcm.googleapis.com/v1/projects/alliswell-test/messages:send',
    );
    expect(fetchImpl.calls[1].init.headers.Authorization).toBe('Bearer at-1');

    const body = JSON.parse(fetchImpl.calls[1].init.body);
    expect(body.message.token).toBe('device-token-1');
    // FCM data values are strings, every one of them.
    expect(Object.values(body.message.data).every((v) => typeof v === 'string')).toBe(true);
    expect(body.message.data.reminderId).toBe(REMINDER);
  });

  it('does not buy a new access token for every message', async () => {
    const fetchImpl = fakeFetch([tokenResponse, { status: 200, body: '{}' }]);
    const sender = createFcmSender({ ...serviceAccount(), fetchImpl });

    await sender.send('t1', PAYLOAD);
    const afterFirst = fetchImpl.calls.length;
    await sender.send('t2', PAYLOAD);

    const exchanges = fetchImpl.calls.filter((c) => c.url.includes('oauth2')).length;
    expect(exchanges).toBe(1);
    expect(fetchImpl.calls.length).toBe(afterFirst + 1);
  });

  it('reads UNREGISTERED as gone', async () => {
    const fetchImpl = fakeFetch([
      tokenResponse,
      {
        status: 404,
        body: JSON.stringify({
          error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] },
        }),
      },
    ]);
    const sender = createFcmSender({ ...serviceAccount(), fetchImpl });
    expect(await sender.send('t1', PAYLOAD)).toMatchObject({ outcome: 'gone' });
  });

  it('reads a 503 as try again later', async () => {
    const fetchImpl = fakeFetch([tokenResponse, { status: 503, body: '{}' }]);
    const sender = createFcmSender({ ...serviceAccount(), fetchImpl });
    expect(await sender.send('t1', PAYLOAD)).toMatchObject({
      outcome: 'failed',
      retryable: true,
    });
  });
});

describe('the transport is the only thing that writes a device off (OPH-312)', () => {
  let db;
  let tables;

  const device = (over) => ({
    id: '01HZDEVICEAAAAAAAAAAAAAAAA',
    user_id: '01HZUSERAAAAAAAAAAAAAAAAAA',
    platform: 'web',
    push_provider: 'webpush',
    push_endpoint: 'https://push.example/one',
    push_p256dh: subscription().p256dh,
    push_auth: crypto.randomBytes(16).toString('base64url'),
    push_token: null,
    invalid_at: null,
    last_push_at: null,
    ...over,
  });

  beforeEach(() => {
    ({ db, tables } = fakeDb());
  });

  const transportWith = (senders) =>
    createPushTransport({ db, senders, log: { warn() {}, error() {} } });

  it('marks a gone device so nothing tries it again', async () => {
    tables.notification_devices.push(device());
    const transport = transportWith({
      webpush: { send: async () => ({ outcome: 'gone' }) },
    });

    await transport.send(tables.notification_devices, PAYLOAD);

    expect(tables.notification_devices[0].invalid_at).toBeInstanceOf(Date);
  });

  it('skips a device already written off', async () => {
    tables.notification_devices.push(device({ invalid_at: new Date('2026-09-01') }));
    let tried = 0;
    const transport = transportWith({
      webpush: {
        send: async () => {
          tried += 1;
          return { outcome: 'sent' };
        },
      },
    });

    await transport.send(tables.notification_devices, PAYLOAD);

    expect(tried).toBe(0);
  });

  it('records a send without disturbing the dead mark', async () => {
    tables.notification_devices.push(device());
    const transport = transportWith({ webpush: { send: async () => ({ outcome: 'sent' }) } });

    await transport.send(tables.notification_devices, PAYLOAD);

    expect(tables.notification_devices[0].last_push_at).toBeInstanceOf(Date);
    expect(tables.notification_devices[0].invalid_at).toBeNull();
  });

  it('sends each device through the provider it registered with', async () => {
    tables.notification_devices.push(
      device(),
      device({
        id: '01HZDEVICEBBBBBBBBBBBBBBBB',
        platform: 'android',
        push_provider: 'fcm',
        push_endpoint: null,
        push_token: 'fcm-token-1',
      }),
    );
    const seen = [];
    const transport = transportWith({
      webpush: {
        send: async () => {
          seen.push('webpush');
          return { outcome: 'sent' };
        },
      },
      fcm: {
        send: async () => {
          seen.push('fcm');
          return { outcome: 'sent' };
        },
      },
    });

    await transport.send(tables.notification_devices, PAYLOAD);

    expect(seen.sort()).toEqual(['fcm', 'webpush']);
  });

  it('survives a sender that throws, and keeps going', async () => {
    tables.notification_devices.push(
      device(),
      device({ id: '01HZDEVICEBBBBBBBBBBBBBBBB', push_endpoint: 'https://push.example/two' }),
    );
    let sent = 0;
    const transport = transportWith({
      webpush: {
        send: async (sub) => {
          if (sub.endpoint.endsWith('one')) throw new Error('boom');
          sent += 1;
          return { outcome: 'sent' };
        },
      },
    });

    await expect(transport.send(tables.notification_devices, PAYLOAD)).resolves.toBeDefined();
    expect(sent).toBe(1);
  });

  it('has nothing to say about a device with no provider', async () => {
    tables.notification_devices.push(device({ push_provider: null, push_endpoint: null }));
    const transport = transportWith({});
    const results = await transport.send(tables.notification_devices, PAYLOAD);
    expect(results).toEqual([]);
  });
});
