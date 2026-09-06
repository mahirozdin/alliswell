<script setup>
import BrandMark from './BrandMark.vue';
import LangSwitch from './LangSwitch.vue';
import { VERSION, siteColumns } from '../content.js';
import { company } from '../company.js';
import { useGithubStars } from '../composables/useGithubStars.js';

const { stars, forks, loaded, format } = useGithubStars();


/**
 * EE-143 — the footer's own words become props so a second page can speak its
 * own language. `company.legalName` and the contact address deliberately stay
 * shared: the legal identity is the one thing that must not fork per page.
 */
defineProps({
  home: { type: String, default: '/' },
  columns: { type: Array, default: () => siteColumns },
  blurb: {
    type: String,
    default:
      'Source-available, self-hosted tasks, notes and alarm-grade reminders. Free for ' +
      'personal use. Built in the open, one task at a time.',
  },
  notes: {
    type: String,
    default:
      'Not affiliated with Apple, Google, Anthropic or OpenAI. Product names are their owners’.',
  },
  privacyLabel: { type: String, default: 'Privacy' },
  supportLabel: { type: String, default: 'Support' },
  privacyHref: { type: String, default: '/privacy' },
  supportHref: { type: String, default: '/support' },
  alternates: { type: Array, default: () => [] },
  current: { type: String, default: '' },
});
</script>

<template>
  <footer class="ftr">
    <div class="aw-shell">
      <div class="ftr__top">
        <div class="ftr__brand">
          <a class="ftr__mark" :href="home">
            <BrandMark :size="34" />
            <span>AllisWell</span>
          </a>
          <p>{{ blurb }}</p>
          <p v-if="loaded && stars !== null" class="ftr__stats">
            ★ {{ format(stars) }} stars · {{ format(forks ?? 0) }} forks · v{{ VERSION }}
          </p>
          <p v-else class="ftr__stats">v{{ VERSION }} · PolyForm Noncommercial</p>
        </div>

        <nav v-for="col in columns" :key="col.title" class="ftr__col" :aria-label="col.title">
          <h3>{{ col.title }}</h3>
          <ul>
            <li v-for="l in col.links" :key="l.label">
              <a
                :href="l.href"
                :target="/^https?:/.test(l.href) ? '_blank' : null"
                rel="noopener"
              >
                {{ l.label }}
              </a>
            </li>
          </ul>
        </nav>
      </div>

      <div class="ftr__bottom">
        <p>
          © {{ new Date().getFullYear() }} {{ company.legalName }} ·
          <a :href="privacyHref">{{ privacyLabel }}</a> ·
          <a :href="supportHref">{{ supportLabel }}</a> ·
          <a :href="`mailto:${company.email}`">{{ company.email }}</a>
        </p>
        <p>{{ notes }}</p>
        <LangSwitch class="ftr__langs" :alternates="alternates" :current="current" />
      </div>
    </div>
  </footer>
</template>

<style scoped>
.ftr {
  padding-block: clamp(3rem, 6vw, 4.5rem) 2rem;
  border-top: 1px solid var(--aw-hairline);
  background: color-mix(in srgb, var(--aw-surface) 45%, transparent);
}

.ftr__top {
  display: grid;
  grid-template-columns: minmax(0, 1.6fr) repeat(4, minmax(0, 1fr));
  gap: 2rem;
}

.ftr__mark {
  display: inline-flex;
  align-items: center;
  gap: 0.55rem;
  font-weight: 700;
  font-size: 1.1rem;
  color: var(--aw-text);
  text-decoration: none;
  margin-bottom: 0.85rem;
}

.ftr__brand p {
  color: var(--aw-text-dim);
  font-size: 0.92rem;
  max-width: 32ch;
}

.ftr__stats {
  font-variant-numeric: tabular-nums;
  font-size: 0.86rem !important;
}

.ftr__col h3 {
  font-size: 0.78rem;
  letter-spacing: 0.07em;
  text-transform: uppercase;
  color: var(--aw-text-dim);
  margin-bottom: 0.85rem;
}

.ftr__col ul {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 0.55rem;
}

.ftr__col a {
  color: var(--aw-text);
  text-decoration: none;
  font-size: 0.92rem;
}
.ftr__col a:hover {
  color: var(--aw-primary-strong);
  text-decoration: underline;
}

.ftr__bottom {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 0.5rem 2rem;
  margin-top: 2.5rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--aw-hairline);
  color: var(--aw-text-dim);
  font-size: 0.83rem;
}

.ftr__bottom p {
  margin: 0;
}

.ftr__langs {
  /* The switch is also in the header. It is repeated at the bottom because the
     enterprise page is long, and a reader who reaches the end in the wrong
     language should not have to scroll back up to say so. */
  flex-basis: 100%;
  margin-top: 0.35rem;
}

@media (max-width: 900px) {
  .ftr__top {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .ftr__brand {
    grid-column: 1 / -1;
  }
}
</style>
