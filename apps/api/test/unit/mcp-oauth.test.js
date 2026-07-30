import { describe, it, expect, beforeEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import {
  REDIRECT_URI,
  pkcePair,
  registerMcpClient,
  formTokenFrom,
  formEncode,
  FORM_HEADERS,
  authorize,
  exchangeCode,
  fullDance,
  rpc,
} from '../helpers/mcpdance.js';

/** OPH-218 — the OAuth 2.1 authorization server, corner by corner. */

let app;
let tables;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  await registerUser(app, { email: 'mcp-oauth@example.com' });
});

describe('discovery', () => {
  it('serves AS metadata on both paths and PR metadata on both forms', async () => {
    for (const path of [
      '/.well-known/oauth-authorization-server',
      '/.well-known/openid-configuration',
    ]) {
      const res = await app.inject({ method: 'GET', url: path });
      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.authorization_endpoint).toMatch(/\/oauth\/authorize$/);
      expect(body.code_challenge_methods_supported).toEqual(['S256']);
      expect(body.grant_types_supported).toEqual(['authorization_code', 'refresh_token']);
    }
    for (const path of [
      '/.well-known/oauth-protected-resource',
      '/.well-known/oauth-protected-resource/mcp',
    ]) {
      const res = await app.inject({ method: 'GET', url: path });
      expect(res.statusCode).toBe(200);
      expect(res.json().resource).toMatch(/\/mcp$/);
      expect(res.json().scopes_supported).toEqual(['mcp:read', 'mcp:write']);
    }
  });
});

describe('dynamic client registration', () => {
  it('registers a public client (no secret) with loopback redirects', async () => {
    const client = await registerMcpClient(app);
    expect(client.client_id).toHaveLength(26);
    expect(client.client_secret).toBeUndefined();
    expect(client.token_endpoint_auth_method).toBe('none');
  });

  it('rejects non-https non-loopback redirect uris', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/register',
      payload: { redirect_uris: ['http://evil.example/cb'] },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('invalid_redirect_uri');
  });

  it('mints a one-time secret for confidential clients and stores only its hash', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/register',
      payload: {
        redirect_uris: ['https://ai.example/cb'],
        token_endpoint_auth_method: 'client_secret_post',
      },
    });
    expect(res.statusCode).toBe(201);
    const secret = res.json().client_secret;
    expect(secret).toBeTruthy();
    const row = tables.oauth_clients.find((c) => c.id === res.json().client_id);
    expect(row.client_secret_hash).toHaveLength(64);
    expect(row.client_secret_hash).not.toContain(secret);
  });
});

describe('authorize', () => {
  it('unknown client → 400 page; unregistered redirect_uri → 400 page, NEVER a redirect', async () => {
    const unknown = await app.inject({
      method: 'GET',
      url: `/oauth/authorize?client_id=${'0'.repeat(26)}&redirect_uri=${REDIRECT_URI}&response_type=code`,
    });
    expect(unknown.statusCode).toBe(400);
    expect(unknown.headers.location).toBeUndefined();

    const client = await registerMcpClient(app);
    const mismatch = await app.inject({
      method: 'GET',
      url: `/oauth/authorize?client_id=${client.client_id}&redirect_uri=http://localhost:9876/other&response_type=code`,
    });
    expect(mismatch.statusCode).toBe(400);
    expect(mismatch.headers.location).toBeUndefined();
  });

  it('PKCE is mandatory: no challenge bounces back with invalid_request', async () => {
    const client = await registerMcpClient(app);
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/authorize?client_id=${client.client_id}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&response_type=code&state=s1`,
    });
    expect(res.statusCode).toBe(302);
    const location = new URL(res.headers.location);
    expect(location.searchParams.get('error')).toBe('invalid_request');
    expect(location.searchParams.get('state')).toBe('s1');
  });

  it('wrong password re-renders the form; deny bounces access_denied', async () => {
    const client = await registerMcpClient(app);
    const { challenge } = pkcePair();
    const query = new URLSearchParams({
      client_id: client.client_id,
      redirect_uri: REDIRECT_URI,
      response_type: 'code',
      code_challenge: challenge,
      code_challenge_method: 'S256',
    });
    const page = await app.inject({ method: 'GET', url: `/oauth/authorize?${query}` });
    const formToken = formTokenFrom(page.body);

    const wrong = await app.inject({
      method: 'POST',
      url: '/oauth/authorize',
      headers: FORM_HEADERS,
      payload: formEncode({
        formToken,
        email: 'mcp-oauth@example.com',
        password: 'not-the-password',
        decision: 'approve',
      }),
    });
    expect(wrong.statusCode).toBe(200);
    expect(wrong.body).toContain('parola hatalı');

    const deny = await app.inject({
      method: 'POST',
      url: '/oauth/authorize',
      headers: FORM_HEADERS,
      payload: formEncode({ formToken, email: 'x@y.z', password: 'x', decision: 'deny' }),
    });
    expect(deny.statusCode).toBe(302);
    expect(new URL(deny.headers.location).searchParams.get('error')).toBe('access_denied');
  });

  it('a tampered form token is a 400 page, not a grant', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/authorize',
      headers: FORM_HEADERS,
      payload: formEncode({
        formToken: 'garbage.token.here',
        email: 'mcp-oauth@example.com',
        password: 'test-password-1',
        decision: 'approve',
      }),
    });
    expect(res.statusCode).toBe(400);
  });
});

describe('token exchange', () => {
  it('the full dance issues a working bearer', async () => {
    const { tokens } = await fullDance(app, { email: 'mcp-oauth@example.com' });
    expect(tokens.token_type).toBe('Bearer');
    expect(tokens.scope).toBe('mcp:read mcp:write');
    const ping = await rpc(app, tokens.access_token, 'ping');
    expect(ping.statusCode).toBe(200);
    expect(ping.json().result).toEqual({});
  });

  it('a wrong PKCE verifier is invalid_grant', async () => {
    const client = await registerMcpClient(app);
    const { challenge } = pkcePair();
    const { code } = await authorize(app, {
      clientId: client.client_id,
      challenge,
      email: 'mcp-oauth@example.com',
      password: 'test-password-1',
    });
    const res = await exchangeCode(app, {
      clientId: client.client_id,
      code,
      verifier: 'completely-wrong-verifier-aaaaaaaaaaaa',
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('invalid_grant');
  });

  it('replaying a consumed code revokes the tokens it minted', async () => {
    const client = await registerMcpClient(app);
    const { verifier, challenge } = pkcePair();
    const { code } = await authorize(app, {
      clientId: client.client_id,
      challenge,
      email: 'mcp-oauth@example.com',
      password: 'test-password-1',
    });
    const first = await exchangeCode(app, { clientId: client.client_id, code, verifier });
    expect(first.statusCode).toBe(200);
    const access = first.json().access_token;
    expect((await rpc(app, access, 'ping')).statusCode).toBe(200);

    const replay = await exchangeCode(app, { clientId: client.client_id, code, verifier });
    expect(replay.statusCode).toBe(400);
    // …and the previously minted access token is now dead.
    expect((await rpc(app, access, 'ping')).statusCode).toBe(401);
  });

  it('refresh rotation works once; reuse burns the whole family', async () => {
    const { client, tokens } = await fullDance(app, { email: 'mcp-oauth@example.com' });
    const rotate = await app.inject({
      method: 'POST',
      url: '/oauth/token',
      headers: FORM_HEADERS,
      payload: formEncode({
        grant_type: 'refresh_token',
        refresh_token: tokens.refresh_token,
        client_id: client.client_id,
      }),
    });
    expect(rotate.statusCode).toBe(200);
    const fresh = rotate.json();
    expect((await rpc(app, fresh.access_token, 'ping')).statusCode).toBe(200);
    // The pre-rotation access token died with the rotation.
    expect((await rpc(app, tokens.access_token, 'ping')).statusCode).toBe(401);

    // Reusing the OLD refresh token kills everything, the fresh pair included.
    const reuse = await app.inject({
      method: 'POST',
      url: '/oauth/token',
      headers: FORM_HEADERS,
      payload: formEncode({
        grant_type: 'refresh_token',
        refresh_token: tokens.refresh_token,
        client_id: client.client_id,
      }),
    });
    expect(reuse.statusCode).toBe(400);
    expect((await rpc(app, fresh.access_token, 'ping')).statusCode).toBe(401);
  });

  it('RFC 7009 revocation kills the family and always answers 200', async () => {
    const { client, tokens } = await fullDance(app, { email: 'mcp-oauth@example.com' });
    const revoke = await app.inject({
      method: 'POST',
      url: '/oauth/revoke',
      headers: FORM_HEADERS,
      payload: formEncode({ token: tokens.refresh_token, client_id: client.client_id }),
    });
    expect(revoke.statusCode).toBe(200);
    expect((await rpc(app, tokens.access_token, 'ping')).statusCode).toBe(401);

    const unknown = await app.inject({
      method: 'POST',
      url: '/oauth/revoke',
      headers: FORM_HEADERS,
      payload: formEncode({ token: 'never-existed' }),
    });
    expect(unknown.statusCode).toBe(200);
  });

  it('a read-only scope request survives the dance', async () => {
    const { tokens } = await fullDance(app, {
      email: 'mcp-oauth@example.com',
      scope: 'mcp:read',
    });
    expect(tokens.scope).toBe('mcp:read');
  });
});

describe('the MCP_ENABLED switch', () => {
  it('MCP_ENABLED=false answers 404 on every oauth/mcp path', async () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      MCP_ENABLED: 'false',
    });
    const { app: off } = await buildTestApp({ config });
    for (const [method, url] of [
      ['GET', '/.well-known/oauth-authorization-server'],
      ['POST', '/oauth/register'],
      ['POST', '/mcp'],
    ]) {
      const res = await off.inject({ method, url, payload: method === 'POST' ? {} : undefined });
      expect(res.statusCode).toBe(404);
    }
  });
});
