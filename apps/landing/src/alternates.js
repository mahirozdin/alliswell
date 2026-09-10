/**
 * The homepage's language pair, spelled once (EE-164).
 *
 * The same shape as `enterprise/alternates.js`, for the same reason: both
 * entries import it, both HTML heads repeat it as `hreflang` links, and
 * `check:copy` asserts the heads and this list agree.
 */
export const HOME_ALTERNATES = Object.freeze([
  { lang: 'en', label: 'EN', href: '/' },
  { lang: 'tr', label: 'TR', href: '/tr' },
]);
