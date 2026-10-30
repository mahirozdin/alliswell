<script setup>
import { computed, ref } from 'vue';

import LoopVideo from './LoopVideo.vue';
import { fallback, media, srcset } from '../media.js';

/**
 * Dusk's hour: a real photograph of fog at sunset fills the hero, the head
 * sits dark on its palest part, and the product runs in smoked glass on the
 * darker side (Hallmark Dusk, Surfaces). The photograph is credited in the
 * footer; it is the largest paint, so it is eager and preloaded in the head.
 */
const props = defineProps({
  hero: { type: Object, required: true },
  ui: { type: Object, required: true },
});

const photo = computed(() => media('photo-fog'));
const also = computed(() => props.hero.also);
const separator = (i) => (i === also.value.links.length - 2 ? also.value.and : ', ');
// The loop's pause button also stills the photograph's drift: one control for
// everything that moves in the hero (WCAG 2.2.2).
const still = ref(false);
</script>

<template>
  <section id="top" class="hero" :class="{ 'is-still': still }">
    <div class="hero__photo" aria-hidden="true">
      <picture>
        <source type="image/avif" :srcset="srcset(photo.sources.avif)" sizes="100vw" />
        <img
          :src="fallback(photo.sources.jpg)"
          :srcset="srcset(photo.sources.jpg)"
          sizes="100vw"
          :width="photo.width"
          :height="photo.height"
          alt=""
          fetchpriority="high"
          decoding="async"
        />
      </picture>
    </div>
    <div class="hero__scrim" aria-hidden="true"></div>
    <div class="container hero__grid">
      <div class="hero__text">
        <h1>{{ hero.title }}</h1>
        <p class="lead hero__sentence">{{ hero.sentence }}</p>
        <div class="hero__actions">
          <a class="btn" :href="hero.primary.href">{{ hero.primary.label }}</a>
          <a class="btn btn--ghost" :href="hero.secondary.href">{{ hero.secondary.label }}</a>
        </div>
        <p class="hero__also">
          {{ also.before
          }}<template v-for="(link, i) in also.links" :key="link.href"
            ><a :href="link.href">{{ link.label }}</a
            ><template v-if="i < also.links.length - 1">{{ separator(i) }}</template></template
          >{{ also.after }}
        </p>
      </div>
      <figure class="glass hero__pane">
        <LoopVideo
          :name="hero.media"
          :alt="hero.alt"
          :labels="ui"
          eager
          sizes="(min-width: 60rem) 52vw, 100vw"
          @paused="still = $event"
        />
        <figcaption>{{ hero.caption }}</figcaption>
      </figure>
    </div>
  </section>
</template>
