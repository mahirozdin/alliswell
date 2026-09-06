<script setup>
import { ref } from 'vue';

import ScreenshotFrame from '../components/ScreenshotFrame.vue';

/**
 * Several captures of one idea, one at a time (EE-153).
 *
 * Three or four screens that belong to the same claim would otherwise be four
 * alternating feature rows, and a page that argues one point four times has
 * stopped arguing. Tabs let the reader take the one they came for.
 *
 * ── TWO THINGS THAT ARE NOT COSMETIC ──────────────────────────────────────
 *
 * It is a real `role="tablist"` with roving `tabindex` and arrow keys, because
 * a div that changes an image on click is a control a keyboard cannot reach and
 * a screen reader cannot describe.
 *
 * And every panel is RENDERED, hidden with `hidden` rather than `v-if`. That is
 * for a gate rather than for the reader: ci.yml greps the built bundle for
 * `/shots/...` literals, and a path that only exists inside a branch nobody
 * took is still in the bundle — but `loading="lazy"` on the inactive ones means
 * the browser does not fetch what nobody looked at.
 */
const props = defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  tabs: { type: Array, required: true },
});

const active = ref(0);
const buttons = ref([]);

function focusTab(i) {
  const next = (i + props.tabs.length) % props.tabs.length;
  active.value = next;
  buttons.value[next]?.focus();
}

function onKey(event, i) {
  if (event.key === 'ArrowRight') focusTab(i + 1);
  else if (event.key === 'ArrowLeft') focusTab(i - 1);
  else if (event.key === 'Home') focusTab(0);
  else if (event.key === 'End') focusTab(props.tabs.length - 1);
  else return;
  event.preventDefault();
}
</script>

<template>
  <section v-reveal class="aw-section tabs">
    <div class="aw-shell">
      <header class="tabs__head">
        <p v-if="eyebrow" class="aw-eyebrow">{{ eyebrow }}</p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <div class="tabs__bar" role="tablist" :aria-label="title">
        <button
          v-for="(tab, i) in tabs"
          :id="`tab-${tab.id}`"
          :key="tab.id"
          ref="buttons"
          type="button"
          role="tab"
          class="tabs__tab"
          :class="{ 'is-active': active === i }"
          :aria-selected="active === i"
          :tabindex="active === i ? 0 : -1"
          :aria-controls="`panel-${tab.id}`"
          @click="active = i"
          @keydown="onKey($event, i)"
        >
          {{ tab.label }}
        </button>
      </div>

      <div
        v-for="(tab, i) in tabs"
        :id="`panel-${tab.id}`"
        :key="tab.id"
        role="tabpanel"
        :aria-labelledby="`tab-${tab.id}`"
        :hidden="active !== i"
        class="tabs__panel"
      >
        <ScreenshotFrame
          :src="tab.shot"
          :src-dark="tab.shotDark || ''"
          :alt="tab.alt"
          variant="browser"
          :label="tab.frameLabel || ''"
        />
        <p v-if="tab.caption" class="tabs__caption">{{ tab.caption }}</p>
      </div>
    </div>
  </section>
</template>

<style scoped>
.tabs__head {
  max-width: 46rem;
  margin-bottom: 1.75rem;
}

.tabs__bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 1.5rem;
}

.tabs__tab {
  padding: 0.55rem 1.1rem;
  border-radius: 999px;
  border: 1px solid var(--aw-hairline);
  background: transparent;
  color: var(--aw-text-dim);
  font: inherit;
  font-size: 0.94rem;
  font-weight: 600;
  cursor: pointer;
  transition: background-color 0.16s var(--aw-ease);
}

.tabs__tab:hover {
  background: var(--aw-surface-2);
}

.tabs__tab.is-active {
  background: var(--aw-surface);
  color: var(--aw-text);
  border-color: transparent;
  box-shadow: var(--aw-shadow-sm);
}

.tabs__panel {
  max-width: 50rem;
}

.tabs__caption {
  margin: 0.9rem 0 0;
  color: var(--aw-text-dim);
  font-size: 0.94rem;
}
</style>
