<script setup>
/**
 * The clamping claim, shown rather than asserted.
 *
 * Two columns of the same rule — "every month on the 31st" — resolved the way
 * RFC 5545 does it (the month is dropped) and the way AllisWell does it
 * (ADR-0020 §2: clamp backwards to the last real day). It is the single
 * sharpest difference against Google Calendar and it fits in a table.
 */
const months = [
  { label: 'December', them: '31 Dec', us: '31 Dec' },
  { label: 'January', them: '31 Jan', us: '31 Jan' },
  { label: 'February', them: null, us: '28 Feb' },
  { label: 'March', them: '31 Mar', us: '31 Mar' },
  { label: 'April', them: null, us: '30 Apr' },
];
</script>

<template>
  <section class="proof aw-section" v-reveal>
    <div class="aw-shell proof__inner">
      <div class="proof__copy">
        <p class="aw-eyebrow">Recurrence</p>
        <h2>“The 31st” should mean month end</h2>
        <p class="aw-lede">
          Set a monthly task on the 31st and a calendar that follows RFC&nbsp;5545 to the letter
          simply skips every month that has no 31st. Your rent does not skip February.
        </p>
        <p class="proof__note">
          AllisWell clamps backwards to the last real day — per value, and the result is a set, so
          a window like 23–29 in a 28-day February collapses instead of emitting the 28th twice.
        </p>
      </div>

      <div class="aw-card proof__table">
        <div class="proof__head">
          <span>Rule: every month on day 31</span>
        </div>
        <table>
          <thead>
            <tr>
              <th scope="col">Month</th>
              <th scope="col">RFC 5545 / Google</th>
              <th scope="col">AllisWell</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in months" :key="m.label">
              <th scope="row">{{ m.label }}</th>
              <td :class="{ 'is-missing': !m.them }">
                <template v-if="m.them">{{ m.them }}</template>
                <template v-else>— skipped —</template>
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
