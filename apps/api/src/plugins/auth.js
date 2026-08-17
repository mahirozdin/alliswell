import fp from 'fastify-plugin';
import jwt from '@fastify/jwt';
import { bearerApiKey } from '../lib/api-keys.js';
import { hashApiKey } from '../lib/tokens.js';

// Fixed token claims — OPH-023's authenticate decorator verifies against the same values.
export const JWT_ISSUER = 'alliswell-api';
export const JWT_AUDIENCE = 'alliswell-app';

// How stale `api_keys.last_used_at` may get (ADR-0032 §6, the MCP pattern).
const LAST_USED_THROTTLE_MS = 60_000;

/**
 * Registers @fastify/jwt for access tokens and decorates:
 * - `app.signAccessToken({ id, email })` → 15-minute JWT (`sub` = user id)
 * - `app.authenticate` — onRequest/preHandler guard; sets `request.user = { id, email }`
 * - `app.requireWorkspaceMember(request, workspaceId, { roles })` — authz helper
 * - `app.rejectApiKeys` — preHandler for the routes keys may never reach
 * Refresh tokens are opaque and DB-backed — see src/lib/tokens.js.
 *
 * OPH-264 made `authenticate` dual-mode (ADR-0032): an `Authorization: Bearer
 * awk_…` header is an API key, anything else is a JWT. This is now the single
 * most security-critical function in the codebase — it decides `request.user`
 * for all ~80 routes — so the JWT branch is byte-for-byte what it was, and the
 * existing auth suites are its regression proof.
 */
export default fp(
  async function authPlugin(app) {
    const { accessSecret, accessTtlSec } = app.config.auth;

    await app.register(jwt, {
      secret: accessSecret,
      sign: {
        expiresIn: accessTtlSec, // @fastify/jwt v10 treats a number as seconds
        iss: JWT_ISSUER,
        aud: JWT_AUDIENCE,
      },
      verify: {
        allowedIss: JWT_ISSUER,
        allowedAud: JWT_AUDIENCE,
      },
      // What request.user looks like after jwtVerify.
      formatUser: (payload) => ({ id: payload.sub, email: payload.email }),
    });

    app.decorate('signAccessToken', (user) => app.jwt.sign({ sub: user.id, email: user.email }));

    function keyRejected(message, code) {
      const err = app.httpErrors.unauthorized(message);
      err.code = code;
      return err;
    }

    /**
     * The API-key branch (ADR-0032). Every failure answers the same 401 shape
     * as a bad JWT — a caller learns that this key does not work, never
     * whether some other key exists.
     */
    async function authenticateApiKey(request, token) {
      const row = await app
        .db('api_keys')
        .where({ key_hash: hashApiKey(token, app.config.auth.refreshSecret) })
        .first();
      if (!row) throw keyRejected('Invalid API key', 'AUTH_INVALID_API_KEY');
      if (row.revoked_at) throw keyRejected('This API key was revoked', 'AUTH_API_KEY_REVOKED');
      if (row.expires_at && new Date(row.expires_at).getTime() <= Date.now()) {
        throw keyRejected('This API key has expired', 'AUTH_API_KEY_EXPIRED');
      }
      // The owner may have deleted their account since the key was minted.
      const user = await app
        .db('users')
        .where({ id: row.user_id })
        .whereNull('deleted_at')
        .first('id', 'email');
      if (!user) throw keyRejected('Invalid API key', 'AUTH_INVALID_API_KEY');

      request.user = { id: user.id, email: user.email };
      request.apiKeyAuth = { keyId: row.id, workspaceId: row.workspace_id };

      // Throttled liveness stamp (~1/min): the list screen needs a date to
      // make revoking a decision, not a counter. Fire-and-forget — a failed
      // stamp must never fail the request it was describing.
      const last = row.last_used_at ? new Date(row.last_used_at).getTime() : 0;
      if (Date.now() - last > LAST_USED_THROTTLE_MS) {
        app
          .db('api_keys')
          .where({ id: row.id })
          .update({ last_used_at: new Date() })
          .catch(() => {});
      }
    }

    // Route guard (use as `onRequest: [app.authenticate]`). Verifies signature,
    // issuer, audience and expiry; expiry gets its own code so clients know to
    // try a refresh instead of forcing a re-login.
    app.decorate('authenticate', async function authenticate(request) {
      // The `awk_` prefix decides the mode before any work happens (ADR-0032
      // §1). A key is never fed to jwtVerify and a JWT is never hashed.
      const apiKey = bearerApiKey(request);
      if (apiKey) return authenticateApiKey(request, apiKey);

      try {
        await request.jwtVerify();
      } catch (cause) {
        const expired = cause?.code === 'FST_JWT_AUTHORIZATION_TOKEN_EXPIRED';
        const err = app.httpErrors.unauthorized(
          expired ? 'Access token expired' : 'Invalid or missing access token',
        );
        err.code = expired ? 'AUTH_TOKEN_EXPIRED' : 'AUTH_INVALID_TOKEN';
        throw err;
      }
    });

    /**
     * The doors keys may never open (ADR-0032 §4): account deletion, `/ai/*`
     * (BYOK provider secrets and the user's model spend) and key management
     * itself — a key that can mint keys makes revocation meaningless.
     *
     * Use as `preHandler`, never `onRequest`: it has to run AFTER
     * `authenticate` has decided what this request is.
     */
    app.decorate('rejectApiKeys', async function rejectApiKeys(request) {
      if (!request.apiKeyAuth) return;
      const err = app.httpErrors.forbidden('API keys cannot be used on this endpoint');
      err.code = 'AUTH_APIKEY_FORBIDDEN';
      throw err;
    });

    // Membership check for workspace-scoped routes. Returns the member row so
    // callers can branch on role; throws 403 for outsiders AND for insufficient
    // roles (existence of a workspace is not leaked to non-members).
    app.decorate(
      'requireWorkspaceMember',
      async function requireWorkspaceMember(request, workspaceId, { roles } = {}) {
        // An API key is bound to ONE workspace — that binding is the blast
        // radius (ADR-0032 §3), so it is checked before membership: the owner
        // may well be a member of the other workspace too, and the key still
        // has no business there.
        if (request.apiKeyAuth && request.apiKeyAuth.workspaceId !== workspaceId) {
          const err = app.httpErrors.forbidden('This API key is bound to a different workspace');
          err.code = 'AUTH_APIKEY_WORKSPACE';
          throw err;
        }
        const member = await app
          .db('workspace_members')
          .where({ workspace_id: workspaceId, user_id: request.user.id })
          .first('id', 'role');
        if (!member || (roles && !roles.includes(member.role))) {
          const err = app.httpErrors.forbidden('You do not have access to this workspace');
          err.code = 'AUTH_WORKSPACE_FORBIDDEN';
          throw err;
        }
        return member;
      },
    );
  },
  { name: 'alliswell-auth' },
);
