/**
 * Guarantee `globalThis.crypto`, the Web Crypto API, for the modules that need it.
 *
 * Importing this module is the guarantee; it exports nothing.
 *
 * Why it exists: `jose` (6.x) verifies signatures through the **global**
 * `crypto.subtle`, exactly as a browser would. Node has shipped that global
 * unflagged only since v19 — on Node 18 the identifier is simply not there, and
 * jose dies with `ReferenceError: crypto is not defined` the moment it moves
 * from parsing a token to checking its signature.
 *
 * That failure mode is unusually cruel, which is why this is worth a comment
 * rather than a one-liner in some entry file:
 *
 *   * It is invisible to a malformed token. jose rejects those while parsing,
 *     long before it reaches any cryptography — so probing the endpoint with a
 *     junk token answers "Invalid Compact JWS" and looks perfectly healthy.
 *   * Only a real, well-formed provider token gets far enough to trigger it,
 *     which means the first person to meet it is a user signing in.
 *   * `verifyIdentityToken` wraps everything it catches as OAUTH_TOKEN_INVALID,
 *     so the server then blames the user's credential for its own missing
 *     runtime feature.
 *
 * `node:crypto` has exposed the same implementation as `webcrypto` since v15,
 * so the repair is available precisely where the global is not.
 *
 * This is a floor, not a licence: package.json still declares `>=22` and CI
 * still tests on 24. It keeps a deployment that has fallen behind — Node 18 went
 * end-of-life in April 2025 — signing users in instead of failing at the one
 * step that cannot be retried.
 */

import { webcrypto } from 'node:crypto';

if (typeof globalThis.crypto === 'undefined') {
  Object.defineProperty(globalThis, 'crypto', {
    value: webcrypto,
    configurable: true,
    enumerable: false,
    writable: true,
  });
}
