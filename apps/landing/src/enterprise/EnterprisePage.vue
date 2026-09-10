<script setup>
import { computed } from 'vue';

import ContactForm from './ContactForm.vue';
import DeployOptions from './DeployOptions.vue';
import EeHero from './EeHero.vue';
import ShotTabs from './ShotTabs.vue';
import StepTimeline from './StepTimeline.vue';
import { SECTIONS, TWO_COLUMN_COMPONENTS } from './page.js';
import { company } from '../company.js';
import ComparisonTable from '../components/ComparisonTable.vue';
import FaqSection from '../components/FaqSection.vue';
import FeatureSection from '../components/FeatureSection.vue';
import PillarGrid from '../components/PillarGrid.vue';
import TheFooter from '../components/TheFooter.vue';
import TheHeader from '../components/TheHeader.vue';

/**
 * The enterprise page (EE-151, sections in EE-153, rebuilt in EE-164).
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
  StepTimeline,
  FeatureSection,
  ShotTabs,
  DeployOptions,
  ComparisonTable,
  ContactForm,
  FaqSection,
};

/** Only the sections this language actually has copy for. */
const sections = computed(() => SECTIONS.filter((s) => props.content[s.key]));

/**
 * The zig-zag. Every two-column section takes `flip` from here rather than
 * computing it from its own index, so the rhythm survives a section being
 * reordered — the homepage learned that first. Feature rows and tab blocks
 * share one running count (page.js says why).
 */
const flipped = computed(() => {
  const map = new Map();
  let n = 0;
  for (const s of sections.value) {
    if (TWO_COLUMN_COMPONENTS.includes(s.component)) map.set(s.key, n++ % 2 === 1);
  }
  return map;
});

/** What each component wants, keyed by the component rather than the section. */
function propsFor(section) {
  const data = props.content[section.key];
  const flip = flipped.value.get(section.key) === true;
  switch (section.component) {
    case 'EeHero':
      return { hero: data };
    case 'PillarGrid':
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
      // `shell`: the homepage wraps its feature run in one `.aw-shell`; this
      // page renders each row straight into <main>, and without its own shell
      // the copy sat on the viewport's left edge and the picture on its right
      // (EE-164, the "text glued to the left" report).
      return { feature: data, flip, shell: true };
    case 'ShotTabs':
      return { eyebrow: data.eyebrow, title: data.title, lede: data.lede, tabs: data.tabs, flip };
    case 'DeployOptions':
      return {
        eyebrow: data.eyebrow,
        title: data.title,
        lede: data.lede,
        options: data.options,
        footnote: data.footnote,
        anchor: section.anchor,
      };
    case 'ComparisonTable':
      // No highlighted column: on the homepage the first column is "us", here
      // the first column is merely the smallest package.
      return { table: data, anchor: section.anchor, highlight: -1 };
    case 'ContactForm':
      // company.js, not the content module: this is the legal contact route
      // and it must not fork per language. `content.lang` and not a new prop:
      // the acknowledgement the sender receives is decided by the page they
      // were reading (EE-158).
      return { contact: data, email: company.email, lang: props.content.lang };
    case 'FaqSection':
      return { heading: data.heading, items: data.items };
    default:
      return {};
  }
}

/**
 * Three components render their own `id` from an `anchor` prop, because the
 * homepage's `#compare` and `#self-host` belong to them. Everything else takes
 * the anchor as a plain attribute and lets it fall through to the root.
 *
 * The `id` is OMITTED rather than passed as undefined. `:id="undefined"` still
 * creates an entry in `$attrs`, and a fallthrough attribute overrides the
 * child's own binding — so the components that set their own id lost it,
 * silently, and their anchors scrolled nowhere. An absent property is not the
 * same as a property whose value is absent.
 */
const OWN_ANCHOR = ['ComparisonTable', 'DeployOptions'];

function bindingsFor(section) {
  const bound = propsFor(section);
  if (section.anchor && !OWN_ANCHOR.includes(section.component)) bound.id = section.anchor;
  return bound;
}
</script>

<template>
  <a class="skip" :href="content.nav.cta.href">{{ content.nav.cta.label }}</a>

  <!-- No GitHub star count on a sales page: the buyer this page is written
       for is not choosing a repository, and the free edition's column in the
       footer still says where the source is. -->
  <TheHeader
    :home="content.nav.home"
    :links="content.nav.links"
    :cta="content.nav.cta"
    :stars-label="content.nav.starsLabel"
    :show-stars="false"
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
