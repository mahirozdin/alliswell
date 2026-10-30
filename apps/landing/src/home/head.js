import { fallback, media, srcset } from './media.js';

const esc = (s) =>
  String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

/**
 * Head tags that depend on promoted media, so no hashed file name is ever
 * typed into the HTML shells by hand (ADR-0061): the hero photograph's
 * preload (it is the largest paint) and the film's VideoObject.
 */
export function headFor(content) {
  const photo = media('photo-fog');
  const tags = [
    `<link rel="preload" as="image" type="image/avif" fetchpriority="high" imagesrcset="${esc(
      srcset(photo.sources.avif),
    )}" imagesizes="100vw" />`,
  ];
  let film;
  try {
    film = media(content.film.media);
  } catch {
    film = null;
  }
  if (film?.mp4) {
    const seconds = Math.round(film.duration);
    const ld = {
      '@context': 'https://schema.org',
      '@type': 'VideoObject',
      name: content.film.title,
      description: content.film.alt,
      inLanguage: content.lang,
      thumbnailUrl: `https://alliswell.space${fallback(film.poster.jpg)}`,
      contentUrl: `https://alliswell.space${film.mp4}`,
      uploadDate: '2026-10-30',
      duration: `PT${seconds}S`,
    };
    tags.push(`<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, '\\u003c')}</script>`);
  }
  return tags.join('\n    ');
}
