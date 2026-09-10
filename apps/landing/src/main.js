import { createApp } from 'vue';

import App from './App.vue';
import { HOME_ALTERNATES } from './alternates.js';
import content from './content.js';
import { revealDirective } from './composables/useReveal.js';
import './style.css';

/**
 * The English homepage. The Turkish one is `main.tr.js`, loaded by `/tr`
 * (EE-164): the language is chosen at build time by which entry the browser
 * loaded, so Rollup keeps the other language's copy out of this chunk.
 */
createApp(App, { content, alternates: HOME_ALTERNATES, current: '/' })
  .directive('reveal', revealDirective)
  .mount('#app');
