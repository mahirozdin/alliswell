# ADR-0064 — Password-reset links, and core's own outgoing mail

- **Status:** Accepted
- **Date:** 2026-11-08
- **Related task:** OPH-406 (Epic 35, C-13)

## Context

Nobody who forgot their password could get back in: the sign-in screen had no link and the API had
no route ([research](../research/2026-11-design-ux/ux-core-screens.md) §4.2). On alliswell.space the
only way out was a social sign-in or a support mail. Core sent no mail at all — the only SMTP block
in the config belonged to the extension — and many self-hosted installs have no mail server.

Constraints: the auth critical path (`.claude/rules/auth.md`) — no account enumeration, stable
error codes, a password change ends every session (ADR-0006), secrets hashed at rest, credential
endpoints under the ADR-0045 limiter.

## Decision

1. **Two public routes.** `POST /api/v1/auth/password/forgot {email, locale?}` always answers
   `202 {delivery}`; `POST /api/v1/auth/password/reset {token, password}` answers `204` or
   `400 AUTH_RESET_INVALID`. Both use the credential limiter (per IP + the address named, and the
   shared per-IP ceiling). `delivery` describes the server, not the address: `email` when it can
   mail links, `admin` when it cannot. Unknown addresses get the same answer and no row.
2. **The link is an opaque 32-byte random token** in `<APP_PUBLIC_URL>/#/reset-password?token=…`
   (after the hash, so it never reaches a server log). The table `password_resets` keeps its
   HMAC-SHA256 digest under `JWT_REFRESH_SECRET` with its own separator, like refresh tokens and
   API keys. A link works **once** (atomic `used_at` claim) and **for 60 minutes**
   (`PASSWORD_RESET_TTL_MIN`, 5–1440). Issuing a link retires the account's earlier unused ones;
   spending one retires the rest.
3. **Reset = password change.** The new password passes the extension's password requirements
   before the link is spent (a refused password leaves the link usable), then the password, every
   refresh family and the other links change in one transaction. A second factor stays enrolled:
   the link replaces the password, not the authenticator.
4. **Per-account throttle:** at most 3 e-mailed links per account per hour, counted from the
   table. The fourth ask is answered `202 email` and dropped — the rate limit stops one address
   hammering, this stops many addresses filling one inbox.
5. **Core gets its own SMTP block**, `SMTP_HOST/PORT/USER/PASSWORD/FROM/SECURE` + `APP_PUBLIC_URL`,
   all-or-nothing at boot like the extension's. It is sent through **nodemailer** (zero
   dependencies, imported only when the block is set) behind `app.mailer` (`null` = no mail), which
   tests replace through `buildApp({ mailer })`. The mail is sent after the response, so its
   round trip is no timing answer to "does this address exist?". Core mails nothing else.
6. **No mail → the operator issues the link**: `node apps/api/src/cli/password-reset-link.js
   <email>` (in Docker: `docker compose exec api …`; in a checkout: `npm run password:reset-link`)
   prints a link that works once for 24 hours (`source = 'admin'`, not counted by the throttle). The
   app's forgot screen shows this command when `delivery` is `admin`, and its "I have a link"
   field takes a pasted link or bare code.
7. **Not in MCP** (I-12): account recovery happens without a session, for a person, not an agent
   tool — and `/auth/*` is closed to API keys (ADR-0032). The REST reference documents both routes.

## Alternatives considered

- **Tokens in Redis with a TTL.** Simpler expiry, but I-02 keeps canonical state in MySQL, and the
  throttle and single-use claim are one SQL statement each.
- **Reuse the extension's `EE_SMTP_*`.** Core would then depend on the extension's config, and a
  CE install could not send a reset mail at all.
- **A short numeric code typed into the app.** Easier on a phone, but a 6-digit code needs its own
  attempt counter to be safe; a 256-bit link needs only the limiter. The paste field covers the
  phone.
- **Sign the person in after the reset.** Skipped: with a second factor the reset would have to ask
  for it too, and one more step on a recovery page is worse than signing in once.

## Consequences

- An operator who wants reset mail sets five variables; until then the app explains the
  command path, which works on every install.
- `password_resets` grows by at most a few rows per account per hour; rows go with the account.
- The hosted instance needs the SMTP block and `APP_PUBLIC_URL` (STATE "Kullanıcıdan bekleyen").
- A mobile app opening the link natively (universal links) is not part of this; the link opens the
  web app, or is pasted.
