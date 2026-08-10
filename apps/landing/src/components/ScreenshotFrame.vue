<script setup>
import { computed } from 'vue';

import { useTheme } from '../composables/useTheme.js';

/**
 * Wraps a screenshot in browser or phone chrome.
 *
 * The frame is drawn in CSS rather than baked into the PNG so the same source
 * image can appear framed on the site and bare in the README and the stores —
 * one screenshot pipeline, three presentations.
 */
const props = defineProps({
  src: { type: String, required: true },
  alt: { type: String, required: true },
  variant: { type: String, default: 'browser' }, // 'browser' | 'phone' | 'bare'
  label: { type: String, default: 'alliswell.space/app' },
  eager: { type: Boolean, default: false },
  /** Optional dark-theme capture; falls back to `src` when there isn't one. */
  srcDark: { type: String, default: '' },
  /** e.g. '1320 / 2868'. Reserves the box before the image loads. */
  ratio: { type: String, default: '' },
});

const { theme } = useTheme();

const shown = computed(() =>
  theme.value === 'dark' && props.srcDark ? props.srcDark : props.src,
);
</script>

<template>
  <figure class="frame" :class="`frame--${variant}`">
    <div v-if="variant === 'browser'" class="frame__bar" aria-hidden="true">
      <span class="frame__dot" />
      <span class="frame__dot" />
      <span class="frame__dot" />
      <span class="frame__url">{{ label }}</span>
    </div>
    <div v-else-if="variant === 'phone'" class="frame__notch" aria-hidden="true" />
    <!-- `ratio` reserves the box before the bytes arrive. Without it a lazy
         screenshot lands mid-scroll and shoves the page down under the reader
         — worst for the tall phone captures, which are twice the page's own
         height. -->
    <img
      :src="shown"
      :alt="alt"
      :loading="eager ? 'eager' : 'lazy'"
      :fetchpriority="eager ? 'high' : 'auto'"
      :style="ratio ? { aspectRatio: ratio } : null"
      decoding="async"
    />
  </figure>
</template>

<style scoped>
.frame {
  margin: 0;
  overflow: hidden;
  background: var(--aw-surface);
  border: 1px solid var(--aw-hairline);
  box-shadow: var(--aw-shadow);
}

.frame--browser {
  border-radius: var(--aw-radius);
}

.frame--phone {
  border-radius: 34px;
  border-width: 8px;
  border-style: solid;
  border-color: color-mix(in srgb, var(--aw-text) 82%, transparent);
  position: relative;
  max-width: 300px;
  box-shadow: var(--aw-shadow);
}

.frame--bare {
  border-radius: var(--aw-radius);
}

.frame__bar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 10px 14px;
  background: var(--aw-surface-2);
  border-bottom: 1px solid var(--aw-hairline);
}

.frame__dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: color-mix(in srgb, var(--aw-text-dim) 40%, transparent);
}

.frame__url {
  margin-left: 12px;
  padding: 2px 12px;
  border-radius: 999px;
  background: var(--aw-surface);
  font-size: 0.75rem;
  color: var(--aw-text-dim);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.frame__notch {
  position: absolute;
  top: 0;
  left: 50%;
  translate: -50% 0;
  width: 38%;
  height: 22px;
  border-radius: 0 0 14px 14px;
  background: color-mix(in srgb, var(--aw-text) 82%, transparent);
  z-index: 2;
}

.frame img {
  width: 100%;
  display: block;
}
</style>
