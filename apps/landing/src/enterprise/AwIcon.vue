<script setup>
import { computed } from 'vue';

import { ICONS } from './icons.js';

/**
 * One line icon from `icons.js` (OPH-388). Always decorative: the text beside
 * it carries the meaning, so the SVG is hidden from assistive technology and
 * takes `currentColor`, which is how it follows the theme.
 */
const props = defineProps({
  name: { type: String, required: true },
  size: { type: Number, default: 24 },
  stroke: { type: Number, default: 2 },
});

const paths = computed(() => ICONS[props.name] ?? []);
</script>

<template>
  <svg
    class="aw-icon"
    viewBox="0 0 24 24"
    :width="size"
    :height="size"
    fill="none"
    stroke="currentColor"
    :stroke-width="stroke"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    <path v-for="(d, i) in paths" :key="i" :d="d" />
  </svg>
</template>

<style scoped>
.aw-icon {
  display: block;
  flex-shrink: 0;
}
</style>
