<script setup>
import LatinWords from '../components/LatinWords.vue';

/**
 * A heading for a run of sections, not a section of its own (OPH-388).
 *
 * After the factory story ends (slide 17), the page keeps four things the deck
 * does not show — the daily work, identity, meeting notes, cloud or own
 * server. They are grouped under one "Also" heading so a reader can tell the
 * argument has finished and the reference has begun.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
});
</script>

<template>
  <header v-reveal class="aw-shell group">
    <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
    <h2>{{ title }}</h2>
    <p v-if="lede" class="aw-lede">{{ lede }}</p>
  </header>
</template>

<style scoped>
.group {
  padding-top: clamp(3rem, 7vw, 5.5rem);
  margin-bottom: clamp(-1rem, -2vw, -0.5rem);
  border-top: 1px solid var(--aw-hairline);
}

.group h2 {
  max-width: 46rem;
  margin-bottom: 0.6rem;
}
</style>
