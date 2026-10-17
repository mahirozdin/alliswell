import {
  FORM_HEADERS,
  REDIRECT_URI,
  formEncode,
  formTokenFrom,
  registerMcpClient,
  pkcePair,
} from './mcpdance.js';

/**
 * The consent page's Google / Apple round trip (OPH-366), walked the way a
 * browser walks it: GET the consent page, press "Continue with …", follow the
 * provider URL's state + nonce, and come back to the callback with an ID
 * token the test signed. The provider's own page is the only part skipped.
 */

export async function openConsent(app, { clientId, challenge, state = 'st1' }) {
  const query = new URLSearchParams({
    client_id: clientId,
    redirect_uri: REDIRECT_URI,
    response_type: 'code',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state,
  });
  const page = await app.inject({ method: 'GET', url: `/oauth/authorize?${query}` });
  if (page.statusCode !== 200) throw new Error(`authorize GET failed: ${page.statusCode}`);
  return page;
}

/** Press "Continue with <provider>"; returns the provider URL's parameters. */
export async function pressProvider(app, { formToken, provider }) {
  const res = await app.inject({
    method: 'POST',
    url: '/oauth/authorize/social',
    headers: FORM_HEADERS,
    payload: formEncode({ formToken, provider }),
  });
  if (res.statusCode !== 302) throw new Error(`social POST failed: ${res.statusCode} ${res.body}`);
  const url = new URL(res.headers.location);
  return { url, params: Object.fromEntries(url.searchParams) };
}

export function postCallback(app, fields) {
  return app.inject({
    method: 'POST',
    url: '/oauth/authorize/callback',
    headers: FORM_HEADERS,
    payload: formEncode(fields),
  });
}

export function postContinue(app, fields) {
  return app.inject({
    method: 'POST',
    url: '/oauth/authorize/continue',
    headers: FORM_HEADERS,
    payload: formEncode(fields),
  });
}

export function stepTokenFrom(html) {
  const match = /name="stepToken" value="([^"]+)"/.exec(html);
  if (!match) throw new Error('no stepToken in page');
  return match[1];
}

/**
 * Register a client, open consent and press the provider button. Returns
 * what the callback needs (`state`, `nonce`) plus the client and PKCE pair.
 */
export async function beginSocial(app, { provider = 'google', state = 'st1' } = {}) {
  const client = await registerMcpClient(app);
  const pkce = pkcePair();
  const page = await openConsent(app, {
    clientId: client.client_id,
    challenge: pkce.challenge,
    state,
  });
  const { url, params } = await pressProvider(app, {
    formToken: formTokenFrom(page.body),
    provider,
  });
  return { client, pkce, url, providerParams: params, state: params.state, nonce: params.nonce };
}
