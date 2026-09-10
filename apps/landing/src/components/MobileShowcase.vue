<script setup>
import ScreenshotFrame from './ScreenshotFrame.vue';
import { mobile as mobileDefault } from '../content.js';

/**
 * The phone strip. Every image here is a real capture off a booted device —
 * iOS from the simulator at native 1320×2868, Android from the emulator — so
 * the status bars, the safe areas and the platform's own type rendering are
 * the device's, not a mock-up's.
 *
 * EE-164 — the list and the heading moved into content.js so the Turkish
 * homepage can pass its own captions; this component no longer holds words.
 */
defineProps({
  /** `{ eyebrow, title, lede, shots: [{ src, caption, alt }] }` */
  mobile: { type: Object, default: () => mobileDefault },
});
</script>

<template>
  <section v-reveal class="aw-section mob">
    <div class="aw-shell">
      <header class="mob__head">
        <p class="aw-eyebrow">{{ mobile.eyebrow }}</p>
        <h2>{{ mobile.title }}</h2>
        <p class="aw-lede">{{ mobile.lede }}</p>
      </header>

      <div class="mob__rail">
        <figure v-for="s in mobile.shots" :key="s.src" class="mob__item">
          <ScreenshotFrame variant="phone" :src="s.src" :alt="s.alt" />
          <figcaption>{{ s.caption }}</figcaption>
        </figure>
      </div>
    </div>
  </section>
</template>

<style scoped>
.mob__head {
  max-width: 46rem;
  margin-bottom: 2.5rem;
}

.mob__rail {
  display: flex;
  gap: 1.5rem;
  overflow-x: auto;
  padding-bottom: 1rem;
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
}

.mob__item {
  margin: 0;
  flex: 0 0 auto;
  width: min(240px, 62vw);
  scroll-snap-align: center;
}

.mob__item figcaption {
  margin-top: 0.85rem;
  text-align: center;
  font-size: 0.86rem;
  color: var(--aw-text-dim);
}
</style>
