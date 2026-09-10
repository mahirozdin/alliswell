import { createApp } from 'vue';

import App from './App.vue';
import { HOME_ALTERNATES } from './alternates.js';
import content from './content.tr.js';
import { revealDirective } from './composables/useReveal.js';
import './style.css';

/** The Turkish homepage entry (EE-164); `main.js` says how the pair works. */
createApp(App, { content, alternates: HOME_ALTERNATES, current: '/tr' })
  .directive('reveal', revealDirective)
  .mount('#app');
