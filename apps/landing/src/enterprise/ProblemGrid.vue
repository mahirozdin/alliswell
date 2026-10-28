<script setup>
import AwIcon from './AwIcon.vue';
import LatinWords from '../components/LatinWords.vue';

/**
 * "This is how requests travel in most factories today" (OPH-388, deck slide 2).
 *
 * The page used to open on a feature list. The deck opens on the reader's own
 * Monday morning — the phone call nobody wrote down, the job two people did and
 * the job nobody did — and only then on the product. Five small cards, each one
 * icon, one title and one sentence, and a dark band under them that says what
 * all five add up to.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  /** `[{ icon, title, body }]` — `icon` is a key of icons.js. */
  items: { type: Array, required: true },
  /** `{ label, body }` — the dark band. */
  conclusion: { type: Object, default: null },
});

/**
 * A card is narrow, and a line may break at a hyphen: "Şikâyet e-" / "postada
 * kalıyor". The title keeps its ASCII hyphen in content (the copy gate reads
 * it); only what is drawn takes the non-breaking one (U+2011).
 */
const unbroken = (t) => t.replace(/(\S)-(\S)/g, '$1\u2011$2');
</script>

<template>
  <section v-reveal class="aw-section problem">
    <div class="aw-shell">
      <header class="problem__head">
        <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <ul class="problem__grid">
        <li v-for="it in items" :key="it.title" class="aw-card problem__card">
          <span class="problem__icon"><AwIcon :name="it.icon" :size="26" /></span>
          <h3>{{ unbroken(it.title) }}</h3>
          <p>{{ it.body }}</p>
        </li>
      </ul>

      <p v-if="conclusion" class="problem__band">
        <strong>{{ conclusion.label }}</strong>
        {{ conclusion.body }}
      </p>
    </div>
  </section>
</template>

<style scoped>
.problem {
  padding-block: clamp(3rem, 7vw, 5.5rem);
}

.problem__head {
  max-width: 50rem;
  margin-bottom: 2rem;
}

.problem__grid {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 12.5rem), 1fr));
  gap: 1rem;
}

.problem__card {
  padding: 1.4rem 1.3rem;
}

.problem__icon {
  display: grid;
  place-items: center;
  width: 3.25rem;
  height: 3.25rem;
  margin-bottom: 1.1rem;
  border-radius: 50%;
  background: color-mix(in srgb, var(--aw-primary) 13%, var(--aw-surface));
  color: var(--aw-primary-strong);
}

.problem__card h3 {
  font-size: 1.08rem;
  margin-bottom: 0.45rem;
}

.problem__card p {
  margin: 0;
  font-size: 0.95rem;
  color: var(--aw-text-dim);
}

.problem__band {
  margin: 1.5rem 0 0;
  padding: clamp(1.25rem, 3vw, 1.75rem) clamp(1.25rem, 3vw, 2.25rem);
  border-radius: var(--aw-radius);
  background: var(--aw-band-bg);
  border: 1px solid var(--aw-hairline);
  color: var(--aw-band-dim);
  font-size: clamp(1.02rem, 1.4vw, 1.15rem);
  line-height: 1.55;
}

.problem__band strong {
  color: var(--aw-band-text);
}
</style>
