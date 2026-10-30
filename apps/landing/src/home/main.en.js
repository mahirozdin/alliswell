import { createSSRApp } from 'vue';

import HomePage from './HomePage.vue';
import { HOME_ALTERNATES } from '../alternates.js';
import content from '../content.js';

/**
 * The English homepage, hydrating the HTML prerender.mjs wrote (ADR-0061).
 * The Turkish one is `main.tr.js`: one entry per language keeps the other
 * language's words out of this chunk.
 */
createSSRApp(HomePage, { content, alternates: HOME_ALTERNATES }).mount('#app');
