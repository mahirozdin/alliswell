/**
 * The ONE entitlement feature dictionary (EE-003). Every layer — dev override
 * parsing, license verification, overlay modules, the status endpoint — must
 * name features out of this list, so a typo is a boot error or a thrown
 * `has()` call, never a silently-disabled feature. Names are deliberately
 * coarse product areas (they appear on the public landing anyway); what each
 * one unlocks is the overlay's business, not core's.
 */
export const EE_FEATURES = Object.freeze([
  'teams',
  'rbac',
  'units',
  'itsm',
  'sla',
  'portal',
  'meetings',
  'audit',
  'reports',
]);

export function assertKnownFeature(name) {
  if (!EE_FEATURES.includes(name)) {
    throw new Error(
      `Unknown entitlement feature "${name}" — the dictionary is src/lib/entitlements.js`,
    );
  }
}
