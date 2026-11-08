import { createSSRApp } from 'vue';
import { renderToString } from 'vue/server-renderer';

import EnterprisePage from './EnterprisePage.vue';
import { ALTERNATES } from './alternates.js';
import en from './content.en.js';
import tr from './content.tr.js';
import { SECTIONS } from './page.js';

/**
 * Render the enterprise page in one language (OPH-413, landing-audit K8).
 * The same props the browser entries hydrate with (`main.en.js`,
 * `main.tr.js`), so the server's markup and the first client render agree.
 *
 * `sections` is every rendered section's heading in page order: the
 * prerender refuses a build whose HTML lacks one.
 */
export async function render(lang) {
  const content = lang === 'tr' ? tr : en;
  const current = lang === 'tr' ? '/enterprise/tr' : '/enterprise';
  const app = createSSRApp(EnterprisePage, { content, alternates: ALTERNATES, current });
  const sections = SECTIONS.filter((s) => content[s.key])
    .map((s) => content[s.key].title ?? content[s.key].heading)
    .filter(Boolean);
  return { app: await renderToString(app), head: '', title: content.hero.title, sections };
}
