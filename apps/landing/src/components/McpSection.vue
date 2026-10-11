<script setup>
import { ref } from 'vue';

import { mcp as mcpDefault } from '../content.js';

/**
 * OPH-364 — the connector, with its URL on the page.
 *
 * Before this the homepage said "AllisWell is a remote MCP server" and linked
 * to a markdown file on GitHub; the address itself was nowhere on the site. An
 * agent asked to find it guessed `alliswell.space/mcp` from the domain — which
 * is this site, not the API — and a Claude Team owner pasted the guess. So the
 * URL is the artwork here, with a copy button, the way ApiSection makes its
 * request the artwork.
 */
const props = defineProps({
  mcp: {
    type: Object,
    default: () => ({ ...mcpDefault, copyLabel: 'Copy', copiedLabel: 'Copied' }),
  },
});

const copied = ref(false);
let timer = null;

async function copy() {
  try {
    await navigator.clipboard.writeText(props.mcp.url);
    copied.value = true;
    clearTimeout(timer);
    timer = setTimeout(() => (copied.value = false), 2000);
  } catch {
    // Clipboard is permission-gated; the URL is selectable text either way.
  }
}
</script>

<template>
  <section id="mcp" v-reveal class="aw-section">
    <div class="aw-shell">
      <header class="mcp__head">
        <p class="aw-eyebrow">{{ mcp.eyebrow }}</p>
        <h2>{{ mcp.title }}</h2>
        <p class="aw-lede">{{ mcp.lede }}</p>
      </header>

      <div class="mcp__url">
        <p class="mcp__url-label">{{ mcp.urlLabel }}</p>
        <div class="mcp__url-row">
          <code>{{ mcp.url }}</code>
          <button type="button" class="aw-btn" @click="copy">
            {{ copied ? mcp.copiedLabel : mcp.copyLabel }}
          </button>
        </div>
        <p class="mcp__self">{{ mcp.selfHost }}</p>
      </div>

      <div class="mcp__clients">
        <article v-for="client in mcp.clients" :key="client.name" class="aw-card mcp__card">
          <h3>{{ client.name }}</h3>
          <p class="mcp__note">{{ client.note }}</p>
          <ol>
            <li v-for="step in client.steps" :key="step">{{ step }}</li>
          </ol>
        </article>
      </div>

      <div class="mcp__foot">
        <div>
          <p class="mcp__prompts-title">{{ mcp.promptsTitle }}</p>
          <ul class="mcp__prompts">
            <li v-for="prompt in mcp.prompts" :key="prompt">“{{ prompt }}”</li>
          </ul>
          <p class="mcp__safety">{{ mcp.safety }}</p>
        </div>
        <a class="aw-btn aw-btn--ghost" :href="mcp.link.href">{{ mcp.link.label }}</a>
      </div>
    </div>
  </section>
</template>

<style scoped>
.mcp__head {
  max-width: 46rem;
  margin-bottom: 2rem;
}

.mcp__url {
  padding: 1.5rem;
  border-radius: var(--aw-radius);
  background: #0b1020;
  border: 1px solid rgb(255 255 255 / 12%);
  box-shadow: var(--aw-shadow);
  margin-bottom: 1.25rem;
}

.mcp__url-label {
  margin: 0 0 0.6rem;
  color: rgb(255 255 255 / 62%);
  font-size: 0.8rem;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.mcp__url-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem 1rem;
}

.mcp__url-row code {
  flex: 1 1 18rem;
  color: #d7e3ff;
  font-family: ui-monospace, Menlo, monospace;
  font-size: clamp(1rem, 2.4vw, 1.35rem);
  overflow-wrap: anywhere;
  user-select: all;
}

.mcp__self {
  margin: 0.9rem 0 0;
  color: rgb(255 255 255 / 70%);
  font-size: 0.9rem;
}

.mcp__clients {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 1.25rem;
}

.mcp__card {
  padding: 1.5rem;
}

.mcp__card h3 {
  margin-bottom: 0.15rem;
}

.mcp__note {
  margin: 0 0 0.75rem;
  color: var(--aw-text-dim);
  font-size: 0.9rem;
}

.mcp__card ol {
  margin: 0;
  padding-left: 1.2rem;
  display: grid;
  gap: 0.5rem;
  color: var(--aw-text-dim);
  font-size: 0.95rem;
}

.mcp__foot {
  margin-top: 1.75rem;
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  justify-content: space-between;
  gap: 1.25rem;
}

.mcp__prompts-title {
  margin: 0 0 0.5rem;
  font-weight: 620;
}

.mcp__prompts {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.mcp__prompts li {
  padding: 0.35rem 0.8rem;
  border-radius: 999px;
  border: 1px solid var(--aw-hairline);
  background: var(--aw-surface);
  color: var(--aw-text-dim);
  font-size: 0.9rem;
}

.mcp__safety {
  margin: 0.9rem 0 0;
  color: var(--aw-text-dim);
  font-size: 0.9rem;
  max-width: 46rem;
}
</style>
