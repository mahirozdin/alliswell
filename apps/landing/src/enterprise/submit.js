/**
 * Sending the enterprise enquiry (EE-161).
 *
 * ── WHERE IT POSTS, AND WHY GUESSING IS SAFE HERE ─────────────────────────
 *
 * The landing has never called an API before, so there was no base URL to
 * reuse. This derives one: `alliswell.space` → `api.alliswell.space`, which is
 * the deployment this page is written for, with `VITE_SALES_API` as an override
 * and localhost for `npm run landing:dev`.
 *
 * Deriving a host is normally a bad idea, and it is fine here for one specific
 * reason: this endpoint only exists on the INSTANCE THAT SELLS the product.
 * Somebody self-hosting AllisWell builds this page too, their derived host has
 * no sales desk, and the POST answers 404 — which is not an error, it is the
 * true answer to "does this deployment have a sales team?". The page reads it
 * as such and shows the mailto instead. A wrong guess degrades into the correct
 * behaviour rather than into a broken form.
 *
 * ── THE CONSENT VERSION LIVES HERE, NOT IN THE COPY ───────────────────────
 *
 * It is an identifier, not a sentence: the same string in both languages, and
 * putting it in `content.en.js` and `content.tr.js` would make it two strings
 * that can disagree — while `check:copy` would wave it through, because it is
 * shorter than the byte-identical threshold that gate refuses.
 *
 * It MUST match the head of `CONSENT_VERSIONS` in
 * `ee/server/modules/sales/codes.js`. When the notice text changes, both move,
 * and a page still serving the old one is refused with a code that tells the
 * reader to reload — which is the point: a consent recorded against a text the
 * person never saw is worse than no consent at all.
 */
export const CONSENT_VERSION = '2026-09';

const LOCAL = /^(localhost|127\.0\.0\.1|\[::1\])$/;

/**
 * The challenge, when this build was given one (EE-232).
 *
 * Both halves at BUILD time — `VITE_SALES_CAPTCHA_PROVIDER` and
 * `VITE_SALES_CAPTCHA_SITE_KEY` — and the server's half (its secret) where the
 * API runs. They are switched on together: a server with a secret refuses an
 * enquiry from a page that drew no box, and a page with a box posts an answer
 * a server without a secret simply ignores. With no key this answers null and
 * the form is exactly what it was: no script, no box, no field.
 *
 * The site key is public by design (it is embedded in every page that shows a
 * widget); the secret never reaches this file.
 */
export const CAPTCHA_SCRIPTS = Object.freeze({
  turnstile: 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit',
  hcaptcha: 'https://js.hcaptcha.com/1/api.js?render=explicit',
});

export function captchaConfig(env = import.meta.env ?? {}) {
  const provider = String(env.VITE_SALES_CAPTCHA_PROVIDER ?? '')
    .trim()
    .toLowerCase();
  const siteKey = String(env.VITE_SALES_CAPTCHA_SITE_KEY ?? '').trim();
  // `hasOwnProperty`, not `Object.hasOwn` (Safari < 15.4 lacks it, and Vite
  // does not polyfill), and not `in` — `'toString' in CAPTCHA_SCRIPTS` is true.
  if (!siteKey || !Object.prototype.hasOwnProperty.call(CAPTCHA_SCRIPTS, provider)) return null;
  return Object.freeze({ provider, siteKey, script: CAPTCHA_SCRIPTS[provider] });
}

export function salesEndpoint(location = window.location) {
  const override = import.meta.env?.VITE_SALES_API;
  if (override) return `${String(override).replace(/\/+$/, '')}/api/v1/ee/sales/leads`;
  const host = location.hostname;
  if (LOCAL.test(host)) return 'http://localhost:3000/api/v1/ee/sales/leads';
  return `${location.protocol}//api.${host.replace(/^www\./, '')}/api/v1/ee/sales/leads`;
}

/**
 * The outcomes the form has to tell apart.
 *
 * `noDesk` is deliberately not called an error. The others are transient and
 * the form stays filled in; this one is permanent for this deployment, so the
 * form is replaced rather than retried.
 */
export const OUTCOME = Object.freeze({
  sent: 'sent',
  noDesk: 'noDesk',
  stale: 'stale',
  busy: 'busy',
  invalid: 'invalid',
  offline: 'offline',
  failed: 'failed',
  // EE-232: the box was not ticked, or its answer expired or did not verify.
  // Transient like the others — the form stays filled in, the box is drawn
  // again, and ticking it is the whole fix.
  challenge: 'challenge',
});

/** Empty string → absent. A blank optional field was not answered. */
const trimmed = (value) => {
  const text = String(value ?? '').trim();
  return text === '' ? undefined : text;
};

/** '' → absent, '250' → 250. The server coerces too; this keeps '' out. */
const counted = (value) => {
  const text = trimmed(value);
  if (text === undefined) return undefined;
  const n = Number(text);
  return Number.isInteger(n) && n > 0 ? n : undefined;
};

export function payloadFrom(form, locale, honeypot = '', captchaToken = '') {
  return {
    fullName: String(form.name ?? '').trim(),
    companyName: String(form.company ?? '').trim(),
    workEmail: String(form.workEmail ?? '').trim(),
    phone: trimmed(form.phone),
    seatCount: counted(form.seats),
    unitCount: counted(form.units),
    packageInterest: trimmed(form.packageInterest),
    message: trimmed(form.message),
    locale,
    consent: true,
    consentVersion: CONSENT_VERSION,
    // Always present, almost always empty. Declared in the server's schema for
    // a measured reason: Fastify's ajv runs with `removeAdditional`, so an
    // undeclared field is silently STRIPPED rather than rejected — an
    // undeclared trap would be no trap at all.
    companyWebsite: honeypot,
    // EE-232: only from a page that drew the box. Absent, not empty, when
    // there is none — a server with no challenge ignores it either way.
    ...(captchaToken ? { captchaToken } : {}),
  };
}

/**
 * Posts one enquiry and answers with an OUTCOME, never with an exception.
 *
 * A `fetch` rather than a form POST: a cross-origin form navigates the BROWSER
 * to the API host and shows whatever it renders — a raw JSON error under a
 * domain the reader has never seen — at the moment we are asking them to trust
 * us with their infrastructure.
 */
export async function sendEnquiry(payload, { endpoint, fetchImpl = fetch } = {}) {
  let res;
  try {
    res = await fetchImpl(endpoint ?? salesEndpoint(), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });
  } catch {
    // No response at all: the network, a blocked request, a DNS name that does
    // not resolve. Distinct from every status below, because it is the one the
    // reader can fix by trying again in a moment.
    return OUTCOME.offline;
  }

  if (res.status === 201) return OUTCOME.sent;
  // The first-class state. Not "something went wrong" — this deployment has no
  // sales desk, which is a fact about it rather than a failure of the request.
  if (res.status === 404) return OUTCOME.noDesk;
  if (res.status === 429) return OUTCOME.busy;
  if (res.status === 400) {
    // One status, two meanings, told apart by the server's code: a field it
    // refused, or the challenge (EE-232) — which the reader fixes by ticking
    // the box again rather than by re-reading the fields.
    const code = await res
      .json()
      .then((body) => body?.code)
      .catch(() => null);
    return code === 'SALES_CAPTCHA_FAILED' ? OUTCOME.challenge : OUTCOME.invalid;
  }
  if (res.status === 409) {
    const code = await res
      .json()
      .then((body) => body?.code)
      .catch(() => null);
    return code === 'SALES_CONSENT_VERSION_STALE' ? OUTCOME.stale : OUTCOME.failed;
  }
  return OUTCOME.failed;
}
