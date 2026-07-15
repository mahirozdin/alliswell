import fp from 'fastify-plugin';
import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { syncEvents } from '../lib/sync-events.js';

/**
 * Live sync fanout (OPH-057, BLUEPRINT §6.2): a Socket.IO server on the same
 * HTTP listener. Clients authenticate at connect with their access token
 * (`auth: { token }`), get joined to one room per workspace membership, and
 * receive `sync:changed {workspaceId, toRevision}` after every committed
 * write — never entity payloads; ordering and authorization stay with the
 * pull endpoint (ARCHITECTURE §5).
 *
 * With Redis up, the adapter fans events out across API instances; otherwise
 * the server runs in single-node mode (fine for dev and tests).
 *
 * v1 notes: membership is snapshotted at connect (clients reconnect to pick
 * up new workspaces) and the JWT is verified at connect only — a socket may
 * outlive its 15-minute token, which is acceptable because the socket only
 * ever tells clients to pull; the pull itself re-authenticates over HTTP.
 */
export default fp(
  async function socketPlugin(app) {
    const io = new Server(app.server, {
      serveClient: false,
      cors: { origin: app.config.corsOrigin },
    });

    if (typeof app.redis?.duplicate === 'function' && app.redis.status === 'ready') {
      // The main client fails fast for /health/ready; the adapter's pub/sub
      // pair must instead connect eagerly and queue while (re)connecting.
      const options = { lazyConnect: false, enableOfflineQueue: true, maxRetriesPerRequest: null };
      const pub = app.redis.duplicate(options);
      const sub = app.redis.duplicate(options);
      io.adapter(createAdapter(pub, sub));
      app.addHook('onClose', async () => {
        pub.disconnect();
        sub.disconnect();
      });
    } else {
      app.log.info('socket.io running without the redis adapter (single-node fanout)');
    }

    io.use((socket, next) => {
      try {
        const payload = app.jwt.verify(String(socket.handshake.auth?.token ?? ''));
        socket.data.userId = payload.sub;
        next();
      } catch {
        next(new Error('unauthorized'));
      }
    });

    io.on('connection', async (socket) => {
      try {
        const memberships = await app
          .db('workspace_members')
          .where({ user_id: socket.data.userId })
          .select('workspace_id');
        for (const membership of memberships) {
          await socket.join(`ws:${membership.workspace_id}`);
        }
        socket.emit('sync:ready', {
          workspaceIds: memberships.map((m) => m.workspace_id),
        });
      } catch (err) {
        app.log.warn({ err: err.message }, 'socket membership lookup failed');
        socket.disconnect(true);
      }
    });

    const relay = (event) => io.to(`ws:${event.workspaceId}`).emit('sync:changed', event);
    syncEvents.on('sync:changed', relay);

    app.decorate('io', io);
    app.addHook('onClose', async () => {
      syncEvents.off('sync:changed', relay);
      await io.close();
    });
  },
  {
    name: 'alliswell-socket',
    dependencies: ['alliswell-redis', 'alliswell-mysql', 'alliswell-auth'],
  },
);
