import { createSSRApp } from 'vue';
import { renderToString } from 'vue/server-renderer';

import HomePage from './HomePage.vue';
import { headFor } from './head.js';
import { HOME_ALTERNATES } from '../alternates.js';
import en from '../content.js';
import tr from '../content.tr.js';

/**
 * Render the homepage in one language (ADR-0061). Called by
 * scripts/prerender.mjs after the build and by scripts/home-ssr.js in dev.
 * Returns the app markup, the extra head tags, and the hero title the
 * prerender asserts is on the page.
 */
export async function render(lang) {
  const content = lang === 'tr' ? tr : en;
  const app = createSSRApp(HomePage, { content, alternates: HOME_ALTERNATES });
  return { app: await renderToString(app), head: headFor(content), title: content.hero.title };
}
