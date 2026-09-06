/**
 * The language pair, spelled once (EE-151).
 *
 * Both entries import it and both HTML heads repeat it as `hreflang` links —
 * which is what Google requires (each page names every version INCLUDING
 * itself). EE-152 asserts the head and this list agree, because two places is
 * one more than one.
 */
export const ALTERNATES = Object.freeze([
  { lang: 'en', label: 'EN', href: '/enterprise' },
  { lang: 'tr', label: 'TR', href: '/enterprise/tr' },
]);
