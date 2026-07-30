import { newId } from '../lib/ids.js';
import { newOpaqueToken, hashMcpToken } from '../lib/tokens.js';
import { parseJsonColumn } from './task-series.js';

/**
 * The MCP OAuth 2.1 domain layer (OPH-218, ADR-0022): clients, single-use
 * codes, opaque token families with rotation + family revocation. Raw token
 * material exists only in return values on its way to the client; the tables
 * hold keyed digests (lib/tokens.js domain separators).
 */

export const MCP_SCOPES = ['mcp:read', 'mcp:write'];
export const DEFAULT_SCOPE = MCP_SCOPES.join(' ');

/** Normalizes a requested scope string; unknown scopes are refused with null. */
export function normalizeScope(requested) {
  if (!requested) return DEFAULT_SCOPE;
  const parts = String(requested).split(/\s+/).filter(Boolean);
  if (parts.length === 0) return DEFAULT_SCOPE;
  if (parts.some((scope) => !MCP_SCOPES.includes(scope))) return null;
  return [...new Set(parts)].join(' ');
}

export function clientRedirectUris(clientRow) {
  return parseJsonColumn(clientRow.redirect_uris) ?? [];
}

/** RFC 7591 open registration. Returns {row, clientSecret?} — secret shown once. */
export async function registerClient(db, secret, { name, redirectUris, tokenEndpointAuthMethod }) {
  const id = newId();
  let clientSecret = null;
  let clientSecretHash = null;
  if (tokenEndpointAuthMethod !== 'none') {
    clientSecret = newOpaqueToken(32);
    clientSecretHash = hashMcpToken('client_secret', clientSecret, secret);
  }
  await db('oauth_clients').insert({
    id,
    name: name ?? null,
    redirect_uris: JSON.stringify(redirectUris),
    token_endpoint_auth_method: tokenEndpointAuthMethod,
    client_secret_hash: clientSecretHash,
  });
  const row = await db('oauth_clients').where({ id }).first();
  return { row, clientSecret };
}

/** Mints a single-use authorization code (60 s TTL). Returns the raw code. */
export async function issueCode(
  db,
  secret,
  { clientId, userId, workspaceId, scope, redirectUri, codeChallenge, resource, ttlSec },
) {
  const code = newOpaqueToken(32);
  await db('oauth_codes').insert({
    id: newId(),
    code_hash: hashMcpToken('code', code, secret),
    client_id: clientId,
    user_id: userId,
    workspace_id: workspaceId,
    scope,
    redirect_uri: redirectUri,
    code_challenge: codeChallenge,
    resource: resource ?? null,
    expires_at: new Date(Date.now() + ttlSec * 1000),
  });
  return code;
}

/**
 * Claims a code atomically (single use). A code that was ALREADY consumed is
 * treated as theft: every token minted for it (same family lineage via the
 * code row's id as family seed) is revoked, per OAuth 2.1 §4.1.2.
 *
 * @returns {{row, replayed: boolean}|null}
 */
export async function claimCode(db, secret, rawCode) {
  const hash = hashMcpToken('code', rawCode, secret);
  const row = await db('oauth_codes').where({ code_hash: hash }).first();
  if (!row) return null;
  if (row.consumed_at) return { row, replayed: true };
  const claimed = await db('oauth_codes')
    .where({ id: row.id })
    .whereNull('consumed_at')
    .update({ consumed_at: new Date() });
  if (claimed === 0) return { row, replayed: true }; // lost the race — replay
  return { row, replayed: false };
}

/** Issues an access+refresh pair in one family. Returns raw tokens. */
export async function issueTokenPair(
  db,
  secret,
  { clientId, userId, workspaceId, scope, familyId, accessTtlSec, refreshTtlDays },
) {
  const family = familyId ?? newId();
  const accessToken = newOpaqueToken(48);
  const refreshToken = newOpaqueToken(48);
  const now = Date.now();
  await db('oauth_tokens').insert([
    {
      id: newId(),
      kind: 'access',
      token_hash: hashMcpToken('access', accessToken, secret),
      client_id: clientId,
      user_id: userId,
      workspace_id: workspaceId,
      scope,
      family_id: family,
      expires_at: new Date(now + accessTtlSec * 1000),
    },
    {
      id: newId(),
      kind: 'refresh',
      token_hash: hashMcpToken('refresh', refreshToken, secret),
      client_id: clientId,
      user_id: userId,
      workspace_id: workspaceId,
      scope,
      family_id: family,
      expires_at: new Date(now + refreshTtlDays * 86400000),
    },
  ]);
  return { accessToken, refreshToken, familyId: family, expiresInSec: accessTtlSec };
}

/** Kills every live token in a family — access AND refresh. */
export async function revokeFamily(db, familyId) {
  await db('oauth_tokens')
    .where({ family_id: familyId })
    .whereNull('revoked_at')
    .update({ revoked_at: new Date() });
}

/** Looks up a LIVE access token; null when unknown/expired/revoked. */
export async function findLiveAccessToken(db, secret, rawToken) {
  const hash = hashMcpToken('access', rawToken, secret);
  const row = await db('oauth_tokens').where({ token_hash: hash, kind: 'access' }).first();
  if (!row || row.revoked_at) return null;
  if (new Date(row.expires_at).getTime() <= Date.now()) return null;
  return row;
}

/**
 * Rotates a refresh token: retires the presented one, revokes the paired
 * access token, issues a fresh pair in the SAME family. Reuse of an already
 * rotated/revoked refresh burns the family (routes/auth.js semantics).
 *
 * @returns {{outcome: 'rotated', tokens}|{outcome: 'reused'}|{outcome: 'invalid'}}
 */
export async function rotateRefreshToken(db, secret, rawToken, { accessTtlSec, refreshTtlDays }) {
  const hash = hashMcpToken('refresh', rawToken, secret);
  const row = await db('oauth_tokens').where({ token_hash: hash, kind: 'refresh' }).first();
  if (!row) return { outcome: 'invalid' };
  if (row.rotated_at || row.revoked_at) {
    await revokeFamily(db, row.family_id);
    return { outcome: 'reused' };
  }
  if (new Date(row.expires_at).getTime() <= Date.now()) return { outcome: 'invalid' };

  const claimed = await db('oauth_tokens')
    .where({ id: row.id })
    .whereNull('rotated_at')
    .update({ rotated_at: new Date() });
  if (claimed === 0) {
    await revokeFamily(db, row.family_id);
    return { outcome: 'reused' };
  }
  // Retire the family's current access tokens; the new pair replaces them.
  await db('oauth_tokens')
    .where({ family_id: row.family_id, kind: 'access' })
    .whereNull('revoked_at')
    .update({ revoked_at: new Date() });

  const tokens = await issueTokenPair(db, secret, {
    clientId: row.client_id,
    userId: row.user_id,
    workspaceId: row.workspace_id,
    scope: row.scope,
    familyId: row.family_id,
    accessTtlSec,
    refreshTtlDays,
  });
  return { outcome: 'rotated', tokens, scope: row.scope };
}

/** RFC 7009: revokes whichever kind the raw token turns out to be. */
export async function revokeToken(db, secret, rawToken) {
  for (const kind of ['access', 'refresh']) {
    const hash = hashMcpToken(kind, rawToken, secret);
    const row = await db('oauth_tokens').where({ token_hash: hash, kind }).first();
    if (row) {
      await revokeFamily(db, row.family_id);
      return true;
    }
  }
  return false;
}
