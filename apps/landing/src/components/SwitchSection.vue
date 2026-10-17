<script setup>
import { switchFrom } from "../content.js";

/**
 * OPH-371 — "Switch from Todoist or TickTick". Words, not a screenshot: the
 * person reading this wants to know whether THEIR data comes over, so the
 * mapping is the artwork. The honest line about Apple Reminders is part of the
 * section, not a footnote.
 */
defineProps({
  block: { type: Object, default: () => switchFrom },
});
</script>

<template>
  <section id="switch" v-reveal class="aw-section switch">
    <div class="aw-shell">
      <header class="switch__head">
        <p class="aw-eyebrow">{{ block.eyebrow }}</p>
        <h2>{{ block.title }}</h2>
        <p class="aw-lede">{{ block.lede }}</p>
      </header>

      <ol class="switch__steps">
        <li
          v-for="(s, i) in block.steps"
          :key="s.title"
          class="aw-card switch__step"
        >
          <span class="switch__num" aria-hidden="true">{{ i + 1 }}</span>
          <h3>{{ s.title }}</h3>
          <p>{{ s.body }}</p>
        </li>
      </ol>

      <div class="aw-card switch__map">
        <ul>
          <li v-for="m in block.mapping" :key="m">{{ m }}</li>
        </ul>
        <p class="switch__note">{{ block.note }}</p>
        <a class="aw-btn aw-btn--ghost" :href="block.link.href">{{
          block.link.label
        }}</a>
      </div>
    </div>
  </section>
</template>

<style scoped>
.switch__head {
  max-width: 46rem;
  margin-bottom: 2rem;
}

.switch__steps {
  list-style: none;
  margin: 0 0 1.15rem;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 1.15rem;
}

.switch__step {
  padding: 1.6rem 1.5rem;
}

.switch__step h3 {
  margin: 0.75rem 0 0.4rem;
}

.switch__step p {
  margin: 0;
  color: var(--aw-text-dim);
}

.switch__num {
  display: inline-grid;
  place-items: center;
  width: 2.25rem;
  height: 2.25rem;
  border-radius: 999px;
  background: var(--aw-surface-2);
  color: var(--aw-text);
  font-weight: 700;
}

.switch__map {
  padding: 1.6rem 1.5rem;
}

.switch__map ul {
  margin: 0 0 1rem;
  padding-left: 1.15rem;
  display: grid;
  gap: 0.55rem;
  color: var(--aw-text-dim);
}

.switch__note {
  margin: 0 0 1.25rem;
  color: var(--aw-text);
  font-weight: 600;
}
</style>
