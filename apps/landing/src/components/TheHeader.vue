<script setup>
import { onMounted, onUnmounted, ref } from 'vue';

import BrandMark from './BrandMark.vue';
import LangSwitch from './LangSwitch.vue';
import ThemeToggle from './ThemeToggle.vue';
import { APP_URL, REPO_URL, siteLinks } from '../content.js';
import { useGithubStars } from '../composables/useGithubStars.js';

const { stars, loaded, format } = useGithubStars();

const scrolled = ref(false);
const menuOpen = ref(false);

const onScroll = () => (scrolled.value = window.scrollY > 12);
onMounted(() => {
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });
});
onUnmounted(() => window.removeEventListener('scroll', onScroll));


/**
 * EE-143 — everything the header says is now a prop, defaulted to what it said
 * before. The homepage passes nothing. The enterprise page passes its own nav,
 * its own call to action and its language pair, and gets the same chrome.
 */
defineProps({
  home: { type: String, default: '/' },
  links: { type: Array, default: () => siteLinks },
  cta: { type: Object, default: () => ({ label: 'Open the app', href: APP_URL }) },
  starsLabel: { type: String, default: 'Star' },
  /**
   * EE-164 — the enterprise page turns the star button off. A buyer reading a
   * sales page is not choosing a repository, and a GitHub count next to
   * "Talk to us" is the wrong social proof for that reader. The footer's
   * free-edition column keeps the link to the source.
   */
  showStars: { type: Boolean, default: true },
  alternates: { type: Array, default: () => [] },
  current: { type: String, default: '' },
});
</script>

<template>
  <header class="hdr" :class="{ 'hdr--scrolled': scrolled }">
    <div class="hdr__inner aw-shell">
      <a class="hdr__brand" :href="home">
        <BrandMark :size="32" />
        <span>AllisWell</span>
      </a>

      <nav class="hdr__nav" :class="{ 'is-open': menuOpen }" aria-label="Site">
        <a v-for="l in links" :key="l.href" :href="l.href" @click="menuOpen = false">
          {{ l.label }}
        </a>
      </nav>

      <div class="hdr__actions">
        <a v-if="showStars" class="hdr__stars" :href="REPO_URL" rel="noopener" target="_blank">
          <svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true">
            <path
              d="M8 0a8 8 0 0 0-2.5 15.6c.4.1.5-.2.5-.4v-1.4c-2.2.5-2.7-1-2.7-1-.4-1-.9-1.2-.9-1.2-.7-.5.1-.5.1-.5.8.1 1.2.8 1.2.8.7 1.2 1.9.9 2.4.7 0-.5.3-.9.5-1.1-1.8-.2-3.6-.9-3.6-3.9 0-.9.3-1.6.8-2.1 0-.2-.3-1 .1-2.1 0 0 .7-.2 2.2.8a7.6 7.6 0 0 1 4 0c1.5-1 2.2-.8 2.2-.8.4 1.1.2 1.9.1 2.1.5.5.8 1.2.8 2.1 0 3-1.8 3.7-3.6 3.9.3.3.5.8.5 1.6v2.2c0 .2.1.5.6.4A8 8 0 0 0 8 0z"
            />
          </svg>
          <span class="hdr__stars-label">{{ starsLabel }}</span>
          <span v-if="loaded && stars !== null" class="hdr__stars-count">{{ format(stars) }}</span>
        </a>

        <LangSwitch :alternates="alternates" :current="current" />

        <ThemeToggle />

        <a class="aw-btn aw-btn--sm hdr__cta" :href="cta.href">{{ cta.label }}</a>

        <button
          class="aw-icon-btn hdr__burger"
          type="button"
          :aria-expanded="menuOpen"
          aria-label="Menu"
          @click="menuOpen = !menuOpen"
        >
          <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true">
            <path d="M3 6h18v2H3zm0 5h18v2H3zm0 5h18v2H3z" />
          </svg>
        </button>
      </div>
    </div>
  </header>
</template>

<style scoped>
.hdr {
  position: sticky;
  top: 0;
  z-index: 50;
  transition: box-shadow 0.2s var(--aw-ease);
}

.hdr__inner {
  display: flex;
  align-items: center;
  gap: 1.25rem;
  margin-block: 0.75rem;
  padding: 0.5rem 0.55rem 0.5rem 0.85rem;
  border-radius: 999px;
  background: var(--aw-glass);
  backdrop-filter: blur(24px) saturate(180%);
  -webkit-backdrop-filter: blur(24px) saturate(180%);
  border: 1px solid var(--aw-glass-stroke);
  transition: box-shadow 0.2s var(--aw-ease);
}

.hdr--scrolled .hdr__inner {
  box-shadow: var(--aw-shadow);
}

.hdr__brand {
  display: inline-flex;
  align-items: center;
  gap: 0.55rem;
  font-weight: 700;
  font-size: 1.06rem;
  letter-spacing: -0.02em;
  color: var(--aw-text);
  text-decoration: none;
  flex-shrink: 0;
}

.hdr__nav {
  display: flex;
  gap: 1.35rem;
  margin-inline: auto;
}

.hdr__nav a {
  color: var(--aw-text-dim);
  text-decoration: none;
  font-size: 0.95rem;
  font-weight: 560;
  white-space: nowrap;
}
.hdr__nav a:hover {
  color: var(--aw-text);
}

.hdr__actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-shrink: 0;
}

.hdr__stars {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  height: 40px;
  padding: 0 0.85rem;
  border-radius: 999px;
  border: 1px solid var(--aw-hairline);
  color: var(--aw-text);
  text-decoration: none;
  font-size: 0.9rem;
  font-weight: 600;
}
.hdr__stars:hover {
  background: var(--aw-surface-2);
}

.hdr__stars-count {
  padding-left: 0.5rem;
  margin-left: 0.1rem;
  border-left: 1px solid var(--aw-hairline);
  color: var(--aw-text-dim);
  font-variant-numeric: tabular-nums;
}

.hdr__burger {
  display: none;
}

/* EE-164 — the Turkish homepage's seven labels are a third longer than the
   English ones, and at 1280 px the call to action was pushed clean out of the
   pill (measured: 1260 px of content in a 1178 px bar). Tighten first, collapse
   later: the star count loses its word and the nav its slack below 1280, and
   the burger takes over at 1120 rather than 940 — where the English nav was
   already 140 px too wide as well, just less visibly. */
@media (max-width: 1280px) {
  .hdr__nav {
    gap: 1rem;
  }
  .hdr__nav a {
    font-size: 0.9rem;
  }
  .hdr__stars-label {
    display: none;
  }
}

@media (max-width: 1120px) {
  .hdr__nav {
    position: absolute;
    inset: calc(100% + 8px) 0 auto 0;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.75rem;
    border-radius: var(--aw-radius);
    background: var(--aw-surface);
    border: 1px solid var(--aw-hairline);
    box-shadow: var(--aw-shadow);
    display: none;
  }
  .hdr__nav.is-open {
    display: flex;
  }
  .hdr__nav a {
    padding: 0.6rem 0.75rem;
    border-radius: 12px;
  }
  .hdr__nav a:hover {
    background: var(--aw-surface-2);
  }
  .hdr__actions {
    margin-left: auto;
  }
  .hdr__burger {
    display: inline-flex;
  }
  .hdr__stars-label {
    display: none;
  }
}

@media (max-width: 620px) {
  .hdr__cta {
    display: none;
  }
}
</style>
