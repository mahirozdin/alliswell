import { describe, it, expect } from 'vitest';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

/**
 * The Web Crypto floor under `jose` (src/lib/webcrypto.js).
 *
 * Why this file exists: on Node 18 the server answered every genuine Apple and
 * Google sign-in with OAUTH_TOKEN_INVALID and the reason `crypto is not
 * defined`. Nothing in this suite could see it. `auth-oauth.test.js` stubs
 * `verifyIdentityToken` — deliberately and correctly, since the account-matching
 * rule is what that file is about — so the verification path was never executed,
 * and CI runs a Node new enough for the global to exist anyway.
 *
 * Why it spawns a process: the first draft deleted `globalThis.crypto` inside
 * the test and passed **with the fix removed**. Vitest restores the global
 * behind your back, so a test written that way reports a guarantee the runtime
 * does not actually make. The bug lives in Node's global scope, so the
 * assertion has to be made in a plain Node process — and the first case below
 * exists to prove this harness can still fail.
 */

const apiRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const moduleUrl = (relative) => pathToFileURL(resolve(apiRoot, relative)).href;

/**
 * In a fresh Node process with no `globalThis.crypto`, import `specifier` and
 * report what the global is afterwards.
 */
function typeofCryptoAfterImporting(specifier) {
  const script = [
    'delete globalThis.crypto;',
    specifier ? `await import(${JSON.stringify(specifier)});` : '',
    'process.stdout.write(typeof globalThis.crypto);',
  ].join('\n');
  return execFileSync(process.execPath, ['--input-type=module', '--eval', script], {
    cwd: apiRoot,
    encoding: 'utf8',
  });
}

describe('Web Crypto availability', () => {
  it('can tell the global is gone — otherwise every case below is vacuous', () => {
    expect(typeofCryptoAfterImporting(null)).toBe('undefined');
  });

  it('restores globalThis.crypto on a runtime that lacks it', () => {
    expect(typeofCryptoAfterImporting(moduleUrl('src/lib/webcrypto.js'))).toBe('object');
  });

  it('is guaranteed by importing oauth-identity, which is what jose needs', () => {
    // The guarantee has to travel with the consumer. Wiring it into an entry
    // file instead would leave every test that builds the app directly — and
    // any future importer — back on the broken path.
    expect(typeofCryptoAfterImporting(moduleUrl('src/lib/oauth-identity.js'))).toBe('object');
  });

  it('leaves a runtime that already has it untouched', () => {
    // Replacing Node's own implementation would swap the global out from under
    // anything already holding a reference to it.
    const script = [
      'const before = globalThis.crypto;',
      `await import(${JSON.stringify(moduleUrl('src/lib/webcrypto.js'))});`,
      'process.stdout.write(String(globalThis.crypto === before));',
    ].join('\n');
    const same = execFileSync(process.execPath, ['--input-type=module', '--eval', script], {
      cwd: apiRoot,
      encoding: 'utf8',
    });
    expect(same).toBe('true');
  });
});
