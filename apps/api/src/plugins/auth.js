import fp from 'fastify-plugin';
import jwt from '@fastify/jwt';

// Fixed token claims — OPH-023's authenticate decorator verifies against the same values.
export const JWT_ISSUER = 'alliswell-api';
export const JWT_AUDIENCE = 'alliswell-app';

/**
 * Registers @fastify/jwt for access tokens and decorates
 * `app.signAccessToken({ id, email })` → 15-minute JWT (`sub` = user id).
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
    });

    app.decorate('signAccessToken', (user) => app.jwt.sign({ sub: user.id, email: user.email }));
  },
  { name: 'alliswell-auth' },
);
