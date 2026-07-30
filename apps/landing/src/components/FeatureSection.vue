<script setup>
import ScreenshotFrame from './ScreenshotFrame.vue';

/**
 * One feature: copy on one side, a screenshot on the other, alternating.
 * `flip` is passed by the parent rather than computed from an index here, so
 * the order can be rearranged without the zig-zag falling out of step.
 */
defineProps({
  feature: { type: Object, required: true },
  flip: { type: Boolean, default: false },
});
</script>

<template>
  <article class="feature" :class="{ 'feature--flip': flip }" v-reveal>
    <div class="feature__copy">
      <p class="aw-eyebrow">{{ feature.eyebrow }}</p>
      <h2>{{ feature.title }}</h2>
      <p class="aw-lede">{{ feature.body }}</p>
      <ul class="feature__points">
        <li v-for="point in feature.points" :key="point">
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
          <span>{{ point }}</span>
        </li>
      </ul>
    </div>

    <ScreenshotFrame
      class="feature__shot"
      :src="`/shots/${feature.shot}`"
      :alt="feature.alt"
      :label="`alliswell.space/app — ${feature.eyebrow}`"
    />
  </article>
</template>

<style scoped>
.feature {
  display: grid;
  grid-template-columns: minmax(0, 5fr) minmax(0, 7fr);
  gap: clamp(2rem, 5vw, 4rem);
  align-items: center;
  padding-block: clamp(3rem, 6vw, 5rem);
}

.feature--flip .feature__copy {
  order: 2;
}

.feature h2 {
  margin-bottom: 0.6rem;
}

.feature__points {
  list-style: none;
  margin: 1.5rem 0 0;
  padding: 0;
  display: grid;
  gap: 0.7rem;
}

.feature__points li {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.7rem;
  align-items: start;
  font-size: 0.97rem;
  color: var(--aw-text-dim);
}

.feature__points svg {
  color: var(--aw-success);
  margin-top: 2px;
  flex-shrink: 0;
}

@media (max-width: 900px) {
  .feature {
    grid-template-columns: 1fr;
  }
  .feature--flip .feature__copy {
    order: 0;
  }
}
</style>
