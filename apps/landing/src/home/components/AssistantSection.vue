<script setup>
import { onBeforeUnmount, ref } from 'vue';

import HomeIcon from './HomeIcon.vue';
import LoopVideo from './LoopVideo.vue';

/**
 * The connector (OPH-364): what you do in three steps, the one address to
 * paste, and the loop of an assistant moving tasks after an approval. The
 * address is plain text in the HTML, so a crawler and an agent reading this
 * page can take it without running anything; the copy button is a nicety
 * that only appears once scripting is on.
 */
defineProps({ assistant: { type: Object, required: true }, ui: { type: Object, required: true } });

const copied = ref(false);
let timer;
const copy = async (text) => {
  try {
    await navigator.clipboard.writeText(text);
    copied.value = true;
    clearTimeout(timer);
    timer = setTimeout(() => (copied.value = false), 1800);
  } catch {
    copied.value = false;
  }
};
onBeforeUnmount(() => clearTimeout(timer));
</script>

<template>
  <section id="mcp" class="section assistant">
    <div class="container split split--lead">
      <div class="split__text">
        <div class="head">
          <h2>{{ assistant.title }}</h2>
          <p class="lead">{{ assistant.lead }}</p>
        </div>
        <ol class="steps">
          <li v-for="(step, i) in assistant.steps" :key="step">
            <span>{{ step }}</span>
            <div v-if="i === 1" class="well address">
              <span class="address__label">{{ assistant.urlLabel }}</span>
              <div class="address__row">
                <code>{{ assistant.url }}</code>
                <button class="btn btn--ghost btn--sm address__copy" type="button" @click="copy(assistant.url)">
                  <HomeIcon :name="copied ? 'check' : 'copy'" :size="16" />
                  <span aria-live="polite">{{ copied ? assistant.copied : assistant.copy }}</span>
                </button>
              </div>
            </div>
          </li>
        </ol>
        <p class="split__fact">{{ assistant.fact }}</p>
        <a class="text-link" :href="assistant.link.href">{{ assistant.link.label }}</a>
      </div>
      <div class="glass split__visual">
        <LoopVideo :name="assistant.media" :alt="assistant.alt" :labels="ui" />
      </div>
    </div>
  </section>
</template>
