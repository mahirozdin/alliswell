/**
 * Which AllisWell account a verified Google / Apple identity belongs to
 * (ADR-0026, shared with the MCP consent page by OPH-366 / ADR-0049).
 *
 * The rule ladder lives here so the two places that accept a provider sign-in
 * — `POST /auth/oauth` (the app) and `POST /oauth/authorize/callback` (the MCP
 * consent page) — cannot drift apart on the part that decides whose tasks a
 * stranger gets:
 *
 *   1. Known (provider, subject)          → that user ('known'), or 'gone' when
 *                                           the account was deleted.
 *   2. Unknown subject, provider-VERIFIED
 *      e-mail matching a live account     → 'link' to that user.
 *   3. Anything else                      → 'none'. The app creates an account
 *                                           here; the consent page does not.
 *
 * An unverified e-mail claim is just a string the provider passed along, so it
 * is never a reason to link (that is what stops account takeover).
 */
import { newId } from '../lib/ids.js';

const USER_COLUMNS = ['id', 'email', 'display_name'];

/**
 * @param {import('knex').Knex} db
 * @param {{provider: string, subject: string, email: string|null, emailVerified: boolean}} identity
 * @returns {Promise<{kind: 'known', user: object, identityId: string}
 *   | {kind: 'gone'} | {kind: 'link', user: object} | {kind: 'none'}>}
 */
export async function matchSocialIdentity(db, identity) {
  const existing = await db('user_identities')
    .where({ provider: identity.provider, subject: identity.subject })
    .first();
  if (existing) {
    const user = await db('users')
      .where({ id: existing.user_id })
      .whereNull('deleted_at')
      .first(...USER_COLUMNS);
    // The account was deleted but its identity row outlived it — only
    // possible if a cascade was skipped. Callers refuse rather than resurrect.
    return user ? { kind: 'known', user, identityId: existing.id } : { kind: 'gone' };
  }
  // Rule 2's candidate — only ever consulted when the provider vouched for
  // the address.
  if (identity.email && identity.emailVerified) {
    const user = await db('users')
      .where({ email: identity.email })
      .whereNull('deleted_at')
      .first(...USER_COLUMNS);
    if (user) return { kind: 'link', user };
  }
  return { kind: 'none' };
}

/** Rule 2's write: attach the provider identity to an existing account. */
export function linkIdentity(trx, userId, identity) {
  return trx('user_identities').insert({
    id: newId(),
    user_id: userId,
    provider: identity.provider,
    subject: identity.subject,
    email: identity.email,
    email_verified: identity.emailVerified,
    last_used_at: new Date(),
  });
}

/** Rule 1's write: a liveness stamp on the identity that just signed in. */
export function touchIdentity(trx, identityId) {
  return trx('user_identities')
    .where({ id: identityId })
    .update({ last_used_at: new Date(), updated_at: new Date() });
}
