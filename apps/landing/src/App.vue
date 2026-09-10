<script setup>
import { computed } from 'vue';

import AiSection from './components/AiSection.vue';
import ApiSection from './components/ApiSection.vue';
import ComparisonTable from './components/ComparisonTable.vue';
import DownloadSection from './components/DownloadSection.vue';
import FaqSection from './components/FaqSection.vue';
import FeatureSection from './components/FeatureSection.vue';
import HeroSection from './components/HeroSection.vue';
import MobileShowcase from './components/MobileShowcase.vue';
import PillarGrid from './components/PillarGrid.vue';
import RecurrenceProof from './components/RecurrenceProof.vue';
import SelfHostSection from './components/SelfHostSection.vue';
import TheFooter from './components/TheFooter.vue';
import TheHeader from './components/TheHeader.vue';
import home from './content.js';

/**
 * The homepage (EE-164: in two languages).
 *
 * Every section takes its words from `content`, which is the English module's
 * default export or the Turkish one's — the same shape, compared key for key
 * by `check:copy`. The chrome (header, footer, language switch) is the one the
 * enterprise page uses, with the same props, so the two pages stay one site.
 */
const props = defineProps({
  content: { type: Object, default: () => home },
  /** `[{ lang, label, href }]`, the page's own entry included, per hreflang. */
  alternates: { type: Array, default: () => [] },
  /** This page's path, so the language pill can mark itself. */
  current: { type: String, default: '/' },
});

// The recurrence claim gets a table of its own (RecurrenceProof) rather than a
// screenshot, so its feature entry is pulled out of the alternating run.
const featureList = computed(() => props.content.features.filter((f) => f.id !== 'recurrence'));
</script>

<template>
  <a class="skip" href="#features">{{ content.skip }}</a>
  <TheHeader
    :home="content.nav.home"
    :links="content.nav.links"
    :cta="content.nav.cta"
    :stars-label="content.nav.starsLabel"
    :alternates="alternates"
    :current="current"
  />

  <main>
    <HeroSection :hero="content.hero" :platforms="content.platforms" />
    <PillarGrid :items="content.pillars" />

    <section id="features" class="aw-shell">
      <template v-for="(f, i) in featureList" :key="f.id">
        <FeatureSection :feature="f" :flip="i % 2 === 1" />
        <RecurrenceProof v-if="i === 1" :recurrence="content.recurrence" />
      </template>
    </section>

    <MobileShowcase :mobile="content.mobile" />
    <AiSection :ai="content.ai" />
    <ApiSection :api="content.api" />
    <ComparisonTable :table="content.comparison" />
    <SelfHostSection
      :block="content.selfHost"
      :terminal-title="content.selfHost.terminalTitle"
      :copy-label="content.selfHost.copyLabel"
      :copied-label="content.selfHost.copiedLabel"
    />
    <DownloadSection :download="content.download" :self-host-link="content.selfHost.link" />
    <FaqSection :heading="content.faq.heading" :items="content.faq.items" />
  </main>

  <TheFooter
    :home="content.nav.home"
    :columns="content.footer.columns"
    :blurb="content.footer.blurb"
    :notes="content.footer.notes"
    :privacy-label="content.footer.privacyLabel"
    :support-label="content.footer.supportLabel"
    :privacy-href="content.lang === 'tr' ? '/privacy/tr' : '/privacy'"
    :support-href="content.lang === 'tr' ? '/support/tr' : '/support'"
    :stars-word="content.footer.starsWord"
    :forks-word="content.footer.forksWord"
    :alternates="alternates"
    :current="current"
  />
</template>
