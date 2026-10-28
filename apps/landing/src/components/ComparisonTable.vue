<script setup>
import { computed } from 'vue';

import { comparison, DOCS_URL } from '../content.js';
import LatinWords from './LatinWords.vue';

/**
 * EE-143 — the whole table, its headings and its three cell words become one
 * prop. The enterprise page's package comparison is the same object with
 * different rows, and `cell()` already passes anything it does not recognise
 * through as free text, so '250 seats' and '90 days' render without a change.
 */
const props = defineProps({
  table: {
    type: Object,
    default: () => ({
      eyebrow: 'Honest comparison',
      title: 'Where AllisWell is actually different',
      lede:
        'Not a scorecard designed to be won. The full analysis — including the six things ' +
        'these apps do better than we do — is in the repository.',
      caption: 'Feature comparison table',
      featureHeading: 'Feature',
      labels: { yes: 'Yes', no: 'No', partial: 'Partial' },
      columns: comparison.columns,
      rows: comparison.rows,
      footnote: comparison.footnote,
      link: { label: 'Read it →', href: `${DOCS_URL}/COMPARISON.md` },
    }),
  },
  /** The homepage owns `#compare`; a second page must not claim the same id. */
  anchor: { type: String, default: 'compare' },
  /**
   * Which data column is tinted as "ours". The homepage's first column is
   * AllisWell against four competitors; the enterprise package table has no
   * such column — its first one is merely the smallest package, and tinting it
   * read as a recommendation nobody made. `-1` tints nothing (EE-164).
   */
  highlight: { type: Number, default: 0 },
});

/**
 * OPH-388 — `table.pinnedRows` (a number) keeps the first N rows in view and
 * folds the rest into a `<details>` titled `table.moreLabel`. The enterprise
 * package table has three rows a buyer compares (seats, units, history) and
 * some twenty-five capability rows that are reference, not argument; open, it
 * was the longest thing on the page. Absent, the table renders whole, as the
 * homepage's does. The folded rows are a second table with the same head, so
 * a screen reader inside it still knows which column is which.
 */
const pinned = computed(() => {
  const n = props.table.pinnedRows;
  return Number.isInteger(n) && n > 0 && n < props.table.rows.length ? n : 0;
});
const groups = computed(() =>
  pinned.value
    ? [props.table.rows.slice(0, pinned.value), props.table.rows.slice(pinned.value)]
    : [props.table.rows],
);

/** 'yes' | 'no' | 'partial' | free text → a cell that reads without colour alone. */
function cell(value) {
  const l = props.table.labels;
  if (value === 'yes') return { mark: '●', label: l.yes, tone: 'yes' };
  if (value === 'no') return { mark: '○', label: l.no, tone: 'no' };
  if (value === 'partial') return { mark: '◐', label: l.partial, tone: 'partial' };
  return { mark: null, label: value, tone: 'text' };
}
</script>

<template>
  <section :id="anchor" v-reveal class="aw-section">
    <div class="aw-shell">
      <header class="cmp__head">
        <p class="aw-eyebrow"><LatinWords :text="table.eyebrow" /></p>
        <h2>{{ table.title }}</h2>
        <p class="aw-lede">{{ table.lede }}</p>
      </header>

      <template v-for="(rows, g) in groups" :key="g">
        <component
          :is="g === 0 ? 'div' : 'details'"
          :class="g === 0 ? 'cmp__group' : 'cmp__more'"
        >
          <summary v-if="g > 0" class="cmp__summary">
            {{ table.moreLabel }}
            <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true">
              <path d="M12 15.4 6.6 10l1.4-1.4 4 4 4-4L17.4 10z" />
            </svg>
          </summary>
          <div
            class="cmp__scroll"
            tabindex="0"
            role="region"
            :aria-label="g === 0 ? table.caption : `${table.caption} — ${table.moreLabel}`"
          >
            <table class="cmp" :class="{ 'cmp--fixed': pinned > 0 }">
              <thead>
                <tr>
                  <th scope="col" class="cmp__feature">{{ table.featureHeading }}</th>
                  <th
                    v-for="(c, i) in table.columns"
                    :key="c"
                    scope="col"
                    :class="{ 'cmp__ours': i === highlight }"
                  >
                    <LatinWords :text="c" />
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in rows" :key="row[0]">
                  <th scope="row" class="cmp__feature">{{ row[0] }}</th>
                  <td
                    v-for="(value, i) in row.slice(1)"
                    :key="i"
                    :class="[`is-${cell(value).tone}`, { 'cmp__ours': i === highlight }]"
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
        </component>
      </template>

      <p class="cmp__note">
        {{ table.footnote }}
        <a :href="table.link.href" rel="noopener" target="_blank">{{ table.link.label }}</a>
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

/* ── OPH-388: pinned rows and the fold ─────────────────────────────────── */

/* Both halves of a folded table share one column grid, so the folded rows
   line up under the pinned ones. */
.cmp--fixed {
  table-layout: fixed;
}
.cmp--fixed .cmp__feature {
  width: 46%;
}
.cmp--fixed td,
.cmp--fixed thead th:not(.cmp__feature) {
  white-space: normal;
}

.cmp__more {
  margin-top: 0.85rem;
}

.cmp__summary {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  min-height: 48px;
  padding: 0.6rem 1.15rem;
  border-radius: var(--aw-radius);
  border: 1px solid var(--aw-hairline);
  background: var(--aw-surface);
  box-shadow: var(--aw-shadow-sm);
  font-weight: 650;
  cursor: pointer;
  list-style: none;
}
.cmp__summary::-webkit-details-marker {
  display: none;
}
.cmp__summary svg {
  color: var(--aw-text-dim);
  transition: rotate 0.18s var(--aw-ease);
}
.cmp__more[open] .cmp__summary {
  margin-bottom: 0.85rem;
}
.cmp__more[open] .cmp__summary svg {
  rotate: 180deg;
}

.cmp__note {
  margin-top: 1rem;
  font-size: 0.88rem;
  color: var(--aw-text-dim);
}
</style>
