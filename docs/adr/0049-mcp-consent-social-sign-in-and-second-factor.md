# ADR-0049 — Google / Apple sign-in and the second factor on the MCP consent page

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related task:** OPH-366

## Context

The MCP authorization server (`apps/api/src/routes/oauth.js`, ADR-0022, ADR-0047) signs a
person in on a server-rendered consent page that had only an e-mail + password form.
Accounts created with Google or Apple sign-in (ADR-0026) have no password and no way to set
one, so they could not connect Claude, ChatGPT or any other MCP client at all.

Checking the page against `/auth/login` showed a second gap: the consent POST verified the
password and issued a code without ever asking for the TOTP code or consulting the
extension's `signInRequirements`. For a TOTP-enrolled account the password alone minted
MCP tokens.

Constraints: the API has no cookies and no session store (the consent flow already carries
the validated request in a signed form token); Redis is only `ping` in tests and holds no
key/value state today; the page is plain HTML with no JavaScript; LESSONS `security` —
every interpolation is escaped, and the two OAuths face opposite directions.

## Decision

1. **Server-side OpenID Connect redirect with `response_mode=form_post`.** "Continue with
   Google / Apple" is a second form, after the password form, that posts the form token to
   `POST /oauth/authorize/social`. That route redirects to the provider and the provider
   posts back to **`<API_PUBLIC_URL>/oauth/authorize/callback`**:
   - Google: `response_type=id_token`, `scope=openid email`, `prompt=select_account`,
     `client_id = SIGN_IN_GOOGLE_WEB_CLIENT_ID`.
   - Apple: `response_type=code id_token`, `scope=email`, `client_id =
     SIGN_IN_APPLE_SERVICE_ID`. The code is ignored; only the ID token is used.
   No client secret, no new environment variable, no provider JavaScript on the page where
   passwords are typed.
2. **Binding without cookies.** `state` is a signed JWT (purpose `mcp_social`, 10 min)
   carrying the original client, redirect_uri, scope, state, PKCE challenge and resource,
   plus a fresh 256-bit **nonce**. The callback verifies the ID token with ADR-0026's
   checks (signature, issuer) plus two new, optional ones in `verifyIdentityToken`: the
   `nonce` must equal the one in the state, and the **audience is pinned** to the single
   client the redirect used (an `audience` option is intersected with the configured
   list, never added to it). PKCE, scope and redirect validation are untouched: nothing
   about the authorization is read from anywhere but signed tokens. Token purposes never
   cross (`mcp_authorize`, `mcp_social`, `mcp_step`; access tokens have none), and the
   step token names the user in `u`, never `sub`.
3. **Same account rules, no creation.** `db/identities.js` holds the ADR-0026 ladder for
   both `POST /auth/oauth` and the callback: a known (provider, subject) is that user; an
   unknown subject with a provider-VERIFIED e-mail matching a live account links. Anything
   else — and a deleted account — gets "No AllisWell account uses this Google/Apple
   account yet. Sign up in the AllisWell app first". Connecting an AI to a brand-new empty
   workspace is never what was meant; it is almost always the wrong account picked in the
   provider's chooser.
4. **An explicit step after every social return.** The page shows "Signed in as X with
   Google", the second-factor field when the account has one, the workspace choice, then
   Approve / Deny (`POST /oauth/authorize/continue`, step token 5 min, reused — not
   re-minted — on a retry). The person approves the account the provider actually picked.
5. **The second factor and the policy on both paths.** The consent page is a sign-in: a
   TOTP-enrolled account (password or social) must enter an authenticator or recovery code
   on the step page, and `app.ee.signInRequirements` run with `{ totpEnrolled,
   totpVerified }` exactly as in `/auth/login`; a refusal re-renders, a throw refuses.
   The password path without 2FA and with one workspace keeps its single POST → 302.
6. **Buttons only when they can work.** Google iff `SIGN_IN_GOOGLE_WEB_CLIENT_ID` is set;
   Apple iff `SIGN_IN_APPLE_SERVICE_ID` is set and `API_PUBLIC_URL` is https (Apple refuses
   http and localhost Return URLs). Neither set: no buttons and no divider.

**Rule 12:** `/oauth/*` is the MCP authorization server itself, and the key-authenticated
public API has no sign-in surface — neither MCP tools, docs/API.md nor openapi.json change.

## Alternatives considered

- **Google Identity Services / Sign in with Apple JS on the page.** Third-party script on
  the page where passwords are typed, a CSP to design, and nothing in the Flutter web
  client to stay consistent with (its Google button calls an API web does not support).
- **Authorization-code flow with a token exchange.** Needs a new client-secret variable
  for Google and, for Apple, a signed client-secret JWT with a private key — operational
  cost for the same verified ID token.
- **Let social users set a password.** Pushes the gap onto every user and keeps a second
  credential alive that they never wanted.
- **Create an account from the consent page (rule 3).** Rejected above.
- **A single-use store for the nonce / step token.** There is no Redis key/value use or
  cookie session in the API. A replayed (state, ID token) pair inside 10 minutes only
  yields another code for the ORIGINAL client's registered redirect_uri, bound to the
  original PKCE challenge, so it is useless without the verifier.

## Consequences

- Google- and Apple-only accounts can connect MCP clients once the consoles list the
  callback URL (Google: an authorized redirect URI on the web client; Apple: a Return URL on
  the Services ID, whose primary App ID must be the iOS app's so `sub` matches accounts made
  on iPhone).
- Existing 2FA users see one extra step when they connect a client — the security fix.
- Google discourages the implicit `id_token` response; if a console refuses it, the
  fallback is the code flow with a client secret.
- Left out, written down as measured gaps in docs/TASKS.md: `POST /auth/oauth` signs
  TOTP-enrolled users in without a code (fixing it needs app UI), and the Flutter web Google
  button calls `authenticate()`, which `google_sign_in_web` does not implement. The consent
  page's password path still does not consult the extension's `credentialVerifiers`
  (existing behaviour, unchanged here).
