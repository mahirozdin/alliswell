<script setup>
import { computed } from 'vue';

import ContactForm from './ContactForm.vue';
import EeHero from './EeHero.vue';
import ShotTabs from './ShotTabs.vue';
import StatStrip from './StatStrip.vue';
import StepTimeline from './StepTimeline.vue';
import { SECTIONS } from './page.js';
import { company } from '../company.js';
import ComparisonTable from '../components/ComparisonTable.vue';
import FaqSection from '../components/FaqSection.vue';
import FeatureSection from '../components/FeatureSection.vue';
import PillarGrid from '../components/PillarGrid.vue';
import SelfHostSection from '../components/SelfHostSection.vue';
import TheFooter from '../components/TheFooter.vue';
import TheHeader from '../components/TheHeader.vue';

/**
 * The enterprise page (EE-151, sections in EE-153).
 *
 * The chrome is the homepage's, taking props rather than reading `content.js`
 * (EE-143) — so a reader who follows a link from `/` to `/enterprise` sees one
 * website, and a change to the header happens once.
 *
 * The section list comes from `page.js`, which holds the ORDER and none of the
 * words: `check:copy` compares two content modules key for key, and it can only
 * do that if structure is not one of the things that can differ between them.
 * A row whose key is absent from the content simply does not render, so the
 * order can carry a section before its copy exists — and the copy gate still
 * refuses one that exists in a single language.
 */
const props = defineProps({
  content: { type: Object, required: true },
  /** `[{ lang, label, href }]`, the page's own entry included, per hreflang. */
  alternates: { type: Array, required: true },
  /** This page's path, so the language pill can mark itself. */
  current: { type: String, required: true },
});

const COMPONENTS = {
  EeHero,
  PillarGrid,
  StatStrip,
  StepTimeline,
  FeatureSection,
  ShotTabs,
  SelfHostSection,
  ComparisonTable,
  ContactForm,
  FaqSection,
};

/** Only the sections this language actually has copy for. */
const sections = computed(() => SECTIONS.filter((s) => props.content[s.key]));

/**
 * The zig-zag. `FeatureSection` takes `flip` from here rather than computing it
 * from its own index, so the rhythm survives a section being reordered — the
 * homepage learned that first. The feature rows are not adjacent (tabs sit
 * between them), so they alternate on their own running count.
 */
const flipped = computed(() => {
  const map = new Map();
  let n = 0;
  for (const s of sections.value) {
    if (s.component === 'FeatureSection') map.set(s.key, n++ % 2 === 1);
  }
  return map;
});

/** What each component wants, keyed by the component rather than the section. */
function propsFor(section) {
  const data = props.content[section.key];
  switch (section.component) {
    case 'EeHero':
      return { hero: data };
    case 'PillarGrid':
      return { items: data.items, eyebrow: data.eyebrow, title: data.title };
    case 'StatStrip':
      return { items: data.items, eyebrow: data.eyebrow, title: data.title };
    case 'StepTimeline':
      return {
        eyebrow: data.eyebrow,
        title: data.title,
        lede: data.lede,
        steps: data.steps,
        aside: data.aside,
      };
    case 'FeatureSection':
      return { feature: data, flip: flipped.value.get(section.key) === true };
    case 'ShotTabs':
      return { eyebrow: data.eyebrow, title: data.title, lede: data.lede, tabs: data.tabs };
    case 'SelfHostSection':
      return {
        block: data,
        terminalTitle: data.terminalTitle,
        copyLabel: data.copyLabel,
        copiedLabel: data.copiedLabel,
        anchor: section.anchor,
      };
    case 'ComparisonTable':
      return { table: data, anchor: section.anchor };
    case 'ContactForm':
      // company.js, not the content module: this is the legal contact route
      // and it must not fork per language. Importing it from content.en.js
      // also dragged the English copy into the shared chunk, so a Turkish
      // reader downloaded both languages.
      // `content.lang` and not a new prop: the page already knows which
      // language it is, and the acknowledgement the sender receives is decided
      // by the page they were reading (EE-158).
      return { contact: data, email: company.email, lang: props.content.lang };
    case 'FaqSection':
      return { heading: data.heading, items: data.items };
    default:
      return {};
  }
}

/**
 * Two components render their own `id` from an `anchor` prop, because the
 * homepage's `#self-host` and `#compare` belong to them. Everything else takes
 * the anchor as a plain attribute and lets it fall through to the root.
 *
 * The `id` is OMITTED rather than passed as undefined. `:id="undefined"` still
 * creates an entry in `$attrs`, and a fallthrough attribute overrides the
 * child's own binding — so the two components that set their own id lost it,
 * silently, and `#ops` and `#packages` were anchors that scrolled nowhere. An
 * absent property is not the same as a property whose value is absent.
 */
const OWN_ANCHOR = ['SelfHostSection', 'ComparisonTable'];

function bindingsFor(section) {
  const bound = propsFor(section);
  if (section.anchor && !OWN_ANCHOR.includes(section.component)) bound.id = section.anchor;
  return bound;
}
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
    <component
      :is="COMPONENTS[section.component]"
      v-for="section in sections"
      :key="section.key"
      v-bind="bindingsFor(section)"
    />
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
