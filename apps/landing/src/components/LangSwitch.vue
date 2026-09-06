<script setup>
/**
 * The two-language pill pair (EE-143).
 *
 * The generated document pages have had one since the legal pages shipped —
 * `.doc__langs` in legal.css. The Vue site has never needed one because it has
 * only ever spoken English. The enterprise page changes that, and the switch
 * has to look like the one the rest of the site already uses, or a reader who
 * follows a link from /privacy to /enterprise sees two different websites.
 *
 * The styling is repeated here rather than shared because legal.css is a
 * stylesheet the Vue bundle deliberately does not load: it carries a whole
 * document skin, and importing it to get twenty lines would bring the other two
 * hundred with it.
 *
 * Rendering nothing for a single alternate is deliberate. A switcher offering
 * one language is a control that cannot be used, and it makes a page look
 * translated when it is not.
 */
defineProps({
  /** `[{ lang, label, href }]` — the page's own entry included, per hreflang. */
  alternates: { type: Array, default: () => [] },
  /** The current page's path, so its own pill can be marked. */
  current: { type: String, default: '' },
});
</script>

<template>
  <nav v-if="alternates.length > 1" class="langs" aria-label="Language">
    <a
      v-for="a in alternates"
      :key="a.href"
      :href="a.href"
      :hreflang="a.lang"
      :aria-current="a.href === current ? 'page' : null"
      >{{ a.label }}</a
    >
  </nav>
</template>

<style scoped>
.langs {
  display: flex;
  gap: 0.35rem;
}

.langs a {
  display: inline-flex;
  align-items: center;
  height: 40px;
  padding: 0 0.8rem;
  border-radius: 999px;
  border: 1px solid var(--aw-hairline);
  font-size: 0.85rem;
  font-weight: 600;
  text-decoration: none;
  color: var(--aw-text-dim);
}

.langs a:hover {
  background: var(--aw-surface-2);
}

.langs a[aria-current='page'] {
  background: var(--aw-surface);
  color: var(--aw-text);
}
</style>
