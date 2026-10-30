import manifest from './media.json';

/**
 * The promoted media for a `media` key from the content modules (ADR-0061).
 * Throws on an unknown key: a typo should fail the prerender, not ship an
 * empty frame. `check:media` asserts the same thing without building.
 */
export function media(key) {
  const entry = manifest[key];
  if (!entry || key.startsWith('$')) throw new Error(`media.json has no entry "${key}" (npm run media:promote)`);
  return entry;
}

/** `srcset` text for a list of `{ src, w }`. */
export const srcset = (list) => list.map(({ src, w }) => `${src} ${w}w`).join(', ');

/** The largest JPEG of a poster or photo, the `<img src>` fallback. */
export const fallback = (list) => list.reduce((a, b) => (b.w > a.w ? b : a)).src;

/** Whether a key has been promoted with a playable file (the film until it is rendered). */
export const playable = (key) => Boolean(manifest[key]?.mp4);
