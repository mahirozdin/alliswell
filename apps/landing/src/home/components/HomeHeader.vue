<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';

import HomeIcon from './HomeIcon.vue';
import { usePlatform } from '../composables/usePlatform.js';
import { primaryFor } from '../platform.js';
import { BUILD_PROOF, starsLabel } from '../proof.js';

/**
 * The bar: wordmark, four places on this page, the enterprise page, the
 * language pair, the source on GitHub and one action (Hallmark: a three-part
 * bar, earned by five real destinations). The action is the hero's, chosen
 * by the device; the GitHub button shows its stars only past a hundred
 * (OPH-412, landing-audit K2 and K6). It sits over the hero photograph in dark ink and turns
 * to slate glass once the photograph has scrolled away. Without scripting it
 * simply stays at the top of the page, over the photograph it was drawn for.
 */
const props = defineProps({
  nav: { type: Object, required: true },
  alternates: { type: Array, required: true },
  lang: { type: String, required: true },
});

const scrolled = ref(false);
const menu = ref(null);
const onScroll = () => (scrolled.value = window.scrollY > 24);
const closeMenu = () => menu.value?.removeAttribute('open');
const onKey = (e) => e.key === 'Escape' && closeMenu();

onMounted(() => {
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });
  document.addEventListener('keydown', onKey);
});
onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScroll);
  document.removeEventListener('keydown', onKey);
});

const platform = usePlatform();
const cta = computed(() => primaryFor(props.nav.cta, platform.value));
const stars = starsLabel(BUILD_PROOF, props.lang);

const homeHref = (alt) => alt.href;
const isCurrent = (alt) => alt.lang === props.lang;
</script>

<template>
  <header class="bar" :class="{ 'is-scrolled': scrolled }">
    <div class="container bar__inner">
      <a class="bar__brand" :href="nav.home">
        <img src="/logo.svg" width="32" height="32" alt="" />
        <span>AllisWell</span>
      </a>
      <nav class="bar__nav" :aria-label="nav.label">
        <a v-for="link in nav.links" :key="link.href" :href="link.href">{{ link.label }}</a>
      </nav>
      <div class="bar__end">
        <nav class="bar__lang" :aria-label="nav.langLabel">
          <a
            v-for="alt in alternates"
            :key="alt.lang"
            :href="homeHref(alt)"
            :hreflang="alt.lang"
            :lang="alt.lang"
            :data-aw-lang="alt.lang"
            :aria-current="isCurrent(alt) ? 'page' : null"
            >{{ alt.label }}</a
          >
        </nav>
        <a class="btn btn--ghost btn--sm bar__gh" :href="nav.github.href" data-cta="nav-github">
          <HomeIcon name="github" :size="18" />
          <span class="bar__gh-label">{{ nav.github.label }}</span>
          <span v-if="stars" class="bar__gh-label bar__gh-stars"><HomeIcon name="star" :size="14" />{{ stars }}</span>
        </a>
        <a class="btn btn--sm" :href="cta.href" data-cta="nav-primary">{{ cta.label }}</a>
        <details ref="menu" class="bar__menu">
          <summary :aria-label="nav.menu"><HomeIcon name="menu" /></summary>
          <div class="bar__sheet">
            <a v-for="link in nav.links" :key="link.href" :href="link.href" @click="closeMenu">{{ link.label }}</a>
            <a :href="nav.github.href" @click="closeMenu">{{ nav.github.label }}</a>
          </div>
        </details>
      </div>
    </div>
  </header>
</template>
