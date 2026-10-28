<script setup>
import AwIcon from './AwIcon.vue';
import LatinWords from '../components/LatinWords.vue';

/**
 * A request's road from opened to closed, in six steps (OPH-388, deck slide 3).
 *
 * The deck's definition of the product is not a sentence about features but
 * this row: opened → reaches the right unit → the clock starts → someone is
 * assigned → solved → the requester confirms. The rest of the page shows the
 * steps one by one, so the footnote says where each is shown.
 *
 * An ordered list, because the order IS the content. Six across with arrows on
 * a wide screen, one column with downward arrows on a phone; in between, where
 * a row would wrap and an arrow would point at the wrong card, the arrows go
 * and the numbers carry the order alone.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  /** `[{ n, icon, title, body }]` */
  steps: { type: Array, required: true },
  footnote: { type: String, default: '' },
});
</script>

<template>
  <section v-reveal class="aw-section journey">
    <div class="aw-shell">
      <header class="journey__head">
        <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <ol class="journey__steps">
        <li v-for="(s, i) in steps" :key="s.n" :value="s.n" class="aw-card journey__step">
          <span v-if="i > 0" class="journey__arrow" aria-hidden="true">
            <AwIcon name="arrow-right" :size="18" />
          </span>
          <div class="journey__top">
            <span class="journey__icon"><AwIcon :name="s.icon" :size="24" /></span>
            <span class="journey__n" aria-hidden="true">{{ s.n }}</span>
          </div>
          <h3>{{ s.title }}</h3>
          <p>{{ s.body }}</p>
        </li>
      </ol>

      <p v-if="footnote" class="journey__foot">{{ footnote }}</p>
    </div>
  </section>
</template>

<style scoped>
.journey {
  padding-block: clamp(3rem, 7vw, 5.5rem);
  --_gap: 1.5rem;
}

.journey__head {
  max-width: 54rem;
  margin-bottom: 2rem;
}

.journey__steps {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: var(--_gap);
}

.journey__step {
  position: relative;
  padding: 1.25rem 1.15rem 1.35rem;
}

.journey__top {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 1rem;
}

.journey__icon {
  display: grid;
  place-items: center;
  width: 3.1rem;
  height: 3.1rem;
  border-radius: 50%;
  background: var(--aw-primary);
  color: var(--aw-surface);
}

/* The big step number is not what assistive technology announces (the list's
   own numbering is), but it is visible content: an opaque token, so it keeps
   I-11's 3:1 for large text in both themes (it was a 45% mix, 2.1–2.7:1). */
.journey__n {
  font-size: 1.7rem;
  font-weight: 700;
  line-height: 1;
  color: var(--aw-text-dim);
}

.journey__step h3 {
  font-size: 1.05rem;
  margin-bottom: 0.45rem;
}

.journey__step p {
  margin: 0;
  font-size: 0.93rem;
  line-height: 1.5;
  color: var(--aw-text-dim);
}

.journey__arrow {
  display: none;
  position: absolute;
  color: var(--aw-primary-strong);
}

.journey__foot {
  margin: 1.75rem 0 0;
  font-style: italic;
  color: var(--aw-text-dim);
  max-width: 70ch;
}

/* Six across: one row, arrows between the cards. */
@media (min-width: 1100px) {
  .journey__steps {
    grid-template-columns: repeat(6, minmax(0, 1fr));
  }
  .journey__arrow {
    display: block;
    top: 50%;
    left: calc(var(--_gap) / -2);
    translate: -50% -50%;
  }
}

/* One column: arrows point down. */
@media (max-width: 640px) {
  .journey__steps {
    grid-template-columns: 1fr;
  }
  .journey__arrow {
    display: block;
    top: calc(var(--_gap) / -2);
    left: 50%;
    translate: -50% -50%;
    rotate: 90deg;
  }
}
</style>
