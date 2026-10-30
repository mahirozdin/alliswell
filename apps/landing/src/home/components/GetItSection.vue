<script setup>
import { computed } from 'vue';

import HomeIcon from './HomeIcon.vue';
import { PLATFORM_ICON } from '../icons.js';
import { fallback, media, srcset } from '../media.js';

/**
 * The close (Hallmark anatomy, "try"): every way to get it, beside one last
 * screen. The phone capture sits in Dusk's bone well, the page's one light
 * surface.
 */
const props = defineProps({ get: { type: Object, required: true } });
const phone = computed(() => media(props.get.media));
</script>

<template>
  <section id="get" class="section get">
    <div class="container split split--close">
      <div class="split__text">
        <div class="head">
          <h2>{{ get.title }}</h2>
          <p class="lead">{{ get.lead }}</p>
        </div>
        <ul class="platforms">
          <li v-for="row in get.rows" :key="row.id" class="platform">
            <HomeIcon :name="PLATFORM_ICON[row.id]" :size="24" />
            <span class="platform__name">{{ row.name }}</span>
            <span class="platform__note">{{ row.note }}</span>
            <a class="btn btn--ghost btn--sm" :href="row.href">{{ row.cta }}</a>
          </li>
        </ul>
      </div>
      <figure class="get__figure">
        <div class="well get__well">
        <picture>
          <source type="image/avif" :srcset="srcset(phone.poster.avif)" sizes="(min-width: 60rem) 22rem, 70vw" />
          <img
            :src="fallback(phone.poster.jpg)"
            :srcset="srcset(phone.poster.jpg)"
            sizes="(min-width: 60rem) 22rem, 70vw"
            :width="phone.width"
            :height="phone.height"
            :alt="get.alt"
            loading="lazy"
            decoding="async"
          />
        </picture>
        </div>
        <figcaption>
          <span class="get__cap">{{ get.caption }}</span>
          <span class="get__note">{{ get.captionNote }}</span>
        </figcaption>
      </figure>
    </div>
  </section>
</template>
