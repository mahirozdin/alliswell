<script setup>
import ScreenshotFrame from './ScreenshotFrame.vue';
import { pillars } from '../content.js';
import AwIcon from '../enterprise/AwIcon.vue';
import { hasIcon } from '../enterprise/icons.js';
import LatinWords from './LatinWords.vue';

/**
 * EE-143 — the grid was the homepage's four pillars and nothing else. The
 * enterprise page needs the same shape twice (who it is for; identity,
 * security and compliance), so the data becomes a prop and the heading pair
 * becomes optional. The defaults are today's values, so the homepage passes
 * nothing and renders exactly as it did.
 */
/*
 * OPH-388 — the enterprise page draws these cards the way the sales deck does
 * (slide 17): a line icon in a coloured circle beside the title, a coloured
 * left edge, and a phone capture beside the grid. All three are opt-in per
 * item or per prop: an `icon` that is not a key of icons.js is printed as text
 * exactly as before, so the homepage's emoji pillars do not change.
 */
defineProps({
  items: { type: Array, default: () => pillars },
  eyebrow: { type: String, default: '' },
  title: { type: String, default: '' },
  lede: { type: String, default: '' },
  /** `{ shot, shotDark?, alt, ratio? }` — a phone capture beside the cards. */
  shot: { type: Object, default: null },
});

/** 'primary' | 'tertiary' | 'secondary' | 'warning' → the card's edge and icon fill. */
const ACCENTS = ['primary', 'tertiary', 'secondary', 'warning'];
const accentOf = (p) => (ACCENTS.includes(p.accent) ? p.accent : '');
</script>

<template>
  <section class="aw-section pillars">
    <div class="aw-shell">
      <header v-if="title" class="pillars__head">
        <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>
      <div :class="{ pillars__split: !!shot }">
        <ScreenshotFrame
          v-if="shot"
          class="pillars__shot"
          :src="shot.shot"
          :src-dark="shot.shotDark || ''"
          :alt="shot.alt"
          variant="phone"
          :ratio="shot.ratio || ''"
          :notch="false"
        />
        <div class="pillars__grid">
          <article
            v-for="(p, i) in items"
            :key="p.key"
            v-reveal="{ delay: i * 70 }"
            class="aw-card pillars__card"
            :class="accentOf(p) && ['pillars__card--accent', `is-${accentOf(p)}`]"
          >
            <div v-if="hasIcon(p.icon)" class="pillars__row">
              <span class="pillars__svg"><AwIcon :name="p.icon" :size="26" /></span>
              <h3>{{ p.title }}</h3>
            </div>
            <template v-else>
              <span class="pillars__icon" aria-hidden="true">{{ p.icon }}</span>
              <h3>{{ p.title }}</h3>
            </template>
            <p>{{ p.body }}</p>
          </article>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.pillars {
  padding-block: clamp(3rem, 7vw, 5.5rem);
}

.pillars__head {
  max-width: 46rem;
  margin-bottom: 2rem;
}

.pillars__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 1.15rem;
}

.pillars__card {
  padding: 1.6rem 1.5rem;
}

.pillars__card h3 {
  margin-bottom: 0.4rem;
}

.pillars__card p {
  margin: 0;
  color: var(--aw-text-dim);
  font-size: 0.97rem;
}

.pillars__icon {
  display: block;
  font-size: 1.9rem;
  line-height: 1;
  margin-bottom: 0.85rem;
}

/* ── OPH-388: line icons, accents, a phone beside the grid ──────────────── */

.pillars__row {
  display: flex;
  align-items: center;
  gap: 0.9rem;
  margin-bottom: 0.85rem;
}

.pillars__row h3 {
  margin: 0;
}

.pillars__svg {
  display: grid;
  place-items: center;
  flex-shrink: 0;
  width: 3.25rem;
  height: 3.25rem;
  border-radius: 50%;
  background: color-mix(in srgb, var(--aw-primary) 13%, var(--aw-surface));
  color: var(--aw-primary-strong);
}

/* The accent fills the circle and the icon takes the SURFACE colour: in light
   mode that is white on a deep colour, in dark mode the dark surface on a
   light one — so the pair holds 3:1 in both themes without a second set. */
.pillars__card--accent {
  border-left: 5px solid var(--_accent);
}
.pillars__card--accent .pillars__svg {
  background: var(--_accent);
  color: var(--aw-surface);
}
.is-primary {
  --_accent: var(--aw-primary);
}
.is-tertiary {
  --_accent: var(--aw-tertiary);
}
.is-secondary {
  --_accent: var(--aw-secondary);
}
.is-warning {
  --_accent: var(--aw-warning);
}

.pillars__split {
  display: grid;
  grid-template-columns: 16.5rem minmax(0, 1fr);
  gap: clamp(1.5rem, 3vw, 2.5rem);
  align-items: center;
}

.pillars__split .pillars__grid {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 19rem), 1fr));
}

.pillars__shot {
  width: 100%;
}

@media (max-width: 820px) {
  .pillars__split {
    grid-template-columns: 1fr;
  }
  .pillars__shot {
    width: min(16.5rem, 100%);
    justify-self: center;
    order: 2;
  }
}
</style>
