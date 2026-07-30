<script setup>
import { pillars } from '../content.js';
</script>

<template>
  <section class="aw-section pillars">
    <div class="aw-shell">
      <div class="pillars__grid">
        <article
          v-for="(p, i) in pillars"
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
