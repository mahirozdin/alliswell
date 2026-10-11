import { describe, it, expect, beforeEach, vi } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { pkcePair, formTokenFrom, formEncode, FORM_HEADERS, rpc } from '../helpers/mcpdance.js';

// The network fetch is replaced; everything that judges what it returns is real.
vi.mock('../../src/lib/oauth-cimd.js', async (importOriginal) => ({
  ...(await importOriginal()),
  fetchClientMetadata: vi.fn(),
}));

const cimd = await import('../../src/lib/oauth-cimd.js');
const real = await vi.importActual('../../src/lib/oauth-cimd.js');

/** ADR-0047 — clients that name themselves by a metadata document URL. */

const CLIENT_URL = 'https://claude.example/oauth/client-metadata.json';
const REDIRECT = 'https://claude.example/api/mcp/auth_callback';
const EMAIL = 'mcp-cimd@example.com';
const PASSWORD = 'test-password-1';

const document = (overrides = {}) => ({
  client_id: CLIENT_URL,
  client_name: 'Claude',
  redirect_uris: [REDIRECT],
  grant_types: ['authorization_code', 'refresh_token'],
  token_endpoint_auth_method: 'none',
  ...overrides,
});

let app;
let tables;

async function setup() {
  cimd.fetchClientMetadata.mockReset();
  cimd.fetchClientMetadata.mockResolvedValue({ document: document(), ttlSec: 3600 });
  ({ app, tables } = await buildTestApp());
  await registerUser(app, { email: EMAIL });
}

function authorizeUrl({ clientId = CLIENT_URL, redirectUri = REDIRECT, challenge }) {
  const query = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: 'code',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state: 'st1',
  });
  return `/oauth/authorize?${query}`;
}

async function dance() {
  const { verifier, challenge } = pkcePair();
  const page = await app.inject({ method: 'GET', url: authorizeUrl({ challenge }) });
  expect(page.statusCode).toBe(200);
  const post = await app.inject({
    method: 'POST',
    url: '/oauth/authorize',
    headers: FORM_HEADERS,
    payload: formEncode({
      formToken: formTokenFrom(page.body),
      email: EMAIL,
      password: PASSWORD,
      decision: 'approve',
    }),
  });
  expect(post.statusCode).toBe(302);
  const location = new URL(post.headers.location);
  expect(`${location.origin}${location.pathname}`).toBe(REDIRECT);
  const token = await app.inject({
    method: 'POST',
    url: '/oauth/token',
    headers: FORM_HEADERS,
    payload: formEncode({
      grant_type: 'authorization_code',
      code: location.searchParams.get('code'),
      redirect_uri: REDIRECT,
      client_id: CLIENT_URL,
      code_verifier: verifier,
    }),
  });
  return { page, token };
}

describe('discovery', () => {
  beforeEach(setup);

  it('advertises client ID metadata documents beside registration', async () => {
    const res = await app.inject({ method: 'GET', url: '/.well-known/oauth-authorization-server' });
    expect(res.json().client_id_metadata_document_supported).toBe(true);
    expect(res.json().registration_endpoint).toMatch(/\/oauth\/register$/);
  });
});

describe('the metadata-client dance', () => {
  beforeEach(setup);

  it('authorizes, exchanges and calls /mcp with a URL client_id', async () => {
    const { page, token } = await dance();
    expect(page.body).toContain('Claude (claude.example)');
    expect(token.statusCode).toBe(200);
    const list = await rpc(app, token.json().access_token, 'tools/list');
    expect(list.statusCode).toBe(200);
    expect(list.json().result.tools.length).toBeGreaterThan(0);
    expect(tables.oauth_clients).toHaveLength(1);
    expect(tables.oauth_clients[0].metadata_url).toBe(CLIENT_URL);
    expect(tables.oauth_clients[0].id).toHaveLength(26);
  });

  it('reuses a fresh document and fetches an expired one again', async () => {
    await dance();
    await dance();
    expect(cimd.fetchClientMetadata).toHaveBeenCalledTimes(1);
    expect(tables.oauth_clients).toHaveLength(1);

    tables.oauth_clients[0].metadata_expires_at = new Date(Date.now() - 1000);
    cimd.fetchClientMetadata.mockResolvedValue({
      document: document({ client_name: 'Claude (renamed)' }),
      ttlSec: 3600,
    });
    const { page } = await dance();
    expect(cimd.fetchClientMetadata).toHaveBeenCalledTimes(2);
    expect(page.body).toContain('Claude (renamed) (claude.example)');
    expect(tables.oauth_clients).toHaveLength(1);
  });

  it('an unreachable document is a 400 page, never a stale grant', async () => {
    await dance();
    tables.oauth_clients[0].metadata_expires_at = new Date(Date.now() - 1000);
    cimd.fetchClientMetadata.mockRejectedValue(
      Object.assign(new Error('down'), { code: 'CIMD_TIMEOUT' }),
    );
    const { challenge } = pkcePair();
    const res = await app.inject({ method: 'GET', url: authorizeUrl({ challenge }) });
    expect(res.statusCode).toBe(400);
    expect(res.body).toContain('could not be loaded');
  });

  it('a redirect_uri the document does not list is a 400 page, not a redirect', async () => {
    const { challenge } = pkcePair();
    const res = await app.inject({
      method: 'GET',
      url: authorizeUrl({ challenge, redirectUri: 'https://evil.example/cb' }),
    });
    expect(res.statusCode).toBe(400);
    expect(res.headers.location).toBeUndefined();
  });

  it('a document naming another client_id is refused', async () => {
    cimd.fetchClientMetadata.mockResolvedValue({
      document: document({ client_id: 'https://other.example/meta.json' }),
      ttlSec: 3600,
    });
    const { challenge } = pkcePair();
    const res = await app.inject({ method: 'GET', url: authorizeUrl({ challenge }) });
    expect(res.statusCode).toBe(400);
    expect(res.body).toContain('another client_id');
    expect(tables.oauth_clients).toHaveLength(0);
  });

  it('the token endpoint never fetches: an unseen URL client is invalid_client', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/token',
      headers: FORM_HEADERS,
      payload: formEncode({
        grant_type: 'authorization_code',
        code: 'x',
        redirect_uri: REDIRECT,
        client_id: CLIENT_URL,
        code_verifier: 'y',
      }),
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().error).toBe('invalid_client');
    expect(cimd.fetchClientMetadata).not.toHaveBeenCalled();
  });

  it('MCP_CIMD_ENABLED=false: no flag, and a URL client_id is unknown', async () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      MCP_CIMD_ENABLED: 'false',
    });
    ({ app } = await buildTestApp({ config }));
    const meta = await app.inject({
      method: 'GET',
      url: '/.well-known/oauth-authorization-server',
    });
    expect(meta.json().client_id_metadata_document_supported).toBeUndefined();
    const { challenge } = pkcePair();
    const res = await app.inject({ method: 'GET', url: authorizeUrl({ challenge }) });
    expect(res.statusCode).toBe(400);
    expect(cimd.fetchClientMetadata).not.toHaveBeenCalled();
  });
});

describe('isClientMetadataUrl', () => {
  it.each([
    ['https://claude.ai/oauth/claude-client.json', true],
    ['https://claude.example/meta', true],
    ['http://claude.example/meta', false],
    ['https://claude.example/', false],
    ['https://claude.example', false],
    ['https://claude.example:8443/meta', false],
    ['https://user:pw@claude.example/meta', false],
    ['https://claude.example/meta#x', false],
    ['https://claude.example/meta?x=1', false],
    ['https://claude.example/a/../meta', false],
    ['https://claude.example/./meta', false],
    ['https://127.0.0.1/meta', false],
    ['https://[::1]/meta', false],
    ['https://localhost/meta', false],
    ['01J9ZQ8Y3K4M5N6P7Q8R9S0T1V', false],
  ])('%s → %s', (value, expected) => {
    expect(real.isClientMetadataUrl(value)).toBe(expected);
  });
});

describe('isBlockedAddress', () => {
  it.each([
    ['127.0.0.1', true],
    ['10.1.2.3', true],
    ['172.20.0.1', true],
    ['192.168.1.1', true],
    ['169.254.169.254', true],
    ['100.64.0.1', true],
    ['0.0.0.0', true],
    ['::1', true],
    ['fd00::1', true],
    ['fe80::1', true],
    ['::ffff:127.0.0.1', true],
    ['::ffff:10.0.0.1', true],
    ['not-an-ip', true],
    ['104.18.32.7', false],
    ['2606:4700::6810:2007', false],
    ['::ffff:104.18.32.7', false],
  ])('%s → %s', (address, expected) => {
    expect(real.isBlockedAddress(address)).toBe(expected);
  });
});

describe('ttlFromCacheControl', () => {
  it('clamps max-age into 5 min – 24 h and defaults to an hour', () => {
    expect(real.ttlFromCacheControl(undefined)).toBe(3600);
    expect(real.ttlFromCacheControl('public, max-age=7200')).toBe(7200);
    expect(real.ttlFromCacheControl('max-age=10')).toBe(300);
    expect(real.ttlFromCacheControl('max-age=9999999')).toBe(86400);
    expect(real.ttlFromCacheControl('no-store')).toBe(300);
  });
});

describe('validateClientMetadata', () => {
  const allowed = { redirectUriAllowed: (uri) => uri.startsWith('https://') };

  it('accepts a public client and keeps its name and redirects', () => {
    expect(real.validateClientMetadata(CLIENT_URL, document(), allowed)).toEqual({
      name: 'Claude',
      redirectUris: [REDIRECT],
    });
  });

  it.each([
    ['not an object', null],
    ['an array', []],
    ['another client_id', document({ client_id: 'https://x.example/m' })],
    ['a secret', document({ client_secret: 's' })],
    ['a secret auth method', document({ token_endpoint_auth_method: 'client_secret_basic' })],
    ['private_key_jwt', document({ token_endpoint_auth_method: 'private_key_jwt' })],
    ['no code grant', document({ grant_types: ['client_credentials'] })],
    ['no redirects', document({ redirect_uris: [] })],
    ['an http redirect', document({ redirect_uris: ['http://evil.example/cb'] })],
    ['eleven redirects', document({ redirect_uris: Array(11).fill(REDIRECT) })],
  ])('refuses %s', (_label, doc) => {
    expect(real.validateClientMetadata(CLIENT_URL, doc, allowed).error).toBeTruthy();
  });
});

describe('fetchClientMetadata', () => {
  it('refuses to connect to a name that resolves to loopback', async () => {
    await expect(real.fetchClientMetadata('https://localhost/meta.json')).rejects.toMatchObject({
      code: 'CIMD_BLOCKED_ADDRESS',
    });
  });
});
