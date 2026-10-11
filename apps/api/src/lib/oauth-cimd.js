import dns from 'node:dns';
import https from 'node:https';
import net from 'node:net';

/**
 * OAuth Client ID Metadata Documents (ADR-0047,
 * draft-ietf-oauth-client-id-metadata-document): a client may name itself by
 * an https URL instead of registering, and the authorization server reads the
 * client's metadata from that URL. Claude's "Use Claude's published identity"
 * connector option works this way; dynamic registration (RFC 7591) stays
 * beside it, unchanged.
 *
 * Fetching a URL a stranger chose is a server-side request on their behalf,
 * so the fetch is fenced: https on the default port only, a DNS name rather
 * than an IP literal, every resolved address checked against the private and
 * reserved ranges AT CONNECT TIME (the `lookup` hook — a name that resolves
 * public once and private the next is refused on the second), no redirects,
 * a 5 s budget and a 5 KB ceiling.
 */

export const CIMD_MAX_BYTES = 5 * 1024;
export const CIMD_TIMEOUT_MS = 5000;
/** How long a fetched document is trusted, unless its Cache-Control says less. */
export const CIMD_DEFAULT_TTL_SEC = 3600;
export const CIMD_MIN_TTL_SEC = 300;
export const CIMD_MAX_TTL_SEC = 86400;

const blocked = new net.BlockList();
for (const [prefix, bits] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.0.2.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['198.51.100.0', 24],
  ['203.0.113.0', 24],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
]) {
  blocked.addSubnet(prefix, bits, 'ipv4');
}
for (const [prefix, bits] of [
  ['::', 128],
  ['::1', 128],
  ['64:ff9b::', 96],
  ['100::', 64],
  ['2001:db8::', 32],
  ['fc00::', 7],
  ['fe80::', 10],
  ['ff00::', 8],
]) {
  blocked.addSubnet(prefix, bits, 'ipv6');
}

/** True for an address no metadata fetch may connect to. */
export function isBlockedAddress(address) {
  const family = net.isIP(address);
  if (family === 0) return true;
  if (family === 6) {
    // An IPv4-mapped IPv6 address is the IPv4 address in disguise.
    const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
    if (mapped) return blocked.check(mapped[1], 'ipv4');
    return blocked.check(address, 'ipv6');
  }
  return blocked.check(address, 'ipv4');
}

/**
 * Whether `value` is a client_id this server will treat as a metadata URL:
 * https, a DNS host on the default port, a path, no credentials, no fragment,
 * no query, no dot segments (the draft's MUSTs, plus the SSRF fence's).
 */
export function isClientMetadataUrl(value) {
  if (typeof value !== 'string' || value.length > 500 || !value.startsWith('https://')) {
    return false;
  }
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:' || url.port !== '' || url.username || url.password) return false;
  if (url.hash || value.includes('#') || url.search || value.includes('?')) return false;
  if (!url.pathname || url.pathname === '/') return false;
  // Normalisation must not change what the client said it is — this is also
  // what refuses dot segments, which the parser resolves away.
  if (url.href !== value) return false;
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (net.isIP(host) !== 0 || !host.includes('.')) return false;
  return true;
}

/** The host a consent page shows next to a metadata client's name. */
export function clientMetadataHost(value) {
  try {
    return new URL(value).hostname;
  } catch {
    return null;
  }
}

/** Resolves like dns.lookup, but refuses when any answer is private. */
function guardedLookup(hostname, options, callback) {
  dns.lookup(hostname, { ...options, all: true }, (err, addresses) => {
    if (err) return callback(err);
    const list = Array.isArray(addresses) ? addresses : [];
    if (list.length === 0 || list.some((entry) => isBlockedAddress(entry.address))) {
      const refused = new Error(`refusing to fetch client metadata from ${hostname}`);
      refused.code = 'CIMD_BLOCKED_ADDRESS';
      return callback(refused);
    }
    if (options?.all) return callback(null, list);
    return callback(null, list[0].address, list[0].family);
  });
}

/** `max-age` from a Cache-Control header, clamped; the default when absent. */
export function ttlFromCacheControl(header) {
  const value = Array.isArray(header) ? header.join(',') : String(header ?? '');
  if (/\bno-store\b|\bno-cache\b/i.test(value)) return CIMD_MIN_TTL_SEC;
  const match = /\bmax-age\s*=\s*(\d+)/i.exec(value);
  if (!match) return CIMD_DEFAULT_TTL_SEC;
  return Math.min(CIMD_MAX_TTL_SEC, Math.max(CIMD_MIN_TTL_SEC, Number(match[1])));
}

/**
 * GETs the metadata document at `url`. Resolves `{ document, ttlSec }` or
 * rejects with an Error whose `code` starts with `CIMD_`.
 */
export function fetchClientMetadata(url, { timeoutMs = CIMD_TIMEOUT_MS } = {}) {
  return new Promise((resolve, reject) => {
    const fail = (code, message) => {
      const error = new Error(message);
      error.code = code;
      reject(error);
    };
    const request = https.get(
      url,
      {
        lookup: guardedLookup,
        timeout: timeoutMs,
        headers: { accept: 'application/json', 'user-agent': 'AllisWell-OAuth/1' },
      },
      (response) => {
        if (response.statusCode !== 200) {
          response.resume();
          return fail('CIMD_HTTP_STATUS', `client metadata answered ${response.statusCode}`);
        }
        const chunks = [];
        let size = 0;
        response.on('data', (chunk) => {
          size += chunk.length;
          if (size > CIMD_MAX_BYTES) {
            request.destroy();
            fail('CIMD_TOO_LARGE', 'client metadata is larger than 5 KB');
            return;
          }
          chunks.push(chunk);
        });
        response.on('end', () => {
          if (size > CIMD_MAX_BYTES) return;
          let document;
          try {
            document = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          } catch {
            return fail('CIMD_NOT_JSON', 'client metadata is not JSON');
          }
          resolve({ document, ttlSec: ttlFromCacheControl(response.headers['cache-control']) });
        });
        response.on('error', (err) => fail('CIMD_FETCH_FAILED', err.message));
      },
    );
    request.on('timeout', () => {
      request.destroy();
      fail('CIMD_TIMEOUT', 'client metadata did not answer in time');
    });
    request.on('error', (err) =>
      fail(err.code === 'CIMD_BLOCKED_ADDRESS' ? err.code : 'CIMD_FETCH_FAILED', err.message),
    );
  });
}

/**
 * Checks a fetched document against the URL it came from. Returns
 * `{ name, redirectUris }` or `{ error }`. `redirectUriAllowed` is the same
 * rule dynamic registration applies, so neither door is wider than the other.
 */
export function validateClientMetadata(url, document, { redirectUriAllowed }) {
  if (!document || typeof document !== 'object' || Array.isArray(document)) {
    return { error: 'client metadata is not an object' };
  }
  if (document.client_id !== url) return { error: 'client metadata names another client_id' };
  if ('client_secret' in document || 'client_secret_expires_at' in document) {
    return { error: 'client metadata must not carry a client secret' };
  }
  const method = document.token_endpoint_auth_method ?? 'none';
  // A public document cannot hold a secret, and private_key_jwt is not built.
  if (method !== 'none') {
    return { error: `token_endpoint_auth_method ${method} is not supported for metadata clients` };
  }
  if (
    document.grant_types !== undefined &&
    (!Array.isArray(document.grant_types) || !document.grant_types.includes('authorization_code'))
  ) {
    return { error: 'client metadata does not ask for the authorization_code grant' };
  }
  const uris = document.redirect_uris;
  if (
    !Array.isArray(uris) ||
    uris.length === 0 ||
    uris.length > 10 ||
    !uris.every((uri) => typeof uri === 'string' && uri.length <= 500 && redirectUriAllowed(uri))
  ) {
    return { error: 'client metadata has no acceptable redirect_uris' };
  }
  const name =
    typeof document.client_name === 'string' && document.client_name.trim()
      ? document.client_name.trim().slice(0, 255)
      : null;
  return { name, redirectUris: uris };
}
