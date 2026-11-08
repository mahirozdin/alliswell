<script setup>
import { computed, ref } from 'vue';

import LoopVideo from './LoopVideo.vue';
import { usePlatform } from '../composables/usePlatform.js';
import { fallback, media, srcset } from '../media.js';
import { primaryFor } from '../platform.js';
import { BUILD_PROOF, proofParts } from '../proof.js';

/**
 * Dusk's hour: a real photograph of fog at sunset fills the hero, the head
 * sits dark on its palest part, and the product runs in smoked glass on the
 * darker side (Hallmark Dusk, Surfaces). The photograph is credited in the
 * footer; it is the largest paint, so it is eager and preloaded in the head.
 */
const props = defineProps({
  hero: { type: Object, required: true },
  proof: { type: Object, required: true },
  lang: { type: String, required: true },
  ui: { type: Object, required: true },
});

// OPH-412: the store on a phone, the browser elsewhere (landing-audit K6), and
// the proof line the build counted (K2).
const platform = usePlatform();
const primary = computed(() => primaryFor(props.hero.primary, platform.value));
const proofLine = computed(() => proofParts(props.proof, BUILD_PROOF, props.lang));

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
          <a class="btn" :href="primary.href" data-cta="hero-primary">{{ primary.label }}</a>
          <a class="btn btn--ghost" :href="hero.secondary.href">{{ hero.secondary.label }}</a>
        </div>
        <p class="hero__also">
          {{ also.before
          }}<template v-for="(link, i) in also.links" :key="link.href"
            ><a :href="link.href">{{ link.label }}</a
            ><template v-if="i < also.links.length - 1">{{ separator(i) }}</template></template
          >{{ also.after }}
        </p>
        <ul class="hero__proof" :aria-label="proof.label" data-proof>
          <li v-for="(part, i) in proofLine" :key="i">
            <a v-if="i === 0" :href="proof.source.href">{{ part }}</a>
            <template v-else>{{ part }}</template>
          </li>
        </ul>
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
