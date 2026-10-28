<script setup>
import { computed } from 'vue';

/**
 * Text whose product and brand names are marked `lang="en"`.
 *
 * Eyebrows, table heads and footer headings are upper-cased in CSS, and CSS
 * upper-cases with the element's language: under `lang="tr"` a Latin "i"
 * becomes "İ", so "AllisWell Enterprise" read "ALLİSWELL ENTERPRİSE". The
 * Turkish words around the names must stay Turkish ("nedir?" → "NEDİR?"), so
 * only the names get the English language tag. The text itself is unchanged.
 */
const props = defineProps({
  text: { type: String, default: '' },
});

const NAMES = /(AllisWell(?: Enterprise)?|Enterprise|Business|Starter|Active Directory)/;

const parts = computed(() =>
  props.text
    .split(NAMES)
    .filter(Boolean)
    .map((t) => ({ t, en: NAMES.test(t) && t.match(NAMES)[0] === t })),
);
</script>

<template>
  <template v-for="(p, i) in parts" :key="i"
    ><span v-if="p.en" lang="en">{{ p.t }}</span
    ><template v-else>{{ p.t }}</template></template
  >
</template>
