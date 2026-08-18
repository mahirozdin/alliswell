import path from 'node:path';

import fp from 'fastify-plugin';

import { assertKnownFeature } from '../lib/entitlements.js';
import { verifyLicenseFile, BUBIAPPS_EE_LICENSE_PUBLIC_KEY } from '../lib/ee-license.js';
import { resolveEeDir } from '../lib/ee.js';

/**
 * Instance entitlements (EE-003/EE-004): the ONE gate every enterprise
 * feature consults. The plugin always registers — a CE instance answers
 * `has() === false` for everything and /ee/status stays a plain 200 with an
 * empty list, because capability discovery must not look like an error.
 *
 * Sources, in precedence order:
 *   1. EE_DEV_ENTITLEMENTS (development override; config.js refuses it in
 *      production — a leftover override must never hand out paid features)
 *   2. a signed license file (self-host EE; Ed25519, verified offline)
 *   3. nothing → CE
 * A plan/package feed for the hosted service joins the chain later (EE-034)
 * through the overlay, which is why `refresh()` exists already.
 */
export default fp(
  async function entitlementsPlugin(app) {
    const { ee } = app.config;

    let current = { state: 'none', features: [], expiresAt: null, licenseError: null };

    function resolve() {
      if (ee.devEntitlements) {
        current = {
          state: 'active',
          features: [...ee.devEntitlements],
          expiresAt: null,
          licenseError: null,
        };
        return;
      }
      const dir = resolveEeDir(app.config);
      const licensePath = ee.licensePath || (dir ? path.join(dir, 'license.json') : null);
      if (!licensePath) return;
      const result = verifyLicenseFile({
        path: licensePath,
        publicKeyBase64: ee.licensePublicKey || BUBIAPPS_EE_LICENSE_PUBLIC_KEY,
      });
      if (result.error) {
        // Invalid ≠ absent for the operator (log), = absent for behaviour (CE).
        app.log.error({ licensePath, error: result.error }, 'EE license rejected — running as CE');
      }
      current = {
        state: result.state,
        features: result.payload?.features ?? [],
        expiresAt: result.payload ? new Date(result.payload.expiresAt) : null,
        licenseError: result.error,
      };
    }

    resolve();

    app.decorate('entitlements', {
      /** True only while the license breathes (active or grace). Unknown names throw. */
      has(feature) {
        assertKnownFeature(feature);
        return (
          (current.state === 'active' || current.state === 'grace') &&
          current.features.includes(feature)
        );
      },
      list: () => [...current.features],
      get state() {
        return current.state;
      },
      get expiresAt() {
        return current.expiresAt;
      },
      /** Re-reads the sources — the overlay's plan feed will call this (EE-034). */
      refresh: resolve,
    });
  },
  { name: 'alliswell-entitlements' },
);
