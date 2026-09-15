import fp from 'fastify-plugin';

import { createFcmSender } from '../lib/push/fcm.js';
import { createWebPushSender } from '../lib/push/webpush.js';
import { createPushTransport } from '../lib/push/transport.js';

/**
 * Builds the push transport from whatever credentials this instance has
 * (OPH-312, ADR-0038), and decorates `app.pushTransport` with it.
 *
 * **`null` when there is nothing to send with.** Not an empty transport that
 * silently does nothing: a caller has to be able to ask, and the honest answer
 * to "can this instance push?" is a value you can check, not a call that
 * returns an empty array. The same shape EE's `createPushSender` already uses.
 *
 * Either provider alone is a working configuration — a browser-only instance
 * is entirely reasonable, and so is a mobile-only one.
 */
export default fp(
  async function pushPlugin(app) {
    const { push } = app.config;
    const senders = {};

    if (push.webPush.publicKey) {
      senders.webpush = createWebPushSender({
        publicKey: push.webPush.publicKey,
        privateKey: push.webPush.privateKey,
        subject: push.webPush.subject,
      });
    }
    if (push.fcm.serviceAccountFile) {
      senders.fcm = createFcmSender({
        serviceAccountFile: push.fcm.serviceAccountFile,
        projectId: push.fcm.projectId,
      });
    }

    const configured = Object.keys(senders).length > 0;
    if (configured) {
      app.log.info({ providers: Object.keys(senders) }, 'push transport ready');
    }

    app.decorate(
      'pushTransport',
      configured
        ? createPushTransport({
            // Late-bound on purpose: this plugin declares no dependency on the
            // database, and the transport only ever touches it inside a send.
            db: (...args) => app.db(...args),
            senders,
            log: app.log,
          })
        : null,
    );
  },
  { name: 'alliswell-push' },
);
