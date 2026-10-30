import { createSSRApp } from 'vue';

import HomePage from './HomePage.vue';
import { HOME_ALTERNATES } from '../alternates.js';
import content from '../content.tr.js';

/** The Turkish homepage; `main.en.js` says why there are two entries. */
createSSRApp(HomePage, { content, alternates: HOME_ALTERNATES }).mount('#app');
