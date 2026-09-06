<script setup>
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
import { features } from './content.js';

// The recurrence claim gets a table of its own (RecurrenceProof) rather than a
// screenshot, so its feature entry is pulled out of the alternating run.
const featureList = features.filter((f) => f.id !== 'recurrence');
</script>

<template>
  <a class="skip" href="#features">Skip to features</a>
  <TheHeader />

  <main>
    <HeroSection />
    <PillarGrid />

    <section id="features" class="aw-shell">
      <template v-for="(f, i) in featureList" :key="f.id">
        <FeatureSection :feature="f" :flip="i % 2 === 1" />
        <RecurrenceProof v-if="i === 1" />
      </template>
    </section>

    <MobileShowcase />
    <AiSection />
    <ApiSection />
    <ComparisonTable />
    <SelfHostSection />
    <DownloadSection />
    <FaqSection />
  </main>

  <TheFooter />
</template>
