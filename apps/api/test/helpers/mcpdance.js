import crypto from 'node:crypto';

/**
 * The full OAuth 2.1 dance against an injected app (OPH-218): register a
 * client, walk the login+consent form, exchange the code with PKCE. Returns
 * everything later steps need. Suites share this so protocol/tool tests can
 * mint tokens without repeating the choreography.
 */

export const REDIRECT_URI = 'http://localhost:9876/callback';

export function pkcePair() {
  const verifier = crypto.randomBytes(32).toString('base64url');
  const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
  return { verifier, challenge };
}

export async function registerMcpClient(app, { name = 'Test Connector' } = {}) {
  const res = await app.inject({
    method: 'POST',
    url: '/oauth/register',
    payload: { redirect_uris: [REDIRECT_URI], client_name: name },
  });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.body}`);
  return res.json();
}

export function formTokenFrom(html) {
  const match = /name="formToken" value="([^"]+)"/.exec(html);
  if (!match) throw new Error('no formToken in page');
  return match[1];
}

export const formEncode = (fields) => new URLSearchParams(fields).toString();
export const FORM_HEADERS = { 'content-type': 'application/x-www-form-urlencoded' };

export async function authorize(
  app,
  { clientId, challenge, email, password, scope, state = 'st1', workspaceId },
) {
  const query = new URLSearchParams({
    client_id: clientId,
    redirect_uri: REDIRECT_URI,
    response_type: 'code',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state,
    ...(scope ? { scope } : {}),
  });
  const page = await app.inject({ method: 'GET', url: `/oauth/authorize?${query}` });
  if (page.statusCode !== 200) throw new Error(`authorize GET failed: ${page.statusCode}`);
  const formToken = formTokenFrom(page.body);
  const post = await app.inject({
    method: 'POST',
    url: '/oauth/authorize',
    headers: FORM_HEADERS,
    // A user with more than one workspace is asked WHICH one the connection
    // is for; the page re-renders with radios instead of redirecting. Tests
    // that sign in such a user must say which workspace they mean.
    payload: formEncode({
      formToken,
      email,
      password,
      decision: 'approve',
      ...(workspaceId ? { workspaceId } : {}),
    }),
  });
  if (post.statusCode !== 302)
    throw new Error(`authorize POST failed: ${post.statusCode} ${post.body}`);
  const location = new URL(post.headers.location);
  return { code: location.searchParams.get('code'), state: location.searchParams.get('state') };
}

export async function exchangeCode(app, { clientId, code, verifier }) {
  const res = await app.inject({
    method: 'POST',
    url: '/oauth/token',
    headers: FORM_HEADERS,
    payload: formEncode({
      grant_type: 'authorization_code',
      code,
      redirect_uri: REDIRECT_URI,
      client_id: clientId,
      code_verifier: verifier,
    }),
  });
  return res;
}

/** register → authorize → exchange; returns {client, tokens}. */
export async function fullDance(
  app,
  { email, password = 'test-password-1', scope, workspaceId } = {},
) {
  const client = await registerMcpClient(app);
  const { verifier, challenge } = pkcePair();
  const { code } = await authorize(app, {
    clientId: client.client_id,
    challenge,
    email,
    password,
    scope,
    workspaceId,
  });
  const res = await exchangeCode(app, { clientId: client.client_id, code, verifier });
  if (res.statusCode !== 200) throw new Error(`token exchange failed: ${res.body}`);
  return { client, tokens: res.json() };
}

/** One JSON-RPC call against /mcp with a bearer token. */
export function rpc(app, accessToken, method, params, id = 1) {
  return app.inject({
    method: 'POST',
    url: '/mcp',
    headers: { authorization: `Bearer ${accessToken}` },
    payload: { jsonrpc: '2.0', id, method, ...(params ? { params } : {}) },
  });
}

export async function callTool(app, accessToken, name, args) {
  const res = await rpc(app, accessToken, 'tools/call', { name, arguments: args });
  if (res.statusCode !== 200) throw new Error(`tools/call HTTP ${res.statusCode}: ${res.body}`);
  const body = res.json();
  if (body.error) throw new Error(`rpc error: ${JSON.stringify(body.error)}`);
  return body.result;
}
