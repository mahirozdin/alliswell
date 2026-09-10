<script setup>
import BrandMark from '../components/BrandMark.vue';
import ScreenshotFrame from '../components/ScreenshotFrame.vue';

/**
 * The enterprise hero (EE-151; the facts row added in EE-164).
 *
 * A fork of HeroSection rather than a prop-ised version of it, and the reason
 * is not laziness: that one hard-codes a platform strip and two fixed captures,
 * and carries a Play Store button and a GitHub star count. Bending it into
 * something that can also be this would leave a component whose template is
 * mostly `v-if`.
 *
 * `hero.facts` is the row of four short claims under the buttons. It replaces
 * the strip of measured numbers that used to follow the hero — a buyer does not
 * decide on "634 keys per language" or "one codebase", but does decide on
 * "runs on your own servers" and "keeps working offline". Each fact is a claim
 * a section further down the page substantiates.
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

      <ul v-if="hero.facts && hero.facts.length" class="eehero__facts">
        <li v-for="fact in hero.facts" :key="fact">
          <svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true">
            <circle cx="10" cy="10" r="9" fill="currentColor" opacity="0.14" />
            <path
              d="M6 10.2 8.7 13 14 7.4"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <span>{{ fact }}</span>
        </li>
      </ul>
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

.eehero__facts {
  list-style: none;
  margin: 1.6rem 0 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 0.55rem 1.4rem;
  color: var(--aw-text-dim);
  font-size: 0.95rem;
  font-weight: 560;
}

.eehero__facts li {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
}

.eehero__facts svg {
  color: var(--aw-success);
  flex-shrink: 0;
}

.eehero__shot {
  margin-top: clamp(2.5rem, 6vw, 4rem);
}
</style>
