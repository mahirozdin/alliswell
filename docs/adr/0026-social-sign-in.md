# ADR-0026 — Sign in with Google and Apple

- **Status:** Accepted
- **Date:** 2026-07-31
- **Related task:** OPH-231

## Context

The store release needs social sign-in: e-mail and password alone is friction on
mobile, and Apple **requires** Sign in with Apple in any app that offers another
social login on its platforms.

AllisWell already has a complete auth system — users in MySQL, argon2id
passwords, JWT access tokens and rotating refresh families. Whatever social
sign-in does, it must not become a second, parallel notion of "who is signed in".

Firebase Auth is available (ADR-0025) and would happily be that second notion.
That is the trap: a server that trusts Firebase ID tokens can only be run by
somebody who has been told about the Firebase project, and most servers running
this code never will be.

## Decision

**The provider proves the human; our API decides the account.**

The app performs the native sign-in and obtains the **provider's** ID token
(Google's or Apple's). It posts that to `POST /api/v1/auth/oauth`, which verifies
it and returns an ordinary AllisWell session. `users` in MySQL stays the single
source of truth.

Verification (`src/lib/oauth-identity.js`) checks three things via `jose`:
signature against the provider's live JWKS, issuer, and — the one people skip —
**audience against our own client IDs**. Without the audience check, a token
Google signed for _any application in the world_ would sign its bearer in here as
whoever it names.

Account matching is a three-rule ladder, and the third rule is the security one:

1. A known `(provider, subject)` → that user.
2. An unknown subject whose **verified** e-mail matches an existing account →
   link, and sign in as them.
3. An unknown subject with an unverified or absent e-mail → a **new** account,
   never a link.

`subject`, not `email`, is the identity. Apple sends the address only on the
first authorisation and only with consent; every later token carries `sub` alone.
Keying on e-mail would strand Apple users on their second sign-in.

Firebase Auth is still signed into, with the same credential — purely so
Crashlytics and Analytics can attribute a report to an account. It is never the
credential the API trusts, and its failure is swallowed.

## Alternatives considered

- **Verify Firebase ID tokens server-side.** Fewer moving parts for the hosted
  deployment, and unusable for every self-hoster — the API would need the Firebase
  project's identity to verify anything. Rejected: it makes an optional client
  dependency (ADR-0025) mandatory on the server.
- **Firebase Auth as the user store.** Would mean two user records per person and
  a sync problem between them, and would put account data outside the database the
  product promises is yours.
- **OAuth authorisation-code flow with a server-side exchange.** Correct for a
  pure web app; needless here, since the native SDKs already return a signed ID
  token and an authorisation code would add a redirect URI per platform.
- **Match accounts on e-mail regardless of verification.** Simpler, and an
  account-takeover primitive: anyone who can get an unverified address into a
  token adopts that account. Pinned by a test that fails if the guard is removed.

## Consequences

- Sign-in works on a self-hosted instance with **no Firebase at all** — set the
  client IDs and it works; set nothing and the endpoint answers
  `OAUTH_PROVIDER_NOT_CONFIGURED` (503) rather than accepting foreign tokens.
- `users.password_hash` being nullable since the first migration finally has a
  user: a provider-only account has no password until it sets one.
- Accounts with no e-mail (Apple's "Hide My Email", sharing declined) get a
  stable synthetic address derived from the subject, so the same person cannot
  accumulate accounts.
- New table `user_identities` — several identities may point at one user, which
  is how one person signing in with both Google and Apple stays one account.
- **Not built:** unlinking a provider, and password-setting for a provider-only
  account. Both are reachable through support today; both belong in Settings.
