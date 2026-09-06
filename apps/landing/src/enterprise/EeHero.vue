<script setup>
import BrandMark from '../components/BrandMark.vue';
import ScreenshotFrame from '../components/ScreenshotFrame.vue';

/**
 * The enterprise hero (EE-151).
 *
 * A fork of HeroSection rather than a prop-ised version of it, and the reason
 * is not laziness: that one imports `content.js` directly, hard-codes a
 * platform strip and two fixed captures, and carries a Play Store button and a
 * GitHub star count. Bending it into something that can also be this would
 * leave a component whose template is mostly `v-if`. This is sixty lines and
 * says what it is.
 *
 * The capture is `variant="bare"`: the hero image is already a composite with
 * its own frames and shadow (EE-150), and browser chrome around framed screens
 * would be a frame around a frame.
 */
defineProps({
  hero: { type: Object, required: true },
});
</script>

<template>
  <section id="top" class="eehero">
    <div class="aw-shell eehero__inner">
      <p class="aw-eyebrow">
        <BrandMark :size="16" />
        {{ hero.eyebrow }}
      </p>

      <h1>{{ hero.title }}</h1>
      <p class="aw-lede eehero__lede">{{ hero.lede }}</p>

      <div class="eehero__cta">
        <a class="aw-btn" :href="hero.primary.href">
          {{ hero.primary.label }}
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
            <path d="M13.2 5.4 20 12l-6.8 6.6-1.4-1.4 4.2-4.2H4v-2h12l-4.2-4.2z" />
          </svg>
        </a>
        <a class="aw-btn aw-btn--ghost" :href="hero.secondary.href">
          {{ hero.secondary.label }}
        </a>
      </div>
    </div>

    <div class="aw-shell eehero__shot">
      <ScreenshotFrame
        :src="hero.shot"
        :src-dark="hero.shotDark"
        :alt="hero.alt"
        variant="bare"
        ratio="1600 / 1000"
        eager
      />
    </div>
  </section>
</template>

<style scoped>
.eehero {
  padding-block: clamp(3rem, 8vw, 6rem) 0;
}

.eehero__inner {
  max-width: 54rem;
}

.eehero h1 {
  font-size: clamp(2.3rem, 5.4vw, 3.9rem);
  line-height: 1.06;
  letter-spacing: -0.032em;
  margin-block: 0.9rem 1.1rem;
}

.eehero__lede {
  max-width: 46rem;
}

.eehero__cta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-top: 1.9rem;
}

.eehero__shot {
  margin-top: clamp(2.5rem, 6vw, 4rem);
}
</style>
