<script setup>
import AwIcon from './AwIcon.vue';
import ScreenshotFrame from '../components/ScreenshotFrame.vue';
import LatinWords from '../components/LatinWords.vue';

/**
 * The sales deck, as a file (OPH-388).
 *
 * The page and the deck tell the same story; the deck is what a reader
 * forwards to the colleague who signs. So it is offered as a real download —
 * an `<a download>` to a dated file under `/downloads/`, never a viewer or a
 * script — with its first page as the picture, so the reader knows what they
 * will get before they get it. `check-copy.mjs` refuses an href whose file is
 * not in `public/downloads/`.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  /** `{ shot, alt }` — the PDF's first page. */
  cover: { type: Object, required: true },
  /** `{ href, label, meta }` — `meta` is e.g. "PDF · 18 pages · 3.5 MB". */
  pdf: { type: Object, required: true },
  /** `{ label, href }` — optional quieter link beside the button. */
  secondary: { type: Object, default: null },
});
</script>

<template>
  <section v-reveal class="aw-section deck">
    <div class="aw-shell">
      <div class="aw-card deck__card">
        <ScreenshotFrame
          class="deck__cover"
          :src="cover.shot"
          :alt="cover.alt"
          variant="card"
          ratio="16 / 9"
        />
        <div class="deck__copy">
          <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
          <h2>{{ title }}</h2>
          <p v-if="lede" class="deck__lede">{{ lede }}</p>
          <div class="deck__actions">
            <a class="aw-btn" :href="pdf.href" download type="application/pdf">
              <AwIcon name="download" :size="20" />
              {{ pdf.label }}
            </a>
            <a v-if="secondary" class="deck__secondary" :href="secondary.href">{{
              secondary.label
            }}</a>
          </div>
          <p v-if="pdf.meta" class="deck__meta">
            <AwIcon name="file-text" :size="16" />
            {{ pdf.meta }}
          </p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.deck {
  padding-block: clamp(3rem, 6vw, 5rem);
}

.deck__card {
  display: grid;
  grid-template-columns: minmax(0, 5fr) minmax(0, 6fr);
  gap: clamp(1.5rem, 4vw, 3rem);
  align-items: center;
  padding: clamp(1.25rem, 3vw, 2.25rem);
}

.deck__copy h2 {
  font-size: clamp(1.6rem, 3vw, 2.2rem);
  margin-bottom: 0.6rem;
}

.deck__lede {
  color: var(--aw-text-dim);
  max-width: 52ch;
}

.deck__actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem 1.25rem;
  margin-top: 1.25rem;
}

/* A text link still gets a 44 px target (I-11). */
.deck__secondary {
  display: inline-flex;
  align-items: center;
  min-height: 44px;
  font-weight: 600;
}

.deck__meta {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  margin: 0.9rem 0 0;
  font-size: 0.9rem;
  color: var(--aw-text-dim);
}

@media (max-width: 760px) {
  .deck__card {
    grid-template-columns: 1fr;
  }
}
</style>
