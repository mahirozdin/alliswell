<script setup>
import { pillars } from '../content.js';

/**
 * EE-143 — the grid was the homepage's four pillars and nothing else. The
 * enterprise page needs the same shape twice (who it is for; identity,
 * security and compliance), so the data becomes a prop and the heading pair
 * becomes optional. The defaults are today's values, so the homepage passes
 * nothing and renders exactly as it did.
 */
defineProps({
  items: { type: Array, default: () => pillars },
  eyebrow: { type: String, default: '' },
  title: { type: String, default: '' },
});
</script>

<template>
  <section class="aw-section pillars">
    <div class="aw-shell">
      <header v-if="title" class="pillars__head">
        <p v-if="eyebrow" class="aw-eyebrow">{{ eyebrow }}</p>
        <h2>{{ title }}</h2>
      </header>
      <div class="pillars__grid">
        <article
          v-for="(p, i) in items"
          :key="p.key"
          v-reveal="{ delay: i * 70 }"
          class="aw-card pillars__card"
        >
          <span class="pillars__icon" aria-hidden="true">{{ p.icon }}</span>
          <h3>{{ p.title }}</h3>
          <p>{{ p.body }}</p>
        </article>
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
</style>
