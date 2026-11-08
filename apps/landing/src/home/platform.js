/**
 * OPH-412 (landing-audit K6): one primary action, chosen by the device. A
 * phone is sent to its store, everything else to the web app.
 *
 * The server renders the desktop action (it cannot know the device), and the
 * client swaps it after hydration, so the first paint matches the HTML and
 * Vue sees no hydration mismatch.
 */

/**
 * @param {string | undefined} userAgent
 * @param {number} [maxTouchPoints] iPadOS asks for the desktop site and calls
 *   itself "Macintosh"; only the touch screen gives it away.
 * @returns {'ios' | 'android' | 'desktop'}
 */
export function platformOf(userAgent, maxTouchPoints = 0) {
  const ua = userAgent ?? '';
  if (/iPhone|iPad|iPod/.test(ua)) return 'ios';
  if (/Macintosh/.test(ua) && maxTouchPoints > 1) return 'ios';
  if (/Android/i.test(ua)) return 'android';
  return 'desktop';
}

/**
 * @param {{ desktop: {label: string, href: string}, ios?: object, android?: object }} primary
 * @param {string} platform
 */
export function primaryFor(primary, platform) {
  return (platform !== 'desktop' && Object.hasOwn(primary, platform) && primary[platform]) || primary.desktop;
}
