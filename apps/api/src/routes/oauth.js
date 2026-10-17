import crypto from 'node:crypto';
import { coded } from '../lib/errors.js';
import { hashPassword, verifyPassword } from '../lib/passwords.js';
import { hashMcpToken } from '../lib/tokens.js';
import { OauthIdentityError, verifyIdentityToken } from '../lib/oauth-identity.js';
import { linkIdentity, matchSocialIdentity, touchIdentity } from '../db/identities.js';
import { totpStatus } from '../db/totp.js';
import { checkSignInFactors } from '../lib/sign-in-factors.js';
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
  upsertMetadataClient,
} from '../db/oauth.js';
import {
  isClientMetadataUrl,
  clientMetadataHost,
  fetchClientMetadata,
  validateClientMetadata,
} from '../lib/oauth-cimd.js';

/**
 * The MCP track's OAuth 2.1 authorization server (OPH-218, ADR-0022):
 * discovery documents, RFC 7591 dynamic client registration and client ID
 * metadata documents (ADR-0047), a PKCE-S256-only
 * authorization-code flow with a server-rendered login+consent page, token
 * rotation with family revocation, and RFC 7009 revocation.
 *
 * The API has no cookies and no session store, so the consent flow carries a
 * SIGNED form token (the integrations-google state-token precedent) binding
 * the POSTed credentials to the GET-validated OAuth parameters: hidden fields
 * are untrusted, the token is not. The same signed-token idea carries the
 * pending authorization through a Google / Apple sign-in round trip and on to
 * the second-factor step (OPH-366, ADR-0049). Token-endpoint errors speak OAuth's own
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
  input[type=email],input[type=password],input[type=text]{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #475569;background:#0f172a;color:#e2e8f0}
  .scopes{background:#0f172a;border-radius:8px;padding:12px;font-size:13px;margin-top:14px}
  .ws{margin:6px 0;font-size:14px} .err{color:#f87171;font-size:13px;margin-top:10px}
  .row{display:flex;flex-direction:row-reverse;gap:10px;margin-top:20px}
  button{flex:1;min-height:44px;padding:10px;border-radius:8px;border:0;font-size:14px;cursor:pointer}
  .approve{background:#2563eb;color:#fff} .deny{background:#334155;color:#cbd5e1}
  .or{display:flex;align-items:center;gap:10px;color:#94a3b8;font-size:13px;margin:22px 0 4px}
  .or::before,.or::after{content:"";flex:1;height:1px;background:#334155}
  .social button{display:flex;align-items:center;justify-content:center;gap:10px;width:100%;margin-top:10px;font-weight:500}
  .google{background:#fff;color:#1f1f1f;border:1px solid #747775}
  .apple{background:#000;color:#fff;border:1px solid #64748b}
  .who{color:#e2e8f0}
</style></head><body><div class="card">${body}</div></body></html>`;
}

/**
 * What the consent page calls a client. A metadata client chose its own name
 * in a document anyone can publish, so the host that published it is shown
 * beside the name — "Claude (claude.ai)" — and a look-alike name cannot hide
 * where it really comes from.
 */
function clientDisplayName(client) {
  const name = client.name ?? 'AI connector';
  const host = client.metadata_url ? clientMetadataHost(client.metadata_url) : null;
  return host ? `${name} (${host})` : name;
}

function renderAuthorizePage({
  clientName,
  formToken,
  scope,
  error,
  email,
  workspaces,
  providers,
  socialAction,
  authorizeAction,
}) {
  const scopeLines = scopeList(scope);
  const workspaceField = workspaceChoice(workspaces);
  return renderPage(
    'Connect',
    `<h1>Connect “${escapeHtml(clientName)}”</h1>
<p>Only continue if you started this from your own AI app (Claude, ChatGPT, …).<br>
<span style="color:#64748b">Bunu kendi yapay zekâ uygulamandan başlatmadıysan devam etme.</span></p>
<form method="post" action="${escapeHtml(authorizeAction)}">
  <input type="hidden" name="formToken" value="${escapeHtml(formToken)}">
  <label>Email</label><input type="email" name="email" required value="${escapeHtml(email ?? '')}">
  <label>Password <span style="color:#64748b">/ Parola</span></label><input type="password" name="password" required>
  ${workspaceField}
  <div class="scopes">${scopeLines}</div>
  ${error ? `<div class="err">${escapeHtml(error)}</div>` : ''}
  <div class="row">
    <button class="approve" name="decision" value="approve">Approve</button>
    <button class="deny" name="decision" value="deny" formnovalidate>Deny</button>
  </div>
</form>${socialForm({ formToken, providers, socialAction })}`,
  );
}

const PROVIDER_LABEL = { google: 'Google', apple: 'Apple', password: null };

// Brand marks, inline so the page still loads nothing from anywhere else.
const GOOGLE_MARK =
  '<svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>';
const APPLE_MARK =
  '<svg width="16" height="18" viewBox="0 0 814 1000" aria-hidden="true"><path fill="#fff" d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"/></svg>';

/**
 * The "Continue with Google / Apple" form (OPH-366). A SEPARATE form placed
 * after the password form, so Enter in the password field can never start a
 * provider sign-in. Nothing at all — not even the divider — when no provider
 * is configured on this instance.
 */
function socialForm({ formToken, providers, socialAction }) {
  if (!providers || providers.length === 0) return '';
  const buttons = providers
    .map((provider) =>
      provider === 'google'
        ? `<button class="google" name="provider" value="google">${GOOGLE_MARK}<span>Continue with Google</span></button>`
        : `<button class="apple" name="provider" value="apple">${APPLE_MARK}<span>Continue with Apple</span></button>`,
    )
    .join('');
  return `
<div class="or">or / veya</div>
<form method="post" action="${escapeHtml(socialAction)}" class="social">
  <input type="hidden" name="formToken" value="${escapeHtml(formToken)}">
  ${buttons}
</form>`;
}

function workspaceChoice(workspaces) {
  return workspaces && workspaces.length > 1
    ? `<label>Workspace <span style="color:#64748b">/ Çalışma alanı</span></label>` +
        workspaces
          .map(
            (ws, index) =>
              `<div class="ws"><label><input type="radio" name="workspaceId" value="${escapeHtml(ws.id)}" ${index === 0 ? 'checked' : ''}> ${escapeHtml(ws.name)}</label></div>`,
          )
          .join('')
    : '';
}

function scopeList(scope) {
  return scope
    .split(' ')
    .map((s) =>
      s === 'mcp:write'
        ? 'Create and complete tasks (with your approval in the AI app)'
        : 'Read your tasks, notes and projects',
    )
    .map((line) => `<div>• ${escapeHtml(line)}</div>`)
    .join('');
}

/**
 * The step after the first factor (OPH-366): who signed in, the second-factor
 * field when the account has one, the workspace choice, then Approve / Deny.
 * Always shown after a Google / Apple return, so the person approves the
 * account the provider actually picked, not the one they assumed.
 */
function renderStepPage({
  clientName,
  stepToken,
  continueAction,
  scope,
  user,
  via,
  needsCode,
  workspaces,
  error,
}) {
  const who = user.display_name
    ? `${escapeHtml(user.display_name)} (${escapeHtml(user.email)})`
    : escapeHtml(user.email);
  const provider = PROVIDER_LABEL[via];
  const signedIn = provider
    ? `Signed in as <strong class="who">${who}</strong> with ${provider}.<br><span style="color:#64748b">${provider} ile giriş yapıldı.</span>`
    : `Signed in as <strong class="who">${who}</strong>.<br><span style="color:#64748b">Giriş yapıldı.</span>`;
  const codeField = needsCode
    ? `<label for="totpCode">Authenticator or recovery code <span style="color:#64748b">/ Doğrulama ya da kurtarma kodu</span></label><input type="text" id="totpCode" name="totpCode" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false" required autofocus>`
    : '';
  return renderPage(
    'Connect',
    `<h1>Connect “${escapeHtml(clientName)}”</h1>
<p>${signedIn}</p>
<form method="post" action="${escapeHtml(continueAction)}">
  <input type="hidden" name="stepToken" value="${escapeHtml(stepToken)}">
  ${codeField}
  ${workspaceChoice(workspaces)}
  <div class="scopes">${scopeList(scope)}</div>
  ${error ? `<div class="err">${escapeHtml(error)}</div>` : ''}
  <div class="row">
    <button class="approve" name="decision" value="approve">Approve</button>
    <button class="deny" name="decision" value="deny" formnovalidate>Deny</button>
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
    ...(mcp.cimdEnabled ? { client_id_metadata_document_supported: true } : {}),
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

  // ── Clients: a registered ULID, or a metadata document URL (ADR-0047) ─────
  /**
   * The client row `clientId` names. A metadata URL maps to its own row; with
   * `fresh`, an expired (or never fetched) document is fetched first, and a
   * document that cannot be fetched or does not validate is an error, never
   * a stale fallback — its owner may have withdrawn a redirect URI on purpose.
   * Returns `{ client }` or `{ error }`.
   */
  async function resolveClient(clientId, { fresh = false } = {}) {
    if (!clientId) return { error: 'Unknown client_id' };
    if (!isClientMetadataUrl(clientId)) {
      const client = await app.db('oauth_clients').where({ id: clientId }).first();
      return client ? { client } : { error: 'Unknown client_id' };
    }
    if (!mcp.cimdEnabled) return { error: 'Unknown client_id' };
    const cached = await app.db('oauth_clients').where({ metadata_url: clientId }).first();
    const expired =
      !cached?.metadata_expires_at || new Date(cached.metadata_expires_at).getTime() <= Date.now();
    if (cached && !(fresh && expired)) return { client: cached };
    if (!fresh) return { error: 'Unknown client_id' };
    let fetched;
    try {
      fetched = await fetchClientMetadata(clientId);
    } catch (err) {
      app.log.warn({ err: err.message, code: err.code, clientId }, 'client metadata fetch failed');
      return { error: 'The client’s metadata document could not be loaded' };
    }
    const checked = validateClientMetadata(clientId, fetched.document, { redirectUriAllowed });
    if (checked.error) return { error: `Client metadata rejected: ${checked.error}` };
    const client = await upsertMetadataClient(app.db, {
      url: clientId,
      name: checked.name,
      redirectUris: checked.redirectUris,
      expiresAt: new Date(Date.now() + fetched.ttlSec * 1000),
    });
    return { client };
  }

  // ── Authorize: validate STRICTLY before rendering anything ────────────────
  async function validateAuthorizeParams(query) {
    const { client, error } = await resolveClient(query.client_id, { fresh: true });
    if (!client) return { fatal: error };
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

  // ── Consent helpers shared by the password, social and step paths ────────
  /** The validated authorization request, as every signed token carries it. */
  const grantParams = (p) => ({ c: p.c, r: p.r, s: p.s, st: p.st, cc: p.cc, res: p.res });
  const signFormToken = (p) =>
    app.jwt.sign({ purpose: 'mcp_authorize', ...grantParams(p) }, { expiresIn: 600 });

  /**
   * A signed token of exactly this purpose, or null. Purposes never cross:
   * a form token is not a step token, and neither is an access token (which
   * has no purpose at all).
   */
  function readToken(raw, purpose) {
    try {
      const payload = app.jwt.verify(String(raw ?? ''));
      return payload.purpose === purpose ? payload : null;
    } catch {
      return null;
    }
  }

  const expiredPage = (reply) =>
    reply
      .code(400)
      .type('text/html')
      .send(renderPage('Expired', '<h1>The form expired</h1><p>Start again from your AI app.</p>'));
  const unknownClientPage = (reply) =>
    reply.code(400).type('text/html').send(renderPage('Error', '<h1>Unknown client</h1>'));

  // OPH-366 (ADR-0049): Google / Apple on the consent page. A provider is
  // offered only when this instance can verify its tokens: Google needs the
  // web client id; Apple needs its Services ID AND an https public URL,
  // because Apple refuses http and localhost Return URLs.
  const signIn = app.config.signIn ?? {};
  const providerAudience = {
    google: signIn.googleWebClientId ?? null,
    apple: signIn.appleServiceId ?? null,
  };
  const socialProviders = [
    ...(providerAudience.google ? ['google'] : []),
    ...(providerAudience.apple && publicUrl?.startsWith('https://') ? ['apple'] : []),
  ];
  // Absolute, never action="": the consent page is also rendered by the
  // social callback, and an empty action there would post the password form
  // back to /oauth/authorize/callback.
  const authorizeAction = `${publicUrl}/oauth/authorize`;
  const socialAction = `${publicUrl}/oauth/authorize/social`;
  const socialCallback = `${publicUrl}/oauth/authorize/callback`;
  const continueAction = `${publicUrl}/oauth/authorize/continue`;

  const consentPage = (fields) =>
    renderAuthorizePage({ providers: socialProviders, socialAction, authorizeAction, ...fields });

  async function memberWorkspaceIds(userId) {
    const rows = await app
      .db('workspace_members')
      .where({ user_id: userId })
      .select('workspace_id');
    return rows.map((row) => row.workspace_id);
  }

  const workspaceRows = (ids) => app.db('workspaces').whereIn('id', ids).select('id', 'name');

  /**
   * The step page, with a fresh step token unless one is being re-used — a
   * re-render after a wrong code keeps the original expiry, so retrying
   * never extends the window.
   */
  async function sendStepPage(reply, { client, params, user, via, stepToken, error = null }) {
    const factors = await totpStatus(app.db, user.id);
    const ids = await memberWorkspaceIds(user.id);
    const token =
      stepToken ??
      app.jwt.sign(
        // `u`, never `sub`: this token must not read as an access token.
        { purpose: 'mcp_step', u: user.id, via, ...grantParams(params) },
        { expiresIn: 300 },
      );
    return reply.type('text/html').send(
      renderStepPage({
        clientName: clientDisplayName(client),
        stepToken: token,
        continueAction,
        scope: params.s,
        user,
        via,
        needsCode: factors.enrolled,
        workspaces: ids.length > 1 ? await workspaceRows(ids) : null,
        error: error ?? (ids.length === 0 ? 'This account has no workspace' : null),
      }),
    );
  }

  async function grantCode(reply, { client, params, userId, workspaceId }) {
    const code = await issueCode(app.db, auth.refreshSecret, {
      clientId: client.id,
      userId,
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
  }

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
    const formToken = signFormToken({
      c: checked.client.id,
      r: checked.redirectUri,
      s: checked.scope,
      st: checked.state,
      cc: checked.codeChallenge,
      res: checked.resource,
    });
    return reply.type('text/html').send(
      consentPage({
        clientName: clientDisplayName(checked.client),
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
    const params = readToken(body.formToken, 'mcp_authorize');
    if (!params) return expiredPage(reply);
    const client = await app.db('oauth_clients').where({ id: params.c }).first();
    if (!client) return unknownClientPage(reply);
    const rerender = (error, workspaces = null) =>
      reply.type('text/html').send(
        consentPage({
          clientName: clientDisplayName(client),
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
      .first('id', 'email', 'password_hash', 'display_name');
    const passwordOk = await verifyPassword(
      user?.password_hash ?? timingSafeDummyHash,
      String(body.password ?? ''),
    );
    if (!user || !user.password_hash || !passwordOk) {
      return rerender('Email or password is wrong / E-posta veya parola hatalı');
    }

    // OPH-366: the consent page is a sign-in, so it asks for the second
    // factor the same as /auth/login. Until then a password alone minted MCP
    // tokens for a TOTP-enrolled account. The password is not asked again:
    // the step page carries the proven first factor in a signed step token.
    // `checkSignInFactors` is the one /auth/login and /auth/oauth use
    // (OPH-381); without a code an enrolled account answers `required`
    // before any policy runs, which here means "show the step page".
    const outcome = await checkSignInFactors(app, { user, request });
    if (outcome.reason === 'required') {
      return sendStepPage(reply, { client, params, user, via: 'password' });
    }
    if (!outcome.ok) return rerender(outcome.message);

    const memberships = await memberWorkspaceIds(user.id);
    if (memberships.length === 0) {
      return rerender('This account has no workspace');
    }
    let workspaceId = body.workspaceId || null;
    if (memberships.length === 1) {
      workspaceId = memberships[0];
    } else if (!workspaceId) {
      return rerender(null, await workspaceRows(memberships));
    }
    if (!memberships.includes(workspaceId)) {
      return rerender('Pick one of your own workspaces');
    }
    return grantCode(reply, { client, params, userId: user.id, workspaceId });
  });

  // ── Google / Apple on the consent page (OPH-366, ADR-0049) ────────────────
  //
  // A server-side OpenID Connect redirect with response_mode=form_post: no
  // provider JavaScript on the page where passwords are typed, no client
  // secret. The pending authorization rides through the provider inside a
  // signed `state` (purpose mcp_social) together with a fresh nonce, and the
  // returning ID token must carry that nonce and name the one client the
  // redirect used. Nothing about the authorization itself — client,
  // redirect_uri, PKCE challenge, scope, state, resource — can change on the
  // way, because none of it is read from anywhere but the signed token.
  app.post('/oauth/authorize/social', { config: authRateLimit }, async (request, reply) => {
    assertConfigured();
    const body = request.body ?? {};
    const params = readToken(body.formToken, 'mcp_authorize');
    if (!params) return expiredPage(reply);
    const provider = String(body.provider ?? '');
    if (!socialProviders.includes(provider)) {
      return reply
        .code(400)
        .type('text/html')
        .send(renderPage('Error', '<h1>This sign-in option is not available here</h1>'));
    }
    const nonce = crypto.randomBytes(32).toString('base64url');
    const state = app.jwt.sign(
      { purpose: 'mcp_social', p: provider, n: nonce, ...grantParams(params) },
      { expiresIn: 600 },
    );
    const target =
      provider === 'google'
        ? new URL('https://accounts.google.com/o/oauth2/v2/auth')
        : new URL('https://appleid.apple.com/auth/authorize');
    target.search = new URLSearchParams(
      provider === 'google'
        ? {
            client_id: providerAudience.google,
            redirect_uri: socialCallback,
            response_type: 'id_token',
            response_mode: 'form_post',
            scope: 'openid email',
            nonce,
            state,
            prompt: 'select_account',
          }
        : {
            client_id: providerAudience.apple,
            redirect_uri: socialCallback,
            // Apple's web flow always pairs the id_token with a code; the
            // code is ignored — the id_token is all this needs.
            response_type: 'code id_token',
            response_mode: 'form_post',
            scope: 'email',
            nonce,
            state,
          },
    ).toString();
    return reply.redirect(target.toString(), 302);
  });

  app.post('/oauth/authorize/callback', { config: authRateLimit }, async (request, reply) => {
    assertConfigured();
    const body = request.body ?? {};
    const params = readToken(body.state, 'mcp_social');
    if (!params || !socialProviders.includes(params.p)) return expiredPage(reply);
    const client = await app.db('oauth_clients').where({ id: params.c }).first();
    if (!client) return unknownClientPage(reply);
    const label = PROVIDER_LABEL[params.p];

    // Every failure lands back on the consent page with a FRESH form token
    // minted from the same signed parameters, so the person can try another
    // way without starting over in their AI app.
    const backToConsent = (error) =>
      reply.type('text/html').send(
        consentPage({
          clientName: clientDisplayName(client),
          formToken: signFormToken(params),
          scope: params.s,
          error,
          email: null,
          workspaces: null,
        }),
      );

    // Apple: user_cancelled_authorize; Google: access_denied.
    if (body.error) return backToConsent('Sign-in was cancelled / Giriş iptal edildi');

    let identity;
    try {
      identity = await verifyIdentityToken(app.config, {
        provider: params.p,
        idToken: String(body.id_token ?? ''),
        nonce: params.n,
        audience: [providerAudience[params.p]],
      });
    } catch (err) {
      if (!(err instanceof OauthIdentityError)) throw err;
      // The reason goes to the log, never to the page.
      request.log.warn(
        { code: err.code, err: err.message, provider: params.p },
        'mcp consent: identity token rejected',
      );
      return backToConsent(
        `Could not verify your ${label} sign-in / ${label} girişi doğrulanamadı`,
      );
    }

    // The same account rules as the app's own sign-in, minus rule 3: this
    // page never creates an account (ADR-0049). Connecting an AI to a brand
    // new, empty workspace is never what was meant — it is the wrong
    // Google / Apple account picked in the provider's chooser.
    const match = await matchSocialIdentity(app.db, identity);
    if (match.kind === 'none' || match.kind === 'gone') {
      return backToConsent(
        `No AllisWell account uses this ${label} account yet. Sign up in the AllisWell app first, then connect again. / ` +
          `Bu ${label} hesabını kullanan bir AllisWell hesabı yok. Önce AllisWell uygulamasında kaydol, sonra yeniden bağlan.`,
      );
    }
    if (match.kind === 'link') {
      await app.db.transaction((trx) => linkIdentity(trx, match.user.id, identity));
    } else {
      await touchIdentity(app.db, match.identityId);
    }
    return sendStepPage(reply, { client, params, user: match.user, via: params.p });
  });

  app.post('/oauth/authorize/continue', { config: authRateLimit }, async (request, reply) => {
    assertConfigured();
    const body = request.body ?? {};
    const params = readToken(body.stepToken, 'mcp_step');
    if (!params) return expiredPage(reply);
    const client = await app.db('oauth_clients').where({ id: params.c }).first();
    if (!client) return unknownClientPage(reply);
    if (body.decision === 'deny') {
      return bounceRedirect(reply, params.r, 'access_denied', params.st);
    }
    const user = await app
      .db('users')
      .where({ id: params.u })
      .whereNull('deleted_at')
      .first('id', 'email', 'display_name');
    if (!user) return expiredPage(reply);
    const again = (error) =>
      sendStepPage(reply, {
        client,
        params,
        user,
        via: params.via,
        stepToken: body.stepToken,
        error,
      });

    // The workspace first: a wrong pick must not burn a one-time code.
    const ids = await memberWorkspaceIds(user.id);
    if (ids.length === 0) return again('This account has no workspace');
    const workspaceId = ids.length === 1 ? ids[0] : body.workspaceId || null;
    if (!workspaceId || !ids.includes(workspaceId)) {
      return again('Pick one of your own workspaces');
    }

    // Re-read, never trusted from the token: a factor turned on since the
    // step page was rendered still applies.
    // On this page a missing code is just a wrong one: the field is there.
    const outcome = await checkSignInFactors(app, {
      user,
      request,
      totpCode: String(body.totpCode ?? '').trim() || null,
    });
    if (outcome.reason === 'required' || outcome.reason === 'invalid') {
      return again('That code is not right / Kod doğru değil');
    }
    if (!outcome.ok) return again(outcome.message);

    return grantCode(reply, { client, params, userId: user.id, workspaceId });
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
    // A metadata client's row exists once /oauth/authorize has seen it; the
    // token endpoint never fetches — there is nothing to fetch for.
    const { client } = await resolveClient(id);
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
