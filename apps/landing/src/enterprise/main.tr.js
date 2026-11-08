import { createSSRApp } from 'vue';

import EnterprisePage from './EnterprisePage.vue';
import { ALTERNATES } from './alternates.js';
import content from './content.tr.js';
import '../style.css';

/**
 * The Turkish entry.
 *
 * The locale is chosen HERE, at build time, by which entry the browser loaded.
 * Rollup then keeps the other language's copy out of this chunk: no runtime
 * detection, no flash of the wrong language, and a reader downloads one
 * language rather than two.
 *
 * OPH-413: it hydrates the HTML scripts/prerender.mjs wrote
 * (src/enterprise/entry-server.js renders the same props).
 */
createSSRApp(EnterprisePage, {
  content,
  alternates: ALTERNATES,
  current: '/enterprise/tr',
}).mount('#app');
