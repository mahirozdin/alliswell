<script setup>
import ScreenshotFrame from '../components/ScreenshotFrame.vue';

/**
 * An ordered walk through one flow (EE-153).
 *
 * `PillarGrid` cannot do this job: it is an unordered auto-fit grid, and the
 * whole point of the public request flow is that step three cannot happen
 * before step two. The numbers and the connecting rule are the content, not
 * decoration — so this is an `<ol>` and reads as one with the stylesheet off.
 *
 * Not every step has a picture. Three of the five here are things a person
 * sees; two are things the SERVER does — the request lands in the answering
 * unit's queue and a clock starts — and inventing a screenshot for those would
 * be inventing a screen.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  steps: { type: Array, required: true },
  /** The abuse note under the walk — a box, because it answers a fear. */
  aside: { type: Object, default: null },
});
</script>

<template>
  <section v-reveal class="aw-section steps">
    <div class="aw-shell">
      <header class="steps__head">
        <p v-if="eyebrow" class="aw-eyebrow">{{ eyebrow }}</p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <ol class="steps__list">
        <li v-for="step in steps" :key="step.n" class="steps__item">
          <div class="steps__marker" aria-hidden="true">{{ step.n }}</div>
          <div class="steps__body">
            <h3>{{ step.title }}</h3>
            <p>{{ step.body }}</p>
            <ScreenshotFrame
              v-if="step.shot"
              class="steps__shot"
              :src="step.shot"
              :src-dark="step.shotDark || ''"
              :alt="step.alt"
              :variant="step.frame || 'browser'"
              :label="step.frameLabel || ''"
            />
          </div>
        </li>
      </ol>

      <aside v-if="aside" class="aw-card steps__aside">
        <h3>{{ aside.title }}</h3>
        <p>{{ aside.body }}</p>
        <ul>
          <li v-for="p in aside.points" :key="p">{{ p }}</li>
        </ul>
      </aside>
    </div>
  </section>
</template>

<style scoped>
.steps__head {
  max-width: 46rem;
  margin-bottom: 2.5rem;
}

.steps__list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 2.25rem;
}

.steps__item {
  display: grid;
  grid-template-columns: 2.5rem minmax(0, 1fr);
  gap: 1.25rem;
  position: relative;
}

/* The rule that makes this a sequence rather than a list. It stops at the last
   marker rather than running past it, because a line that continues implies a
   step nobody wrote. */
.steps__item:not(:last-child)::before {
  content: '';
  position: absolute;
  left: 1.24rem;
  top: 2.75rem;
  bottom: -2.25rem;
  width: 2px;
  background: var(--aw-hairline);
}

.steps__marker {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 999px;
  border: 1px solid var(--aw-hairline);
  background: var(--aw-surface);
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: var(--aw-text);
}

.steps__body h3 {
  margin: 0.3rem 0 0.4rem;
}

.steps__body p {
  margin: 0;
  color: var(--aw-text-dim);
  max-width: 44rem;
}

.steps__shot {
  margin-top: 1.15rem;
  max-width: 40rem;
}

.steps__aside {
  margin-top: 2.75rem;
  padding: 1.6rem 1.7rem;
}

.steps__aside h3 {
  margin: 0 0 0.4rem;
}

.steps__aside p {
  margin: 0 0 0.9rem;
  color: var(--aw-text-dim);
}

.steps__aside ul {
  margin: 0;
  padding-left: 1.15rem;
  color: var(--aw-text-dim);
  font-size: 0.95rem;
  display: grid;
  gap: 0.3rem;
}

@media (max-width: 640px) {
  .steps__item {
    grid-template-columns: 2rem minmax(0, 1fr);
    gap: 0.85rem;
  }
  .steps__item:not(:last-child)::before {
    left: 0.97rem;
  }
  .steps__marker {
    width: 2rem;
    height: 2rem;
    font-size: 0.9rem;
  }
}
</style>
