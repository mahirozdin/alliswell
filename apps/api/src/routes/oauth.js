import crypto from 'node:crypto';
import { coded } from '../lib/errors.js';
import { hashPassword, verifyPassword } from '../lib/passwords.js';
import { hashMcpToken } from '../lib/tokens.js';
import {
  MCP_SCOPES,
  normalizeScope,
  clientRedirectUris,
  registerClient,
  issueCode,
  claimCode,
  issueTokenPair,
  revokeFamily,
  rotateRefreshToken,
  revokeToken,
} from '../db/oauth.js';

/**
 * The MCP track's OAuth 2.1 authorization server (OPH-218, ADR-0022):
 * discovery documents, RFC 7591 dynamic client registration, a PKCE-S256-only
 * authorization-code flow with a server-rendered login+consent page, token
 * rotation with family revocation, and RFC 7009 revocation.
 *
 * The API has no cookies and no session store, so the consent flow carries a
 * SIGNED form token (the integrations-google state-token precedent) binding
 * the POSTed credentials to the GET-validated OAuth parameters: hidden fields
 * are untrusted, the token is not. Token-endpoint errors speak OAuth's own
 * `{error, error_description}` dialect, not the fastify envelope — that is
 * what RFC-compliant clients parse.
 */

/** Loopback redirect URIs are legal for dev tools (MCP Inspector). */
function redirectUriAllowed(uri) {
  let url;
  try {
    url = new URL(uri);
  } catch {
    return false;
  }
  if (url.protocol === 'https:') return true;
  if (url.protocol !== 'http:') return false;
  return url.hostname === 'localhost' || url.hostname === '127.0.0.1';
}

function pkceChallengeFrom(verifier) {
  return crypto.createHash('sha256').update(verifier).digest('base64url');
}

const escapeHtml = (value) =>
  String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

function renderPage(title, body) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} — AllisWell</title>
<style>
  body{font-family:-apple-system,system-ui,sans-serif;background:#0f172a;color:#e2e8f0;display:grid;place-items:center;min-height:100vh;margin:0}
  .card{background:#1e293b;border:1px solid #334155;border-radius:16px;padding:32px;max-width:380px;width:calc(100% - 48px)}
  h1{font-size:20px;margin:0 0 4px} p{color:#94a3b8;font-size:14px;line-height:1.5}
  label{display:block;font-size:13px;color:#cbd5e1;margin:14px 0 4px}
  input[type=email],input[type=password]{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #475569;background:#0f172a;color:#e2e8f0}
  .scopes{background:#0f172a;border-radius:8px;padding:12px;font-size:13px;margin-top:14px}
  .ws{margin:6px 0;font-size:14px} .err{color:#f87171;font-size:13px;margin-top:10px}
  .row{display:flex;gap:10px;margin-top:20px}
  button{flex:1;padding:10px;border-radius:8px;border:0;font-size:14px;cursor:pointer}
  .approve{background:#2563eb;color:#fff} .deny{background:#334155;color:#cbd5e1}
</style></head><body><div class="card">${body}</div></body></html>`;
}

function renderAuthorizePage({ clientName, formToken, scope, error, email, workspaces }) {
  const scopeLines = scope
    .split(' ')
    .map((s) =>
      s === 'mcp:write'
        ? 'Create and complete tasks (with your approval in the AI app)'
        : 'Read your tasks, notes and projects',
    )
    .map((line) => `<div>• ${escapeHtml(line)}</div>`)
    .join('');
  const workspaceField =
    workspaces && workspaces.length > 1
      ? `<label>Workspace <span style="color:#64748b">/ Çalışma alanı</span></label>` +
        workspaces
          .map(
            (ws, index) =>
              `<div class="ws"><label><input type="radio" name="workspaceId" value="${escapeHtml(ws.id)}" ${index === 0 ? 'checked' : ''}> ${escapeHtml(ws.name)}</label></div>`,
          )
          .join('')
      : '';
  return renderPage(
    'Connect',
    `<h1>Connect “${escapeHtml(clientName)}”</h1>
<p>Only continue if you started this from your own AI app (Claude, ChatGPT, …).<br>
<span style="color:#64748b">Bunu kendi yapay zekâ uygulamandan başlatmadıysan devam etme.</span></p>
<form method="post" action="">
  <input type="hidden" name="formToken" value="${escapeHtml(formToken)}">
  <label>Email</label><input type="email" name="email" required value="${escapeHtml(email ?? '')}">
  <label>Password <span style="color:#64748b">/ Parola</span></label><input type="password" name="password" required>
  ${workspaceField}
  <div class="scopes">${scopeLines}</div>
  ${error ? `<div class="err">${escapeHtml(error)}</div>` : ''}
  <div class="row">
    <button class="deny" name="decision" value="deny">Deny</button>
    <button class="approve" name="decision" value="approve">Approve</button>
  </div>
</form>`,
  );
}

export default async function oauthRoutes(app) {
  const { mcp, auth } = app.config;
  const publicUrl =
    mcp.publicUrl ??
    (app.config.env !== 'production' ? `http://localhost:${app.config.port}` : null);
  // In production the issuer must be HTTPS — an http one is treated as absent.
  const configured =
    mcp.enabled &&
    Boolean(publicUrl) &&
    (app.config.env !== 'production' || publicUrl.startsWith('https://'));

  function assertConfigured() {
    if (!configured) {
      throw coded(
        app.httpErrors.notFound('MCP is not configured on this instance'),
        'MCP_NOT_CONFIGURED',
      );
    }
  }

  const authRateLimit = {
    rateLimit: { max: app.config.rateLimitAuthMax, timeWindow: '1 minute' },
  };
  // Same posture as /auth/login: unknown emails burn a real argon2 verify.
  const timingSafeDummyHash = await hashPassword(crypto.randomUUID());

  // The consent form posts urlencoded; parsers are plugin-scoped in Fastify,
  // so this hand-rolled six-liner exists only inside the oauth routes.
  app.addContentTypeParser(
    'application/x-www-form-urlencoded',
    { parseAs: 'string' },
    (request, body, done) => {
      done(null, Object.fromEntries(new URLSearchParams(body)));
    },
  );

  // ── Discovery ─────────────────────────────────────────────────────────────
  const authServerMetadata = () => ({
    issuer: publicUrl,
    authorization_endpoint: `${publicUrl}/oauth/authorize`,
    token_endpoint: `${publicUrl}/oauth/token`,
    registration_endpoint: `${publicUrl}/oauth/register`,
    revocation_endpoint: `${publicUrl}/oauth/revoke`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'refresh_token'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none', 'client_secret_post', 'client_secret_basic'],
    scopes_supported: MCP_SCOPES,
  });
  const protectedResourceMetadata = () => ({
    resource: `${publicUrl}/mcp`,
    authorization_servers: [publicUrl],
    bearer_methods_supported: ['header'],
    scopes_supported: MCP_SCOPES,
  });

  for (const path of [
    '/.well-known/oauth-authorization-server',
    '/.well-known/openid-configuration',
  ]) {
    app.get(path, { config: { rateLimit: false } }, async () => {
      assertConfigured();
      return authServerMetadata();
    });
  }
  // 2025-06-18 clients try the path-suffixed protected-resource form first.
  for (const path of [
    '/.well-known/oauth-protected-resource',
    '/.well-known/oauth-protected-resource/mcp',
  ]) {
    app.get(path, { config: { rateLimit: false } }, async () => {
      assertConfigured();
      return protectedResourceMetadata();
    });
  }

  // ── RFC 7591 dynamic client registration (open, rate-limited) ─────────────
  app.post(
    '/oauth/register',
    {
      config: authRateLimit,
      schema: {
        body: {
          type: 'object',
          additionalProperties: true, // RFC 7591 clients send extras; ignore them
          required: ['redirect_uris'],
          properties: {
            redirect_uris: {
              type: 'array',
              minItems: 1,
              maxItems: 10,
              items: { type: 'string', minLength: 1, maxLength: 500 },
            },
            client_name: { type: 'string', maxLength: 255 },
            token_endpoint_auth_method: {
              type: 'string',
              enum: ['none', 'client_secret_post', 'client_secret_basic'],
            },
          },
        },
      },
    },
    async (request, reply) => {
      assertConfigured();
      const uris = request.body.redirect_uris;
      if (!uris.every(redirectUriAllowed)) {
        return reply.code(400).send({
          error: 'invalid_redirect_uri',
          error_description: 'redirect_uris must be https (or http on localhost)',
        });
      }
      const method = request.body.token_endpoint_auth_method ?? 'none';
      const { row, clientSecret } = await registerClient(app.db, auth.refreshSecret, {
        name: request.body.client_name ?? null,
        redirectUris: uris,
        tokenEndpointAuthMethod: method,
      });
      return reply.code(201).send({
        client_id: row.id,
        client_name: row.name ?? undefined,
        redirect_uris: uris,
        token_endpoint_auth_method: method,
        grant_types: ['authorization_code', 'refresh_token'],
        response_types: ['code'],
        ...(clientSecret ? { client_secret: clientSecret } : {}),
      });
    },
  );

  // ── Authorize: validate STRICTLY before rendering anything ────────────────
  async function validateAuthorizeParams(query) {
    const client = query.client_id
      ? await app.db('oauth_clients').where({ id: query.client_id }).first()
      : null;
    if (!client) return { fatal: 'Unknown client_id' };
    const redirectUri = query.redirect_uri;
    if (!redirectUri || !clientRedirectUris(client).includes(redirectUri)) {
      // Mismatch → a 400 PAGE, never a redirect to an unregistered address.
      return { fatal: 'redirect_uri is not registered for this client' };
    }
    const bounce = (error) => ({ client, redirectUri, bounce: error });
    if (query.response_type !== 'code') return bounce('unsupported_response_type');
    if (!query.code_challenge || query.code_challenge_method !== 'S256') {
      return bounce('invalid_request'); // PKCE S256 is mandatory — no plain, no implicit
    }
    const scope = normalizeScope(query.scope);
    if (scope === null) return bounce('invalid_scope');
    if (query.resource && query.resource !== `${publicUrl}/mcp`) return bounce('invalid_target');
    return {
      client,
      redirectUri,
      scope,
      state: query.state ?? null,
      codeChallenge: query.code_challenge,
      resource: query.resource ?? null,
    };
  }

  const bounceRedirect = (reply, redirectUri, error, state) => {
    const url = new URL(redirectUri);
    url.searchParams.set('error', error);
    if (state) url.searchParams.set('state', state);
    return reply.redirect(url.toString(), 302);
  };

  app.get('/oauth/authorize', { config: authRateLimit }, async (request, reply) => {
    assertConfigured();
    const checked = await validateAuthorizeParams(request.query);
    if (checked.fatal) {
      return reply
        .code(400)
        .type('text/html')
        .send(renderPage('Error', `<h1>Cannot continue</h1><p>${escapeHtml(checked.fatal)}</p>`));
    }
    if (checked.bounce) {
      return bounceRedirect(reply, checked.redirectUri, checked.bounce, request.query.state);
    }
    const formToken = app.jwt.sign(
      {
        purpose: 'mcp_authorize',
        c: checked.client.id,
        r: checked.redirectUri,
        s: checked.scope,
        st: checked.state,
        cc: checked.codeChallenge,
        res: checked.resource,
      },
      { expiresIn: 600 },
    );
    return reply.type('text/html').send(
      renderAuthorizePage({
        clientName: checked.client.name ?? 'AI connector',
        formToken,
        scope: checked.scope,
        error: null,
        email: null,
        workspaces: null,
      }),
    );
  });

  app.post('/oauth/authorize', { config: authRateLimit }, async (request, reply) => {
    assertConfigured();
    const body = request.body ?? {};
    let params;
    try {
      params = app.jwt.verify(String(body.formToken ?? ''));
      if (params.purpose !== 'mcp_authorize') throw new Error('wrong purpose');
    } catch {
      return reply
        .code(400)
        .type('text/html')
        .send(
          renderPage('Expired', '<h1>The form expired</h1><p>Start again from your AI app.</p>'),
        );
    }
    const client = await app.db('oauth_clients').where({ id: params.c }).first();
    if (!client) {
      return reply.code(400).type('text/html').send(renderPage('Error', '<h1>Unknown client</h1>'));
    }
    const rerender = (error, workspaces = null) =>
      reply.type('text/html').send(
        renderAuthorizePage({
          clientName: client.name ?? 'AI connector',
          formToken: body.formToken,
          scope: params.s,
          error,
          email: body.email ?? null,
          workspaces,
        }),
      );

    if (body.decision === 'deny') {
      return bounceRedirect(reply, params.r, 'access_denied', params.st);
    }

    const email = String(body.email ?? '').toLowerCase();
    const user = await app
      .db('users')
      .where({ email })
      .whereNull('deleted_at')
      .first('id', 'email', 'password_hash');
    const passwordOk = await verifyPassword(
      user?.password_hash ?? timingSafeDummyHash,
      String(body.password ?? ''),
    );
    if (!user || !user.password_hash || !passwordOk) {
      return rerender('Email or password is wrong / E-posta veya parola hatalı');
    }

    const memberships = await app
      .db('workspace_members')
      .where({ user_id: user.id })
      .select('workspace_id');
    if (memberships.length === 0) {
      return rerender('This account has no workspace');
    }
    let workspaceId = body.workspaceId || null;
    if (memberships.length === 1) {
      workspaceId = memberships[0].workspace_id;
    } else if (!workspaceId) {
      const rows = await app
        .db('workspaces')
        .whereIn(
          'id',
          memberships.map((m) => m.workspace_id),
        )
        .select('id', 'name');
      return rerender(null, rows);
    }
    if (!memberships.some((m) => m.workspace_id === workspaceId)) {
      return rerender('Pick one of your own workspaces');
    }

    const code = await issueCode(app.db, auth.refreshSecret, {
      clientId: client.id,
      userId: user.id,
      workspaceId,
      scope: params.s,
      redirectUri: params.r,
      codeChallenge: params.cc,
      resource: params.res,
      ttlSec: mcp.codeTtlSec,
    });
    const url = new URL(params.r);
    url.searchParams.set('code', code);
    if (params.st) url.searchParams.set('state', params.st);
    return reply.redirect(url.toString(), 302);
  });

  // ── Token endpoint (OAuth-shaped errors, not the fastify envelope) ────────
  function oauthError(reply, status, error, description) {
    return reply.code(status).send({ error, error_description: description });
  }

  /** Client auth: 'none' needs the id; secret methods verify the digest. */
  async function authenticateClient(request, reply, clientId) {
    let id = clientId;
    let secret = request.body?.client_secret ?? null;
    const header = request.headers.authorization ?? '';
    if (header.startsWith('Basic ')) {
      const [basicId, basicSecret] = Buffer.from(header.slice(6), 'base64')
        .toString('utf8')
        .split(':');
      id = id || decodeURIComponent(basicId ?? '');
      secret = secret ?? decodeURIComponent(basicSecret ?? '');
    }
    if (!id)
      return { error: () => oauthError(reply, 400, 'invalid_request', 'client_id required') };
    const client = await app.db('oauth_clients').where({ id }).first();
    if (!client) return { error: () => oauthError(reply, 401, 'invalid_client', 'unknown client') };
    if (client.token_endpoint_auth_method !== 'none') {
      const expected = client.client_secret_hash;
      const presented = secret
        ? hashMcpToken('client_secret', String(secret), auth.refreshSecret)
        : null;
      if (!expected || !presented || expected !== presented) {
        return { error: () => oauthError(reply, 401, 'invalid_client', 'client auth failed') };
      }
    }
    return { client };
  }

  app.post('/oauth/token', { config: authRateLimit }, async (request, reply) => {
    assertConfigured();
    const body = request.body ?? {};
    const grantType = body.grant_type;

    if (grantType === 'authorization_code') {
      const { client, error } = await authenticateClient(request, reply, body.client_id);
      if (error) return error();
      const claim = await claimCode(app.db, auth.refreshSecret, String(body.code ?? ''));
      if (!claim) return oauthError(reply, 400, 'invalid_grant', 'unknown code');
      const { row, replayed } = claim;
      if (replayed) {
        // OAuth 2.1 §4.1.2: a replayed code burns everything it ever minted.
        // The family id IS the code row id, so the lineage is findable.
        await revokeFamily(app.db, row.id);
        return oauthError(reply, 400, 'invalid_grant', 'code already used');
      }
      if (row.client_id !== client.id) {
        return oauthError(reply, 400, 'invalid_grant', 'code belongs to another client');
      }
      if (new Date(row.expires_at).getTime() <= Date.now()) {
        return oauthError(reply, 400, 'invalid_grant', 'code expired');
      }
      if (String(body.redirect_uri ?? '') !== row.redirect_uri) {
        return oauthError(reply, 400, 'invalid_grant', 'redirect_uri mismatch');
      }
      const verifier = String(body.code_verifier ?? '');
      if (!verifier || pkceChallengeFrom(verifier) !== row.code_challenge) {
        return oauthError(reply, 400, 'invalid_grant', 'PKCE verification failed');
      }
      if (body.resource && String(body.resource) !== `${publicUrl}/mcp`) {
        return oauthError(reply, 400, 'invalid_target', 'unknown resource');
      }
      const tokens = await issueTokenPair(app.db, auth.refreshSecret, {
        clientId: client.id,
        userId: row.user_id,
        workspaceId: row.workspace_id,
        scope: row.scope,
        familyId: row.id, // lineage: replay revocation can find the family
        accessTtlSec: mcp.accessTtlSec,
        refreshTtlDays: mcp.refreshTtlDays,
      });
      await app.db('oauth_clients').where({ id: client.id }).update({ last_used_at: new Date() });
      return {
        access_token: tokens.accessToken,
        token_type: 'Bearer',
        expires_in: tokens.expiresInSec,
        refresh_token: tokens.refreshToken,
        scope: row.scope,
      };
    }

    if (grantType === 'refresh_token') {
      const { error } = await authenticateClient(request, reply, body.client_id);
      if (error) return error();
      const result = await rotateRefreshToken(
        app.db,
        auth.refreshSecret,
        String(body.refresh_token ?? ''),
        { accessTtlSec: mcp.accessTtlSec, refreshTtlDays: mcp.refreshTtlDays },
      );
      if (result.outcome !== 'rotated') {
        return oauthError(reply, 400, 'invalid_grant', 'refresh token is not usable');
      }
      return {
        access_token: result.tokens.accessToken,
        token_type: 'Bearer',
        expires_in: result.tokens.expiresInSec,
        refresh_token: result.tokens.refreshToken,
        scope: result.scope,
      };
    }

    return oauthError(
      reply,
      400,
      'unsupported_grant_type',
      'use authorization_code or refresh_token',
    );
  });

  // ── RFC 7009 revocation: always 200, existence never asserted ─────────────
  app.post('/oauth/revoke', { config: authRateLimit }, async (request, reply) => {
    assertConfigured();
    const token = String(request.body?.token ?? '');
    if (token) await revokeToken(app.db, auth.refreshSecret, token);
    return reply.code(200).send({});
  });
}
