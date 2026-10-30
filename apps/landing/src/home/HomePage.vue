<script setup>
import { playable } from './media.js';
import AssistantSection from './components/AssistantSection.vue';
import CompareSection from './components/CompareSection.vue';
import FilmSection from './components/FilmSection.vue';
import GetItSection from './components/GetItSection.vue';
import HeroDusk from './components/HeroDusk.vue';
import HomeFaq from './components/HomeFaq.vue';
import HomeFooter from './components/HomeFooter.vue';
import HomeHeader from './components/HomeHeader.vue';
import OwnItSection from './components/OwnItSection.vue';
import TourTabs from './components/TourTabs.vue';

/**
 * The homepage (ADR-0061): Hallmark's Dusk theme, rendered on the server and
 * hydrated. The order is the argument: what it is and the product running,
 * the five things, the film, the assistant, owning it, how it compares,
 * where to get it, the questions.
 */
defineProps({
  content: { type: Object, required: true },
  alternates: { type: Array, required: true },
});
</script>

<template>
  <a class="skip" href="#features">{{ content.skip }}</a>
  <HomeHeader :nav="content.nav" :alternates="alternates" :lang="content.lang" />
  <main>
    <HeroDusk :hero="content.hero" :ui="content.ui" />
    <TourTabs :tour="content.tour" :ui="content.ui" />
    <FilmSection v-if="playable(content.film.media)" :film="content.film" :lang="content.lang" />
    <AssistantSection :assistant="content.assistant" :ui="content.ui" />
    <OwnItSection :own="content.own" :ui="content.ui" />
    <CompareSection :compare="content.compare" />
    <GetItSection :get="content.get" />
    <HomeFaq :faq="content.faq" />
  </main>
  <HomeFooter :footer="content.footer" />
</template>
