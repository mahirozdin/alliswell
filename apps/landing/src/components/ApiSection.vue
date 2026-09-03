<script setup>
import { ref } from 'vue';

import { api } from '../content.js';

const copied = ref(false);
let timer = null;

async function copy() {
  try {
    await navigator.clipboard.writeText(api.command);
    copied.value = true;
    clearTimeout(timer);
    timer = setTimeout(() => (copied.value = false), 2000);
  } catch {
    // Clipboard is permission-gated and unavailable over plain http on some
    // browsers — the code is selectable either way, so say nothing.
  }
}
</script>

<template>
  <!--
    OPH-296. Deliberately not a FeatureSection: those are screenshot-led and
    CI gates every `shot` against the built bundle, and a screenshot is the
    wrong evidence for this feature anyway. Somebody deciding whether to write
    a script wants to see the request, so the request is the artwork —
    the same shape SelfHostSection uses, for the same reason.
  -->
  <section id="api" v-reveal class="aw-section">
    <div class="aw-shell apisec">
      <div class="apisec__copy">
        <p class="aw-eyebrow">{{ api.eyebrow }}</p>
        <h2>{{ api.title }}</h2>
        <p class="aw-lede">{{ api.lede }}</p>
        <ul>
          <li v-for="p in api.points" :key="p">{{ p }}</li>
        </ul>
        <div class="apisec__actions">
          <a class="aw-btn" :href="api.link.href">{{ api.link.label }}</a>
          <a class="aw-btn aw-btn--ghost" :href="api.secondary.href" download>
            {{ api.secondary.label }}
          </a>
        </div>
      </div>

      <div class="apisec__term">
        <div class="apisec__bar">
          <span aria-hidden="true">●</span><span aria-hidden="true">●</span
          ><span aria-hidden="true">●</span>
          <span class="apisec__title">your cron job</span>
          <button type="button" class="apisec__copy-btn" @click="copy">
            {{ copied ? 'Copied' : 'Copy' }}
          </button>
        </div>
        <pre><code>{{ api.command }}</code></pre>
      </div>
    </div>
  </section>
</template>

<style scoped>
.apisec {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.1fr);
  gap: clamp(2rem, 5vw, 4rem);
  align-items: center;
}

.apisec__copy ul {
  margin: 1.25rem 0 1.75rem;
  padding-left: 1.15rem;
  display: grid;
  gap: 0.55rem;
  color: var(--aw-text-dim);
  font-size: 0.96rem;
}

.apisec__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
}

.apisec__term {
  border-radius: var(--aw-radius);
  overflow: hidden;
  background: #0b1020;
  border: 1px solid rgb(255 255 255 / 12%);
  box-shadow: var(--aw-shadow);
}

.apisec__bar {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.65rem 1rem;
  background: rgb(255 255 255 / 6%);
  color: rgb(255 255 255 / 40%);
  font-size: 0.7rem;
}

.apisec__title {
  margin-left: 0.75rem;
  font-family: ui-monospace, Menlo, monospace;
  letter-spacing: 0.04em;
}

.apisec__copy-btn {
  margin-left: auto;
  padding: 0.25rem 0.7rem;
  border-radius: 999px;
  border: 1px solid rgb(255 255 255 / 18%);
  background: transparent;
  color: rgb(255 255 255 / 78%);
  font: inherit;
  font-size: 0.72rem;
  cursor: pointer;
}
.apisec__copy-btn:hover {
  background: rgb(255 255 255 / 10%);
}

.apisec__term pre {
  margin: 0;
  padding: 1.25rem;
  overflow-x: auto;
  color: #d7e3ff;
  font-size: 0.8rem;
  line-height: 1.75;
}

@media (max-width: 900px) {
  .apisec {
    grid-template-columns: 1fr;
  }
}
</style>
