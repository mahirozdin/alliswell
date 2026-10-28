<script setup>
import { computed } from 'vue';

import ScreenshotFrame from '../components/ScreenshotFrame.vue';
import LatinWords from '../components/LatinWords.vue';

/**
 * Screens with numbered marks, and the same numbers in a list beside them
 * (OPH-388) — the sales deck's way of explaining a screen.
 *
 * The page used to show one capture per tab with one caption under it, and the
 * reader had to find on their own which part of the picture the sentence was
 * about. The deck puts a blue "1" on the picture and a "1" in front of the
 * sentence; this is that, on the web.
 *
 * ── THE MARKS ARE DECORATION, THE LIST IS THE CONTENT ─────────────────────
 *
 * A mark is a number at `x`%/`y`% of the IMAGE's own box (ScreenshotFrame's
 * `.frame__media`, so a phone bezel or a browser bar does not shift it). It is
 * `aria-hidden`: a screen reader hears the alt text and then an ordered list,
 * which is everything the picture says. Nothing is said only by a mark.
 *
 * ── THREE LAYOUTS ─────────────────────────────────────────────────────────
 *
 *   side    the pictures in one column, the numbered list in the other (deck
 *           slides 5, 7, 10, 11). Takes part in the page's zig-zag via `flip`.
 *   grid    the pictures side by side across the shell, the list under them
 *           in as many columns (slides 4, 6, 8, 12).
 *   phones  a row of phone frames, each with a short titled caption under it
 *           (slide 9); with `items` the row and the list sit side by side
 *           (slides 13, 16).
 *
 * `cols: 2` (grid only) is slide 6's layout: two crops side by side, a third
 * under the first and the list in the cell beside it. A `tall: true` shot in a
 * `side` section is a portrait crop: it takes both rows of the left column and
 * the other two stack beside it (slide 11), instead of leading at full width.
 *
 * ── A NUMBER IS A PROMISE ─────────────────────────────────────────────────
 *
 * A list item gets its blue number only when some picture carries the same
 * mark. An item the screen does not show (it sits at the end of the list) gets
 * a plain dot, so the reader never looks for a "4" that is not there.
 *
 * `points` is the short tick list the FeatureSection rows had. It exists for
 * one reason that is not cosmetic: `check-copy.mjs` holds the request list
 * section (`itsm.points`) to the offline sentence in capabilities.js.
 */
const props = defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  /** 'side' | 'grid' | 'phones' */
  layout: { type: String, default: 'side' },
  /** `2` for the slide-6 grid (see above); anything else is the default grid. */
  cols: { type: Number, default: 0 },
  /**
   * `[{ shot, shotDark?, alt, frame?: 'card'|'phone', ratio?, tall?, marks?: [{ n, x, y, tone? }],
   *     title?, caption? }]`
   */
  shots: { type: Array, required: true },
  /** `[{ n, title, body }]` — `title` is the bold lead-in, `body` the rest of the sentence. */
  items: { type: Array, default: () => [] },
  points: { type: Array, default: () => [] },
  note: { type: String, default: '' },
  /** Copy first, pictures second. Decided by the parent's running count. */
  flip: { type: Boolean, default: false },
});

const hasCopy = computed(() => props.items.length > 0 || props.points.length > 0 || !!props.note);

/** Side by side: always for `side`, for `phones` when there is a list to sit beside. */
const split = computed(
  () => hasCopy.value && (props.layout === 'side' || (props.layout === 'phones' && props.items.length > 0)),
);

const frameOf = (shot) => shot.frame || 'card';

/** The numbers some picture carries; only these items get a numbered badge. */
const marked = computed(() => new Set(props.shots.flatMap((s) => (s.marks || []).map((m) => m.n))));

const pair = computed(() => props.layout === 'grid' && props.cols === 2);
</script>

<template>
  <section
    v-reveal
    class="aw-section ann"
    :class="[`ann--${layout}`, { 'ann--split': split, 'ann--flip': flip && split, 'ann--pair': pair }]"
  >
    <div class="aw-shell">
      <header class="ann__head">
        <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <div class="ann__body">
        <div class="ann__shots" :class="`ann__shots--n${Math.min(shots.length, 3)}`">
          <figure
            v-for="(s, i) in shots"
            :key="s.shot"
            class="ann__shot"
            :class="[`ann__shot--${frameOf(s)}`, { 'ann__shot--lead': i === 0, 'ann__shot--tall': s.tall }]"
          >
            <ScreenshotFrame
              :src="s.shot"
              :src-dark="s.shotDark || ''"
              :alt="s.alt"
              :variant="frameOf(s)"
              :ratio="s.ratio || ''"
              :notch="false"
            >
              <span
                v-for="m in s.marks || []"
                :key="m.n"
                class="ann__mark"
                :class="{ 'ann__mark--alert': m.tone === 'alert' }"
                :style="{ left: `${m.x}%`, top: `${m.y}%` }"
                aria-hidden="true"
                >{{ m.n }}</span
              >
            </ScreenshotFrame>
            <figcaption v-if="s.title || s.caption" class="ann__caption">
              <strong v-if="s.title">{{ s.title }}</strong>
              <span v-if="s.caption">{{ s.caption }}</span>
            </figcaption>
          </figure>
        </div>

        <div v-if="hasCopy" class="ann__copy">
          <ol v-if="items.length" class="ann__items">
            <li v-for="it in items" :key="it.n" :value="it.n">
              <span v-if="marked.has(it.n)" class="ann__n" aria-hidden="true">{{ it.n }}</span>
              <span v-else class="ann__n ann__n--plain" aria-hidden="true" />
              <p>
                <strong v-if="it.title">{{ it.title }}</strong>
                {{ it.body }}
              </p>
            </li>
          </ol>

          <ul v-if="points.length" class="ann__points">
            <li v-for="p in points" :key="p">
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
              <span>{{ p }}</span>
            </li>
          </ul>

          <p v-if="note" class="ann__note">{{ note }}</p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.ann {
  padding-block: clamp(3rem, 6vw, 5rem);
}

.ann__head {
  max-width: 50rem;
  margin-bottom: clamp(1.5rem, 3vw, 2.25rem);
}

.ann__head h2 {
  margin-bottom: 0.6rem;
}

.ann__body {
  display: grid;
  gap: clamp(1.75rem, 4vw, 3rem);
}

/* ── side by side ───────────────────────────────────────────────────────── */

.ann--split .ann__body {
  grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
  align-items: start;
}

.ann--phones.ann--split .ann__body {
  grid-template-columns: minmax(0, 6fr) minmax(0, 5fr);
}

.ann--flip .ann__shots {
  order: 2;
}

/* Flipped, the copy comes first — and the wider track goes with the
   pictures, not with whatever happens to be in the first column. */
.ann--flip .ann__body {
  grid-template-columns: minmax(0, 5fr) minmax(0, 7fr);
}
.ann--phones.ann--flip .ann__body {
  grid-template-columns: minmax(0, 5fr) minmax(0, 6fr);
}

/* ── the pictures ───────────────────────────────────────────────────────── */

.ann__shots {
  display: grid;
  gap: clamp(1rem, 2.5vw, 1.75rem);
  align-items: start;
  min-width: 0;
}

/* Two or three crops in the picture column of a split section: the first one
   leads at full width, the rest share the row under it. */
.ann--side .ann__shots--n2,
.ann--side .ann__shots--n3 {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
.ann--side .ann__shots--n3 .ann__shot--lead {
  grid-column: 1 / -1;
}
/* A portrait lead (slide 11) takes the left column's two rows; the other two
   crops stack beside it at a similar scale. */
.ann--side .ann__shots--n3 .ann__shot--lead.ann__shot--tall {
  grid-column: auto;
  grid-row: span 2;
}

.ann--grid .ann__shots--n2 {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
.ann--grid .ann__shots--n3 {
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

/* Slide 6: two crops side by side, the third under the first and the list in
   the cell beside it — the figures and the list share one two-column grid. */
.ann--pair .ann__body {
  grid-template-columns: repeat(2, minmax(0, 1fr));
  align-items: start;
}
.ann--pair .ann__shots {
  display: contents;
}
.ann--pair .ann__copy {
  align-self: center;
}
.ann--pair .ann__items {
  grid-template-columns: 1fr;
}

.ann--phones .ann__shots {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: clamp(1.25rem, 3vw, 2.25rem);
}

.ann__shot {
  margin: 0;
  min-width: 0;
  display: grid;
  gap: 0.85rem;
  align-content: start;
}

.ann--phones .ann__shot {
  flex: 1 1 13rem;
  max-width: 18.75rem;
}

/* A desktop crop in a row of phones (the absences screen beside Home, the
   knowledge base article beside a machine card) is a landscape picture: it
   takes the room of two phones, and wraps to a row of its own when that room
   is not there. */
.ann--phones .ann__shot--card {
  flex: 2 1 20rem;
  max-width: 36rem;
}

/* A phone among cards (a split `side` section with one phone crop) never grows
   past a phone's width, and sits centred in its cell. */
.ann__shot--phone :deep(.frame--phone) {
  width: 100%;
  max-width: 18.75rem;
  justify-self: center;
}
.ann__shot--phone {
  justify-items: center;
}

.ann__caption {
  display: grid;
  gap: 0.2rem;
  font-size: 0.95rem;
  line-height: 1.5;
  color: var(--aw-text-dim);
}

.ann--phones .ann__caption,
.ann__shot--phone .ann__caption {
  text-align: left;
  width: 100%;
}

.ann__caption strong {
  color: var(--aw-secondary);
  font-weight: 650;
}

/* ── the marks ──────────────────────────────────────────────────────────── */

.ann__mark {
  position: absolute;
  translate: -50% -50%;
  display: grid;
  place-items: center;
  width: 2rem;
  height: 2rem;
  border-radius: 50%;
  background: var(--aw-fill-progress);
  color: var(--aw-on-fill);
  border: 2px solid var(--aw-on-fill);
  box-shadow: var(--aw-shadow-sm);
  font-size: 0.9rem;
  font-weight: 700;
  line-height: 1;
  pointer-events: none;
  z-index: 3;
}

.ann__mark--alert {
  background: var(--aw-fill-alert);
}

/* ── the list ───────────────────────────────────────────────────────────── */

.ann__copy {
  display: grid;
  gap: 1.5rem;
  align-content: start;
  min-width: 0;
}

.ann__items {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 1.15rem;
}

.ann--grid .ann__items {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 20rem), 1fr));
  gap: 1rem 2.5rem;
}

.ann__items li {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.85rem;
  align-items: start;
}

.ann__n {
  display: grid;
  place-items: center;
  width: 2rem;
  height: 2rem;
  border-radius: 50%;
  background: var(--aw-fill-progress);
  color: var(--aw-on-fill);
  font-size: 0.9rem;
  font-weight: 700;
  line-height: 1;
}

.ann__n--plain {
  width: 2rem;
  height: 2rem;
  background: none;
}
.ann__n--plain::before {
  content: '';
  width: 0.55rem;
  height: 0.55rem;
  border-radius: 50%;
  background: var(--aw-primary-strong);
}

.ann__items p {
  margin: 0.2rem 0 0;
  color: var(--aw-text-dim);
  font-size: 0.99rem;
  line-height: 1.55;
}

.ann__items strong {
  color: var(--aw-text);
  font-weight: 680;
}

.ann__points {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 0.7rem;
}

.ann__points li {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.7rem;
  align-items: start;
  font-size: 0.95rem;
  color: var(--aw-text-dim);
}

.ann__points svg {
  color: var(--aw-success);
  margin-top: 2px;
}

.ann__note {
  margin: 0;
  padding-top: 1rem;
  border-top: 1px solid var(--aw-hairline);
  font-size: 0.92rem;
  color: var(--aw-text-dim);
}

/* ── narrow screens: one column, pictures first ─────────────────────────── */

@media (max-width: 900px) {
  .ann--split .ann__body,
  .ann--phones.ann--split .ann__body,
  .ann--flip .ann__body,
  .ann--phones.ann--flip .ann__body {
    grid-template-columns: 1fr;
  }
  .ann--flip .ann__shots {
    order: 0;
  }
  .ann--grid .ann__shots--n3 {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 560px) {
  .ann--side .ann__shots--n2,
  .ann--side .ann__shots--n3,
  .ann--grid .ann__shots--n2,
  .ann--grid .ann__shots--n3,
  .ann--pair .ann__body {
    grid-template-columns: 1fr;
  }
  .ann--side .ann__shots--n3 .ann__shot--lead.ann__shot--tall {
    grid-row: auto;
  }
  .ann__mark {
    width: 1.6rem;
    height: 1.6rem;
    font-size: 0.78rem;
  }
}
</style>
