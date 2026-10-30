<script setup>
import { computed } from 'vue';

import { ICONS } from '../icons.js';

const props = defineProps({
  name: { type: String, required: true },
  size: { type: Number, default: 20 },
});
const parts = computed(() => {
  const shape = ICONS[props.name];
  if (!shape) throw new Error(`HomeIcon: no icon "${props.name}"`);
  return shape;
});
</script>

<template>
  <svg
    class="icon"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    <template v-for="(part, i) in parts" :key="i">
      <path v-if="typeof part === 'string'" :d="part" />
      <rect v-else-if="part.el === 'rect'" :x="part.x" :y="part.y" :width="part.width" :height="part.height" :rx="part.rx" />
      <circle v-else :cx="part.cx" :cy="part.cy" :r="part.r" />
    </template>
  </svg>
</template>
