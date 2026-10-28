<script setup>
import LatinWords from '../components/LatinWords.vue';

/**
 * What the team sees, and what the requester sees (OPH-388, deck slide 14).
 *
 * The desk works with five detailed states; the person who asked sees a plain
 * word for each, and nothing internal (whose approval is awaited) leaves the
 * building. Two rows joined by dashed lines say that faster than a paragraph,
 * and the two boxes under them carry the two rules a buyer asks about: what
 * "waiting" does to the clock, and what happens after "solved".
 *
 * ── ONE LIST, TWO ROWS ────────────────────────────────────────────────────
 *
 * Semantically this is ONE ordered list of states, each item holding the
 * team's word and the requester's word — that pairing is the content, and two
 * separate lists would lose it for a screen reader. The two rows are a CSS
 * subgrid: every item spans the same five tracks (row label, team pill,
 * connector, row label, requester pill), so the pills line up across items
 * without a table. The row labels are drawn once, in the first item, and are
 * decorative; each pill carries its row's name as visually hidden text.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  teamLabel: { type: String, required: true },
  requesterLabel: { type: String, required: true },
  /** `[{ team, requester, tone: 'progress'|'done' }]` */
  states: { type: Array, required: true },
  /** `{ title, hint, reasons: [...], body }` */
  waiting: { type: Object, default: null },
  /** `{ title, body }` */
  after: { type: Object, default: null },
});
</script>

<template>
  <section v-reveal class="aw-section sf">
    <div class="aw-shell">
      <header class="sf__head">
        <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <ol class="sf__states" :style="{ '--_n': states.length }">
        <li v-for="(s, i) in states" :key="s.team" class="sf__state">
          <span class="sf__label sf__label--team" aria-hidden="true">{{ i === 0 ? teamLabel : '' }}</span>
          <span class="sf__pill sf__pill--team" :class="`is-${s.tone || 'progress'}`">
            <span class="aw-visually-hidden">{{ teamLabel }}: </span>{{ s.team }}
            <svg
              v-if="i > 0"
              class="sf__arrow"
              viewBox="0 0 24 24"
              width="18"
              height="18"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              aria-hidden="true"
            >
              <path d="M5 12h14" />
              <path d="m12 5 7 7-7 7" />
            </svg>
          </span>
          <span class="sf__link" aria-hidden="true" />
          <span class="sf__label sf__label--requester" aria-hidden="true">{{
            i === 0 ? requesterLabel : ''
          }}</span>
          <span class="sf__pill sf__pill--requester">
            <span class="aw-visually-hidden">{{ requesterLabel }}: </span>{{ s.requester }}
          </span>
        </li>
      </ol>

      <div v-if="waiting || after" class="sf__boxes">
        <div v-if="waiting" class="sf__box sf__box--waiting">
          <h3>
            {{ waiting.title }}
            <small v-if="waiting.hint">{{ waiting.hint }}</small>
          </h3>
          <ul v-if="waiting.reasons && waiting.reasons.length" class="sf__reasons">
            <li v-for="r in waiting.reasons" :key="r">{{ r }}</li>
          </ul>
          <p>{{ waiting.body }}</p>
        </div>
        <div v-if="after" class="aw-card sf__box sf__box--after">
          <h3>{{ after.title }}</h3>
          <p>{{ after.body }}</p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.sf {
  padding-block: clamp(3rem, 7vw, 5.5rem);
  --_gap: 2.75rem;
}

.sf__head {
  max-width: 50rem;
  margin-bottom: 2.25rem;
}

/* ── wide: two rows of pills, one column per state ──────────────────────── */

.sf__states {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(var(--_n), minmax(0, 1fr));
  grid-template-rows: auto auto 2.25rem auto auto;
  column-gap: var(--_gap);
}

.sf__state {
  display: grid;
  grid-row: span 5;
  grid-template-rows: subgrid;
  justify-items: stretch;
}

.sf__label {
  font-size: 0.9rem;
  font-weight: 650;
  white-space: nowrap;
  min-height: 1.6rem;
  overflow: visible;
}
.sf__label--team {
  color: var(--aw-primary-strong);
}
.sf__label--requester {
  color: var(--aw-tertiary-text);
  margin-top: 0.35rem;
}

.sf__pill {
  position: relative;
  display: grid;
  place-items: center;
  min-height: 3.5rem;
  padding: 0.6rem 0.75rem;
  border-radius: var(--aw-radius-sm);
  text-align: center;
  font-weight: 650;
  line-height: 1.25;
}

.sf__pill--team {
  background: var(--aw-fill-progress);
  color: var(--aw-on-fill);
  font-size: 1.02rem;
}
.sf__pill--team.is-done {
  background: var(--aw-fill-done);
}

.sf__pill--requester {
  min-height: 3rem;
  background: color-mix(in srgb, var(--aw-tertiary) 9%, var(--aw-surface));
  border: 1px solid var(--aw-tertiary);
  color: var(--aw-tertiary-text);
  font-size: 0.97rem;
}

.sf__arrow {
  position: absolute;
  top: 50%;
  left: calc(var(--_gap) / -2);
  translate: -50% -50%;
  color: var(--aw-text-dim);
}

.sf__link {
  justify-self: center;
  width: 0;
  border-left: 2px dashed var(--aw-hairline);
}

/* ── the two boxes ──────────────────────────────────────────────────────── */

.sf__boxes {
  display: grid;
  grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
  gap: 1.25rem;
  margin-top: 2rem;
}

.sf__box {
  padding: clamp(1.25rem, 2.5vw, 1.6rem);
  border-radius: var(--aw-radius);
}

.sf__box h3 {
  font-size: 1.15rem;
  margin-bottom: 0.5rem;
}

.sf__box p {
  margin: 0;
  color: var(--aw-text-dim);
  font-size: 0.97rem;
}

.sf__box--waiting {
  background: color-mix(in srgb, var(--aw-warning) 10%, var(--aw-surface));
  border: 1px solid var(--aw-warning);
}

.sf__box--waiting h3 {
  color: var(--aw-warning-text);
}

.sf__box--waiting small {
  margin-left: 0.4rem;
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--aw-text-dim);
}

.sf__reasons {
  list-style: none;
  margin: 0 0 0.6rem;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem 0;
  font-weight: 650;
  color: var(--aw-text);
}

.sf__reasons li:not(:last-child)::after {
  content: '·';
  margin-inline: 0.55rem;
  color: var(--aw-text-dim);
}

.sf__box--after h3 {
  color: var(--aw-success);
}

/* ── narrow: one row per state, the team's word beside the requester's ──── */

@media (max-width: 820px) {
  .sf__states {
    grid-template-columns: minmax(0, 1fr) 2rem minmax(0, 1fr);
    grid-template-rows: none;
    row-gap: 0.75rem;
  }
  .sf__state {
    grid-row: auto;
    grid-column: 1 / -1;
    grid-template-columns: subgrid;
    grid-template-rows: none;
    grid-template-areas:
      'lt . lr'
      'pt ln pr';
    align-items: center;
  }
  .sf__label--team {
    grid-area: lt;
  }
  .sf__label--requester {
    grid-area: lr;
    margin-top: 0;
  }
  .sf__state:not(:first-child) .sf__label {
    display: none;
  }
  .sf__pill--team {
    grid-area: pt;
  }
  .sf__pill--requester {
    grid-area: pr;
  }
  .sf__link {
    grid-area: ln;
    width: auto;
    height: 0;
    border-left: 0;
    border-top: 2px dashed var(--aw-hairline);
    justify-self: stretch;
  }
  .sf__arrow {
    display: none;
  }
  .sf__label {
    white-space: normal;
  }
  .sf__boxes {
    grid-template-columns: 1fr;
  }
}
</style>
