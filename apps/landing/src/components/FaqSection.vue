<script setup>
import { faq } from '../content.js';
</script>

<template>
  <section v-reveal class="aw-section">
    <div class="aw-shell faq">
      <h2>Questions people actually ask</h2>
      <div class="faq__list">
        <details v-for="(item, i) in faq" :key="item.q" :open="i === 0" class="aw-card faq__item">
          <summary>
            {{ item.q }}
            <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true">
              <path d="M12 15.4 6.6 10l1.4-1.4 4 4 4-4L17.4 10z" />
            </svg>
          </summary>
          <p>{{ item.a }}</p>
        </details>
      </div>
    </div>
  </section>
</template>

<style scoped>
.faq {
  max-width: 52rem;
}

.faq h2 {
  margin-bottom: 1.75rem;
}

.faq__list {
  display: grid;
  gap: 0.75rem;
}

.faq__item {
  padding: 0;
  overflow: hidden;
}

summary {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 1.1rem 1.35rem;
  font-weight: 620;
  cursor: pointer;
  list-style: none;
}

summary::-webkit-details-marker {
  display: none;
}

summary svg {
  flex-shrink: 0;
  color: var(--aw-text-dim);
  transition: rotate 0.2s var(--aw-ease);
}

details[open] summary svg {
  rotate: 180deg;
}

.faq__item p {
  margin: 0;
  padding: 0 1.35rem 1.3rem;
  color: var(--aw-text-dim);
  font-size: 0.97rem;
}
</style>
