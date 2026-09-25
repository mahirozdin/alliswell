import { describe, expect, test } from 'vitest';

import {
  CAPTCHA_SCRIPTS,
  OUTCOME,
  captchaConfig,
  payloadFrom,
  sendEnquiry,
} from '../../../landing/src/enterprise/submit.js';

/// EE-232 — the enterprise page's enquiry, and the verification box it draws
/// only when its build was given a site key.
///
/// The landing has no test runner of its own; its sending logic is plain
/// JavaScript with no DOM in it (the widget lives in `ContactForm.vue`), so
/// it is read here, the way `deploy-overlay-ci.test.js` reads a script from
/// the repo root.

const form = {
  name: 'Aydın Yılmaz',
  company: 'Aydın Metal A.Ş.',
  workEmail: 'satinalma@example.test',
};

/** A `fetch` that answers one status and, optionally, one JSON body. */
const answering = (status, body) => async () => ({
  status,
  json: async () => {
    if (body === undefined) throw new SyntaxError('not JSON');
    return body;
  },
});

describe('which build draws a verification box', () => {
  test('no site key: no box — the form is the one it was', () => {
    expect(captchaConfig({})).toBeNull();
    expect(captchaConfig({ VITE_SALES_CAPTCHA_PROVIDER: 'turnstile' })).toBeNull();
    expect(captchaConfig({ VITE_SALES_CAPTCHA_SITE_KEY: 'k' })).toBeNull();
  });

  test('a provider and its site key draw that provider’s box', () => {
    expect(
      captchaConfig({
        VITE_SALES_CAPTCHA_PROVIDER: ' Turnstile ',
        VITE_SALES_CAPTCHA_SITE_KEY: ' 0x4AAA ',
      }),
    ).toEqual({ provider: 'turnstile', siteKey: '0x4AAA', script: CAPTCHA_SCRIPTS.turnstile });
    expect(
      captchaConfig({ VITE_SALES_CAPTCHA_PROVIDER: 'hcaptcha', VITE_SALES_CAPTCHA_SITE_KEY: 'k' })
        ?.script,
    ).toBe(CAPTCHA_SCRIPTS.hcaptcha);
  });

  test('a provider it does not know is no box — not even one inherited from Object', () => {
    for (const provider of ['recaptcha', 'toString', 'constructor', '__proto__']) {
      expect(
        captchaConfig({ VITE_SALES_CAPTCHA_PROVIDER: provider, VITE_SALES_CAPTCHA_SITE_KEY: 'k' }),
      ).toBeNull();
    }
  });
});

describe('what the enquiry carries', () => {
  test('no answer, no field: a page without a box sends what it always sent', () => {
    expect(payloadFrom(form, 'tr')).not.toHaveProperty('captchaToken');
    expect(payloadFrom(form, 'tr', '', '')).not.toHaveProperty('captchaToken');
  });

  test('the box’s answer travels as `captchaToken`, the name the server declares', () => {
    expect(payloadFrom(form, 'en', '', 'answer')).toMatchObject({
      captchaToken: 'answer',
      companyWebsite: '',
      locale: 'en',
    });
  });
});

describe('what the page says when the server refuses', () => {
  test('EE-232: a refused verification is told apart from a refused field', async () => {
    const outcome = (status, body) =>
      sendEnquiry({}, { endpoint: 'https://api.example.test', fetchImpl: answering(status, body) });
    expect(await outcome(400, { code: 'SALES_CAPTCHA_FAILED' })).toBe(OUTCOME.challenge);
    expect(await outcome(400, { code: 'FST_ERR_VALIDATION' })).toBe(OUTCOME.invalid);
    // A 400 with no JSON at all is still the fields, never a crash.
    expect(await outcome(400)).toBe(OUTCOME.invalid);
    // The outcomes that were there before did not move.
    expect(await outcome(201, { received: true })).toBe(OUTCOME.sent);
    expect(await outcome(404)).toBe(OUTCOME.noDesk);
    expect(await outcome(429)).toBe(OUTCOME.busy);
    expect(await outcome(409, { code: 'SALES_CONSENT_VERSION_STALE' })).toBe(OUTCOME.stale);
  });
});
