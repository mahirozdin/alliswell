<script setup>
import { recurrence as recurrenceDefault } from '../content.js';

/**
 * The clamping claim, shown rather than asserted.
 *
 * Two columns of the same rule — "every month on the 31st" — resolved the way
 * RFC 5545 does it (the month is dropped) and the way AllisWell does it
 * (ADR-0020 §2: clamp backwards to the last real day). It is the single
 * sharpest difference against Google Calendar and it fits in a table.
 *
 * EE-164 — the words and the month rows live in content.js now, so the
 * Turkish homepage can pass its own; the default is the English set.
 */
defineProps({
  /** `{ eyebrow, title, lede, note, rule, columns: { month, them, us }, skipped, months }` */
  recurrence: { type: Object, default: () => recurrenceDefault },
});
</script>

<template>
  <section v-reveal class="proof aw-section">
    <div class="aw-shell proof__inner">
      <div class="proof__copy">
        <p class="aw-eyebrow">{{ recurrence.eyebrow }}</p>
        <h2>{{ recurrence.title }}</h2>
        <p class="aw-lede">{{ recurrence.lede }}</p>
        <p class="proof__note">{{ recurrence.note }}</p>
      </div>

      <div class="aw-card proof__table">
        <div class="proof__head">
          <span>{{ recurrence.rule }}</span>
        </div>
        <table>
          <thead>
            <tr>
              <th scope="col">{{ recurrence.columns.month }}</th>
              <th scope="col">{{ recurrence.columns.them }}</th>
              <th scope="col">{{ recurrence.columns.us }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in recurrence.months" :key="m.label">
              <th scope="row">{{ m.label }}</th>
              <td :class="{ 'is-missing': !m.them }">
                <template v-if="m.them">{{ m.them }}</template>
                <template v-else>{{ recurrence.skipped }}</template>
              </td>
              <td class="is-ours">{{ m.us }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </section>
</template>

<style scoped>
.proof__inner {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: clamp(2rem, 5vw, 4rem);
  align-items: center;
}

.proof__note {
  font-size: 0.95rem;
  color: var(--aw-text-dim);
}

.proof__table {
  overflow: hidden;
}

.proof__head {
  padding: 0.85rem 1.25rem;
  background: var(--aw-surface-2);
  border-bottom: 1px solid var(--aw-hairline);
  font-size: 0.85rem;
  font-weight: 640;
  color: var(--aw-text-dim);
  font-family: ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.95rem;
}

th,
td {
  padding: 0.8rem 1.25rem;
  text-align: left;
  border-bottom: 1px solid var(--aw-hairline);
}

tbody tr:last-child th,
tbody tr:last-child td {
  border-bottom: 0;
}

thead th {
  font-size: 0.78rem;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--aw-text-dim);
  font-weight: 640;
}

tbody th {
  font-weight: 600;
}

.is-missing {
  color: var(--aw-error);
  font-variant-numeric: tabular-nums;
}

.is-ours {
  color: var(--aw-success);
  font-weight: 640;
  font-variant-numeric: tabular-nums;
}

@media (max-width: 900px) {
  .proof__inner {
    grid-template-columns: 1fr;
  }
}
</style>
