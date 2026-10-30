<script setup>
import { computed } from 'vue';

import { fallback, media } from '../media.js';

/**
 * The one-minute film, in the page's language (ADR-0061). Native controls, so
 * it plays with scripting off; never autoplays, because it has sound. The
 * captions track and the transcript carry what the on-screen text says to a
 * reader who cannot see it.
 */
const props = defineProps({ film: { type: Object, required: true }, lang: { type: String, required: true } });
const entry = computed(() => media(props.film.media));
</script>

<template>
  <section id="film" class="section film">
    <div class="container">
      <div class="head">
        <h2>{{ film.title }}</h2>
      </div>
      <div class="film__frame">
        <video
          class="film__video"
          controls
          playsinline
          preload="none"
          :poster="fallback(entry.poster.jpg)"
          :width="entry.width"
          :height="entry.height"
          :aria-label="film.alt"
        >
          <source :src="entry.mp4" type="video/mp4" />
          <track kind="captions" :src="entry.captions" :srclang="lang" :label="lang === 'tr' ? 'Türkçe' : 'English'" default />
        </video>
      </div>
      <details class="film__transcript">
        <summary>{{ film.transcriptLabel }}</summary>
        <ol>
          <li v-for="line in film.transcript" :key="line">{{ line }}</li>
        </ol>
      </details>
    </div>
  </section>
</template>
