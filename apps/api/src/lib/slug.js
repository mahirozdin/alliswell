import crypto from 'node:crypto';

/**
 * URL-safe slugs for workspaces (globally unique) and tags (unique per workspace).
 * Slugs are cosmetic identifiers — uniqueness is guaranteed by the random suffix
 * (workspaces) or the DB unique index (tags), not by the readable part.
 */

/** @param {string} text */
export function slugify(text) {
  const slug = text
    .normalize('NFKD') // decompose accents (é → e + U+0301), then strip the marks
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48)
    .replace(/-+$/, '');
  return slug || 'space';
}

/** Slug + 8 hex chars of randomness, e.g. `mahir-s-space-3f9a1c2e`. */
export function uniqueSlug(text) {
  return `${slugify(text)}-${crypto.randomBytes(4).toString('hex')}`;
}
