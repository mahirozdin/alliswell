/**
 * OPH-343 — an overlay that fails HALFWAY: one rule is already registered
 * when the next step throws. The loader must not serve from this state, and
 * must not quietly fall back to the plain build either — it locks.
 */
export async function register(app, seam) {
  seam.registerPermissionResolver(async () => new Set());
  throw new Error('halfway: the second module failed to start');
}
