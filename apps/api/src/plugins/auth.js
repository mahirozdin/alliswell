import fp from 'fastify-plugin';
import jwt from '@fastify/jwt';

// Fixed token claims — OPH-023's authenticate decorator verifies against the same values.
export const JWT_ISSUER = 'alliswell-api';
export const JWT_AUDIENCE = 'alliswell-app';

/**
 * Registers @fastify/jwt for access tokens and decorates:
 * - `app.signAccessToken({ id, email })` → 15-minute JWT (`sub` = user id)
 * - `app.authenticate` — onRequest/preHandler guard; sets `request.user = { id, email }`
 * - `app.requireWorkspaceMember(request, workspaceId, { roles })` — authz helper
 * Refresh tokens are opaque and DB-backed — see src/lib/tokens.js.
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

    // Route guard (use as `onRequest: [app.authenticate]`). Verifies signature,
    // issuer, audience and expiry; expiry gets its own code so clients know to
    // try a refresh instead of forcing a re-login.
    app.decorate('authenticate', async function authenticate(request) {
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

    // Membership check for workspace-scoped routes. Returns the member row so
    // callers can branch on role; throws 403 for outsiders AND for insufficient
    // roles (existence of a workspace is not leaked to non-members).
    app.decorate(
      'requireWorkspaceMember',
      async function requireWorkspaceMember(request, workspaceId, { roles } = {}) {
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
