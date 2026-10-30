<script setup>
import { computed } from 'vue';

import HomeIcon from './HomeIcon.vue';
import { useLoopVideo } from '../composables/useLoopVideo.js';
import { fallback, media, srcset } from '../media.js';

/**
 * One product loop: a poster picture with the muted video laid over it
 * (ADR-0061). The picture is the image a reader, a crawler and a reduced-motion
 * visitor get, and the largest paint in the hero; the video only fades in
 * once it is actually playing. The alt text describes what the loop shows.
 */
const props = defineProps({
  name: { type: String, required: true },
  alt: { type: String, required: true },
  eager: { type: Boolean, default: false },
  sizes: { type: String, default: '(min-width: 60rem) 56vw, 100vw' },
  labels: { type: Object, required: true },
});

const entry = computed(() => media(props.name));
const avif = computed(() => srcset(entry.value.poster.avif));
const jpg = computed(() => srcset(entry.value.poster.jpg));
const src = computed(() => fallback(entry.value.poster.jpg));
const emit = defineEmits(['paused']);
const { video, playing, paused, enabled, toggle: flip } = useLoopVideo(entry.value.mp4);
const toggle = () => {
  flip();
  emit('paused', paused.value);
};
</script>

<template>
  <figure class="loop" :class="{ 'is-playing': playing }" :data-media="name" data-kind="product">
    <picture>
      <source type="image/avif" :srcset="avif" :sizes="sizes" />
      <img
        :src="src"
        :srcset="jpg"
        :sizes="sizes"
        :width="entry.width"
        :height="entry.height"
        :alt="alt"
        :loading="eager ? 'eager' : 'lazy'"
        :fetchpriority="eager ? 'high' : 'auto'"
        decoding="async"
      />
    </picture>
    <video
      v-if="entry.mp4"
      ref="video"
      class="loop__video"
      :width="entry.width"
      :height="entry.height"
      muted
      loop
      playsinline
      preload="none"
      disablepictureinpicture
      aria-hidden="true"
      tabindex="-1"
    ></video>
    <button
      v-if="entry.mp4"
      class="loop__toggle"
      :class="{ 'is-ready': enabled }"
      type="button"
      :aria-label="paused ? labels.play : labels.pause"
      :aria-pressed="paused ? 'true' : 'false'"
      @click="toggle"
    >
      <HomeIcon :name="paused ? 'play' : 'pause'" :size="16" />
    </button>
  </figure>
</template>
