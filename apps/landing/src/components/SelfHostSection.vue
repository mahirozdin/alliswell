<script setup>
import { ref } from 'vue';

import { selfHost } from '../content.js';

const copied = ref(false);
let timer = null;

async function copy() {
  try {
    await navigator.clipboard.writeText(selfHost.command);
    copied.value = true;
    clearTimeout(timer);
    timer = setTimeout(() => (copied.value = false), 2000);
  } catch {
    // Clipboard is permission-gated and simply unavailable over plain http on
    // some browsers — the code is selectable either way, so say nothing.
  }
}
</script>

<template>
  <section id="self-host" class="aw-section" v-reveal>
    <div class="aw-shell host">
      <div class="host__copy">
        <p class="aw-eyebrow">{{ selfHost.eyebrow }}</p>
        <h2>{{ selfHost.title }}</h2>
        <p class="aw-lede">{{ selfHost.lede }}</p>
        <ul>
          <li v-for="p in selfHost.points" :key="p">{{ p }}</li>
        </ul>
        <a class="aw-btn aw-btn--ghost" :href="selfHost.link.href" rel="noopener" target="_blank">
          {{ selfHost.link.label }}
        </a>
      </div>

      <div class="host__term">
        <div class="host__bar">
          <span aria-hidden="true">●</span><span aria-hidden="true">●</span
          ><span aria-hidden="true">●</span>
          <span class="host__title">your server</span>
          <button type="button" class="host__copy-btn" @click="copy">
            {{ copied ? 'Copied' : 'Copy' }}
          </button>
        </div>
        <pre><code>{{ selfHost.command }}</code></pre>
      </div>
    </div>
  </section>
</template>

<style scoped>
.host {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.1fr);
  gap: clamp(2rem, 5vw, 4rem);
  align-items: center;
}

.host__copy ul {
  margin: 1.25rem 0 1.75rem;
  padding-left: 1.15rem;
  display: grid;
  gap: 0.55rem;
  color: var(--aw-text-dim);
  font-size: 0.96rem;
}

.host__term {
  border-radius: var(--aw-radius);
  overflow: hidden;
  background: #0b1020;
  border: 1px solid rgb(255 255 255 / 12%);
  box-shadow: var(--aw-shadow);
}

.host__bar {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.65rem 1rem;
  background: rgb(255 255 255 / 6%);
  color: rgb(255 255 255 / 40%);
  font-size: 0.7rem;
}

.host__title {
  margin-left: 0.75rem;
  font-family: ui-monospace, Menlo, monospace;
  letter-spacing: 0.04em;
}

.host__copy-btn {
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
.host__copy-btn:hover {
  background: rgb(255 255 255 / 10%);
}

.host__term pre {
  margin: 0;
  padding: 1.25rem;
  overflow-x: auto;
  color: #d7e3ff;
  font-size: 0.8rem;
  line-height: 1.75;
}

@media (max-width: 900px) {
  .host {
    grid-template-columns: 1fr;
  }
}
</style>
