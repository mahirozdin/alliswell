/**
 * Byte budgets for the homepage media (ADR-0061), shared by the encoder
 * (`scripts/media/promote.mjs`) and the gate (`check-media.mjs`), so the
 * number that shrank a file is the number that holds it.
 *
 * Hallmark's video rule is under 2 MB for ten seconds; the loops sit below it
 * because four of them can be on one screen's worth of scrolling. The site is
 * behind Cloudflare's CDN, so the total stays small and every video loads only
 * when it scrolls into view.
 */
export const BUDGETS = Object.freeze({
  loop: 1.5 * 1024 * 1024,
  film: 12 * 1024 * 1024,
  posterAvif: 140 * 1024,
  posterJpg: 260 * 1024,
  photoAvif: 260 * 1024,
  photoJpg: 420 * 1024,
  stillAvif: 120 * 1024,
  stillJpg: 200 * 1024,
  captions: 20 * 1024,
  font: 40 * 1024,
  fontsTotal: 120 * 1024,
  /** Everything under public/media together. */
  mediaTotal: 30 * 1024 * 1024,
  /** README animated WebP/GIF, and README stills. */
  readmeAnimated: 3 * 1024 * 1024,
  readmeStill: 400 * 1024,
});
