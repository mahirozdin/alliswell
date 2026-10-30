<script setup>
import { nextTick, ref } from 'vue';

import LoopVideo from './LoopVideo.vue';

/**
 * The five things, as Dusk's "tour": a ruled list of jobs beside one glass
 * pane that changes with the choice (Hallmark: a Switcher, every state real,
 * the first visible without script). Without JavaScript the list is not
 * drawn and all five panes stand one under the other with their own titles,
 * so nothing is hidden from a reader or a crawler.
 */
const props = defineProps({
  tour: { type: Object, required: true },
  ui: { type: Object, required: true },
});

const active = ref(0);
const tabs = ref([]);
const select = async (i, focus = false) => {
  active.value = (i + props.tour.panes.length) % props.tour.panes.length;
  if (focus) {
    await nextTick();
    tabs.value[active.value]?.focus();
  }
};
const onKey = (e, i) => {
  const moves = { ArrowDown: i + 1, ArrowRight: i + 1, ArrowUp: i - 1, ArrowLeft: i - 1, Home: 0, End: -1 };
  if (!(e.key in moves)) return;
  e.preventDefault();
  select(e.key === 'End' ? props.tour.panes.length - 1 : moves[e.key], true);
};
</script>

<template>
  <section id="features" class="section tour">
    <div class="container tour__grid">
      <div class="tour__side">
        <div class="head">
          <h2>{{ tour.title }}</h2>
          <p class="lead">{{ tour.lead }}</p>
        </div>
        <div class="tour__tabs" role="tablist" :aria-label="tour.tabsLabel" aria-orientation="vertical">
          <button
            v-for="(pane, i) in tour.panes"
            :id="`tour-tab-${pane.id}`"
            :key="pane.id"
            :ref="(el) => (tabs[i] = el)"
            class="tour__tab"
            :class="{ 'is-active': i === active }"
            type="button"
            role="tab"
            :aria-selected="i === active ? 'true' : 'false'"
            :aria-controls="`tour-${pane.id}`"
            :tabindex="i === active ? 0 : -1"
            @click="select(i)"
            @keydown="onKey($event, i)"
          >
            <span class="tour__tab-title">{{ pane.tab }}</span>
            <span class="tour__tab-body">{{ pane.body }}</span>
          </button>
        </div>
      </div>
      <div class="tour__panes">
        <div
          v-for="(pane, i) in tour.panes"
          :id="`tour-${pane.id}`"
          :key="pane.id"
          class="tour__pane"
          :class="{ 'is-active': i === active }"
          role="tabpanel"
          :aria-labelledby="`tour-tab-${pane.id}`"
        >
          <div class="tour__text">
            <h3>{{ pane.tab }}</h3>
            <p>{{ pane.body }}</p>
          </div>
          <div class="glass tour__glass">
            <LoopVideo :name="pane.media" :alt="pane.alt" :labels="ui" />
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
