<script setup>
import { ref } from 'vue';

import ScreenshotFrame from '../components/ScreenshotFrame.vue';

/**
 * Several captures of one idea, one at a time (EE-153; two columns in EE-164).
 *
 * Three or four screens that belong to the same claim would otherwise be four
 * alternating feature rows, and a page that argues one point four times has
 * stopped arguing. Tabs let the reader take the one they came for.
 *
 * ── WHY TWO COLUMNS ───────────────────────────────────────────────────────
 *
 * The first version stacked a heading, a row of pills and an 800 px picture
 * down the left of a 1180 px shell, and left the right third of the section
 * empty. Next to feature rows that fill the shell edge to edge it read as a
 * layout that had slipped. Now the copy — heading, lede, and the tab list with
 * each tab's one-line description — takes one column and the picture the
 * other, in the same 5:7 rhythm as `FeatureSection`, and the parent alternates
 * which side is which (`flip`) on the same running count.
 *
 * The description sits INSIDE the tab button rather than under the picture,
 * so the list reads as a feature list even before anything is clicked. The
 * button's accessible name stays the short label (`aria-label`); the blurb is
 * visible detail, not the control's name.
 *
 * ── TWO THINGS THAT ARE NOT COSMETIC ──────────────────────────────────────
 *
 * It is a real `role="tablist"` with roving `tabindex` and arrow keys, because
 * a div that changes an image on click is a control a keyboard cannot reach and
 * a screen reader cannot describe. Vertical on wide screens, so Up/Down work
 * alongside Left/Right.
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
  /** Copy on the right, picture on the left. Decided by the parent. */
  flip: { type: Boolean, default: false },
});

const active = ref(0);
const buttons = ref([]);

function focusTab(i) {
  const next = (i + props.tabs.length) % props.tabs.length;
  active.value = next;
  buttons.value[next]?.focus();
}

function onKey(event, i) {
  if (event.key === 'ArrowRight' || event.key === 'ArrowDown') focusTab(i + 1);
  else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') focusTab(i - 1);
  else if (event.key === 'Home') focusTab(0);
  else if (event.key === 'End') focusTab(props.tabs.length - 1);
  else return;
  event.preventDefault();
}
</script>

<template>
  <section v-reveal class="aw-section tabs" :class="{ 'tabs--flip': flip }">
    <div class="aw-shell tabs__grid">
      <div class="tabs__copy">
        <header class="tabs__head">
          <p v-if="eyebrow" class="aw-eyebrow">{{ eyebrow }}</p>
          <h2>{{ title }}</h2>
          <p v-if="lede" class="aw-lede">{{ lede }}</p>
        </header>

        <div class="tabs__list" role="tablist" aria-orientation="vertical" :aria-label="title">
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
            :aria-label="tab.label"
            :tabindex="active === i ? 0 : -1"
            :aria-controls="`panel-${tab.id}`"
            @click="active = i"
            @keydown="onKey($event, i)"
          >
            <span class="tabs__label">{{ tab.label }}</span>
            <span v-if="tab.caption" class="tabs__blurb">{{ tab.caption }}</span>
          </button>
        </div>
      </div>

      <div class="tabs__stage">
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
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.tabs__grid {
  display: grid;
  grid-template-columns: minmax(0, 5fr) minmax(0, 7fr);
  gap: clamp(2rem, 5vw, 4rem);
  align-items: start;
}

.tabs--flip .tabs__copy {
  order: 2;
}

.tabs__head h2 {
  margin-bottom: 0.6rem;
}

.tabs__list {
  display: grid;
  gap: 0.4rem;
  margin-top: 1.5rem;
}

.tabs__tab {
  display: grid;
  gap: 0.25rem;
  width: 100%;
  text-align: left;
  padding: 0.85rem 1rem;
  border-radius: 14px;
  border: 1px solid transparent;
  background: transparent;
  color: var(--aw-text-dim);
  font: inherit;
  cursor: pointer;
  transition:
    background-color 0.16s var(--aw-ease),
    border-color 0.16s var(--aw-ease),
    box-shadow 0.16s var(--aw-ease);
}

.tabs__tab:hover {
  background: var(--aw-surface-2);
}

.tabs__tab.is-active {
  background: var(--aw-surface);
  border-color: var(--aw-hairline);
  box-shadow: var(--aw-shadow-sm);
  color: var(--aw-text);
}

.tabs__label {
  font-size: 1rem;
  font-weight: 650;
  color: var(--aw-text);
}

.tabs__blurb {
  font-size: 0.92rem;
  line-height: 1.5;
  color: var(--aw-text-dim);
}

.tabs__stage {
  min-width: 0;
}

@media (max-width: 900px) {
  .tabs__grid {
    grid-template-columns: 1fr;
  }
  .tabs--flip .tabs__copy {
    order: 0;
  }
}
</style>
