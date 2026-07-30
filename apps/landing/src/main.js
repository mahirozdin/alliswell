import { createApp } from 'vue';

import App from './App.vue';
import { revealDirective } from './composables/useReveal.js';
import './style.css';

createApp(App).directive('reveal', revealDirective).mount('#app');
