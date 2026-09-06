<script setup>
import EeHero from './EeHero.vue';
import TheFooter from '../components/TheFooter.vue';
import TheHeader from '../components/TheHeader.vue';

/**
 * The enterprise page's shell (EE-151).
 *
 * The chrome is the homepage's, taking props rather than reading `content.js`
 * (EE-143) — so a reader who follows a link from `/` to `/enterprise` sees one
 * website, and a change to the header happens once.
 *
 * Sections arrive in EE-153; this commit exists to move the ROUTE, and moving
 * a route is the part that cannot be done in halves: the moment `/enterprise`
 * leaves `STATIC_PAGES`, the gate that asks whether pages are indexable stops
 * covering it and keeps passing.
 */
defineProps({
  content: { type: Object, required: true },
  /** `[{ lang, label, href }]`, the page's own entry included, per hreflang. */
  alternates: { type: Array, required: true },
  /** This page's path, so the language pill can mark itself. */
  current: { type: String, required: true },
});
</script>

<template>
  <a class="skip" :href="content.nav.cta.href">{{ content.nav.cta.label }}</a>

  <TheHeader
    :home="content.nav.home"
    :links="content.nav.links"
    :cta="content.nav.cta"
    :stars-label="content.nav.starsLabel"
    :alternates="alternates"
    :current="current"
  />

  <main>
    <EeHero :hero="content.hero" />
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
    :alternates="alternates"
    :current="current"
    :show-version="false"
  />
</template>
