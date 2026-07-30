<script setup>
import { comparison, DOCS_URL } from '../content.js';

/** 'yes' | 'no' | 'partial' | free text → a cell that reads without colour alone. */
function cell(value) {
  if (value === 'yes') return { mark: '●', label: 'Yes', tone: 'yes' };
  if (value === 'no') return { mark: '○', label: 'No', tone: 'no' };
  if (value === 'partial') return { mark: '◐', label: 'Partial', tone: 'partial' };
  return { mark: null, label: value, tone: 'text' };
}
</script>

<template>
  <section id="compare" class="aw-section" v-reveal>
    <div class="aw-shell">
      <header class="cmp__head">
        <p class="aw-eyebrow">Honest comparison</p>
        <h2>Where AllisWell is actually different</h2>
        <p class="aw-lede">
          Not a scorecard designed to be won. The full analysis — including the six things these
          apps do better than we do — is in the repository.
        </p>
      </header>

      <div class="cmp__scroll" tabindex="0" role="region" aria-label="Feature comparison table">
        <table class="cmp">
          <thead>
            <tr>
              <th scope="col" class="cmp__feature">Feature</th>
              <th
                v-for="(c, i) in comparison.columns"
                :key="c"
                scope="col"
                :class="{ 'cmp__ours': i === 0 }"
              >
                {{ c }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in comparison.rows" :key="row[0]">
              <th scope="row" class="cmp__feature">{{ row[0] }}</th>
              <td
                v-for="(value, i) in row.slice(1)"
                :key="i"
                :class="[`is-${cell(value).tone}`, { 'cmp__ours': i === 0 }]"
              >
                <span v-if="cell(value).mark" class="cmp__mark" aria-hidden="true">{{
                  cell(value).mark
                }}</span>
                <span :class="{ 'aw-visually-hidden': !!cell(value).mark }">{{
                  cell(value).label
                }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p class="cmp__note">
        {{ comparison.footnote }}
        <a :href="`${DOCS_URL}/COMPARISON.md`" rel="noopener" target="_blank">Read it →</a>
      </p>
    </div>
  </section>
</template>

<style scoped>
.cmp__head {
  max-width: 46rem;
  margin-bottom: 2rem;
}

/* Wide content scrolls inside its own box — the page body never scrolls
   sideways, which is what makes this readable on a phone. */
.cmp__scroll {
  overflow-x: auto;
  border-radius: var(--aw-radius);
  border: 1px solid var(--aw-hairline);
  background: var(--aw-surface);
  box-shadow: var(--aw-shadow-sm);
  -webkit-overflow-scrolling: touch;
}

.cmp {
  width: 100%;
  min-width: 720px;
  border-collapse: collapse;
  font-size: 0.93rem;
}

.cmp th,
.cmp td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--aw-hairline);
  text-align: center;
  white-space: nowrap;
}

.cmp thead th {
  position: sticky;
  top: 0;
  background: var(--aw-surface-2);
  font-size: 0.8rem;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: var(--aw-text-dim);
  font-weight: 640;
}

.cmp__feature {
  text-align: left !important;
  font-weight: 600;
  white-space: normal !important;
  min-width: 230px;
}

.cmp__ours {
  background: color-mix(in srgb, var(--aw-primary) 7%, transparent);
}

.cmp thead .cmp__ours {
  color: var(--aw-primary-strong);
  background: color-mix(in srgb, var(--aw-primary) 14%, var(--aw-surface-2));
}

.cmp__mark {
  font-size: 1.15rem;
  line-height: 1;
}

.is-yes {
  color: var(--aw-success);
}
.is-no {
  color: color-mix(in srgb, var(--aw-text-dim) 65%, transparent);
}
.is-partial {
  color: var(--aw-warning);
}
.is-text {
  color: var(--aw-text-dim);
  font-size: 0.88rem;
}

.cmp tbody tr:last-child th,
.cmp tbody tr:last-child td {
  border-bottom: 0;
}

.cmp__note {
  margin-top: 1rem;
  font-size: 0.88rem;
  color: var(--aw-text-dim);
}
</style>
