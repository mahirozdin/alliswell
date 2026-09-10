<script setup>
import { comparison, DOCS_URL } from '../content.js';

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
        <p class="aw-eyebrow">{{ table.eyebrow }}</p>
        <h2>{{ table.title }}</h2>
        <p class="aw-lede">{{ table.lede }}</p>
      </header>

      <div class="cmp__scroll" tabindex="0" role="region" :aria-label="table.caption">
        <table class="cmp">
          <thead>
            <tr>
              <th scope="col" class="cmp__feature">{{ table.featureHeading }}</th>
              <th
                v-for="(c, i) in table.columns"
                :key="c"
                scope="col"
                :class="{ 'cmp__ours': i === highlight }"
              >
                {{ c }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in table.rows" :key="row[0]">
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

.cmp__note {
  margin-top: 1rem;
  font-size: 0.88rem;
  color: var(--aw-text-dim);
}
</style>
