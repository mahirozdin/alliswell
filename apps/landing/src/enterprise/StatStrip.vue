<script setup>
/**
 * A row of measured facts (EE-153).
 *
 * The rule this component exists to enforce is in its content, not its markup:
 * every value here is something that was MEASURED, and the ones that were not
 * are absent. "Tested at a million requests" is in the repository's benchmark
 * record; a millisecond figure is not, because the same query moved 23× between
 * two machines. A number a reader could check and find wrong costs more than
 * the number was worth.
 *
 * `note` is the small print under a figure — where the measurement came from —
 * because a bare number on a marketing page is a claim, and a number with its
 * provenance is evidence.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, default: '' },
  items: { type: Array, required: true },
});
</script>

<template>
  <section v-reveal class="aw-section strip">
    <div class="aw-shell">
      <header v-if="title" class="strip__head">
        <p v-if="eyebrow" class="aw-eyebrow">{{ eyebrow }}</p>
        <h2>{{ title }}</h2>
      </header>

      <dl class="strip__grid">
        <div v-for="item in items" :key="item.label" class="aw-card strip__cell">
          <dt>{{ item.value }}</dt>
          <dd>{{ item.label }}</dd>
          <p v-if="item.note" class="strip__note">{{ item.note }}</p>
        </div>
      </dl>
    </div>
  </section>
</template>

<style scoped>
.strip {
  padding-block: clamp(2.5rem, 6vw, 4rem);
}

.strip__head {
  max-width: 46rem;
  margin-bottom: 1.75rem;
}

.strip__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
  margin: 0;
}

.strip__cell {
  padding: 1.35rem 1.4rem;
}

.strip__cell dt {
  font-size: clamp(1.6rem, 3vw, 2.1rem);
  font-weight: 700;
  letter-spacing: -0.028em;
  line-height: 1.05;
  color: var(--aw-text);
}

.strip__cell dd {
  margin: 0.45rem 0 0;
  color: var(--aw-text-dim);
  font-size: 0.95rem;
}

.strip__note {
  margin: 0.55rem 0 0;
  color: var(--aw-text-dim);
  font-size: 0.82rem;
  opacity: 0.85;
}
</style>
