<script setup>
import AwIcon from './AwIcon.vue';
import ScreenshotFrame from '../components/ScreenshotFrame.vue';
import LatinWords from '../components/LatinWords.vue';

/**
 * The ways a request reaches you from outside (OPH-388, deck slide 15).
 *
 * Four channels — a request form, e-mail, the company portal, the phone — as
 * four cards, and beside them the one screen an outsider actually sees: the
 * form. The page used to explain the form in five numbered steps with a
 * paragraph on spam protection; the buyer's question is only "how do they
 * reach us", and the protection is one line under the cards.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  /** `[{ icon, title, body }]` */
  channels: { type: Array, required: true },
  /** `{ shot, shotDark?, alt, caption?, ratio? }` */
  shot: { type: Object, default: null },
  note: { type: String, default: '' },
});
</script>

<template>
  <section v-reveal class="aw-section ch">
    <div class="aw-shell">
      <header class="ch__head">
        <p v-if="eyebrow" class="aw-eyebrow"><LatinWords :text="eyebrow" /></p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <div class="ch__body" :class="{ 'ch__body--split': !!shot }">
        <div class="ch__copy">
          <ul class="ch__list">
            <li v-for="c in channels" :key="c.title" class="aw-card ch__card">
              <span class="ch__icon"><AwIcon :name="c.icon" :size="26" /></span>
              <div>
                <h3>{{ c.title }}</h3>
                <p>{{ c.body }}</p>
              </div>
            </li>
          </ul>
          <p v-if="note" class="ch__note">{{ note }}</p>
        </div>

        <figure v-if="shot" class="ch__shot">
          <ScreenshotFrame
            :src="shot.shot"
            :src-dark="shot.shotDark || ''"
            :alt="shot.alt"
            variant="card"
            :ratio="shot.ratio || ''"
          />
          <figcaption v-if="shot.caption">{{ shot.caption }}</figcaption>
        </figure>
      </div>
    </div>
  </section>
</template>

<style scoped>
.ch {
  padding-block: clamp(3rem, 7vw, 5.5rem);
}

.ch__head {
  max-width: 50rem;
  margin-bottom: 2rem;
}

.ch__body {
  display: grid;
  gap: clamp(1.75rem, 4vw, 3rem);
}

.ch__body--split {
  grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
  align-items: start;
}

.ch__list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 0.85rem;
}

.ch__card {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 1.1rem;
  align-items: center;
  padding: 1.1rem 1.3rem;
}

.ch__icon {
  display: grid;
  place-items: center;
  width: 3.25rem;
  height: 3.25rem;
  border-radius: 50%;
  background: color-mix(in srgb, var(--aw-primary) 13%, var(--aw-surface));
  color: var(--aw-primary-strong);
}

.ch__card h3 {
  font-size: 1.08rem;
  margin-bottom: 0.2rem;
}

.ch__card p {
  margin: 0;
  font-size: 0.95rem;
  color: var(--aw-text-dim);
}

.ch__note {
  margin: 1.1rem 0 0;
  font-size: 0.92rem;
  color: var(--aw-text-dim);
}

.ch__shot {
  margin: 0;
  display: grid;
  gap: 0.85rem;
  justify-items: center;
}

.ch__shot :deep(.frame) {
  width: 100%;
}

.ch__shot figcaption {
  font-weight: 650;
  color: var(--aw-secondary);
}

@media (max-width: 900px) {
  .ch__body--split {
    grid-template-columns: 1fr;
  }
}
</style>
