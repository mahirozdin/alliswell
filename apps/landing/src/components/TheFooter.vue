<script setup>
import BrandMark from './BrandMark.vue';
import { APP_URL, DOCS_URL, PLAY_URL, REPO_URL, VERSION } from '../content.js';
import { company } from '../company.js';
import { useGithubStars } from '../composables/useGithubStars.js';

const { stars, forks, loaded, format } = useGithubStars();

const columns = [
  {
    title: 'Product',
    links: [
      { label: 'Open the app', href: APP_URL },
      { label: 'Get it on Google Play', href: PLAY_URL },
      { label: 'Features', href: '#features' },
      { label: 'Comparison', href: '#compare' },
      { label: 'Enterprise', href: '/enterprise' },
      { label: 'Roadmap', href: `${REPO_URL}/blob/main/ROADMAP.md` },
      { label: 'Changelog', href: `${REPO_URL}/blob/main/CHANGELOG.md` },
    ],
  },
  {
    title: 'Run it yourself',
    links: [
      { label: 'Self-hosting guide', href: `${DOCS_URL}/SELF-HOSTING.md` },
      { label: 'Architecture', href: `${DOCS_URL}/ARCHITECTURE.md` },
      { label: 'Attachments (R2/S3)', href: `${DOCS_URL}/ATTACHMENTS.md` },
      { label: 'Notifications & alarms', href: `${DOCS_URL}/NOTIFICATIONS.md` },
    ],
  },
  {
    title: 'AI',
    links: [
      { label: 'How AI works', href: `${DOCS_URL}/AI.md` },
      { label: 'MCP connector', href: `${DOCS_URL}/MCP.md` },
      // OPH-296: the REST API sat in this repo undocumented on the site for
      // two releases. It belongs beside the MCP connector — they are the two
      // ways something other than the app reaches your data.
      { label: 'REST API reference', href: '/docs/api' },
      { label: 'Security policy', href: `${REPO_URL}/blob/main/SECURITY.md` },
      { label: 'Privacy policy', href: '/privacy' },
    ],
  },
  {
    title: 'Project',
    links: [
      { label: 'GitHub', href: REPO_URL },
      { label: 'Contributing', href: `${REPO_URL}/blob/main/CONTRIBUTING.md` },
      { label: 'Issues', href: `${REPO_URL}/issues` },
      { label: 'Support', href: '/support' },
      { label: 'Licence (PolyForm NC)', href: `${REPO_URL}/blob/main/LICENSE` },
      { label: 'Commercial licensing', href: 'mailto:info@bubiapps.com' },
    ],
  },
];
</script>

<template>
  <footer class="ftr">
    <div class="aw-shell">
      <div class="ftr__top">
        <div class="ftr__brand">
          <a class="ftr__mark" href="#top">
            <BrandMark :size="34" />
            <span>AllisWell</span>
          </a>
          <p>
            Source-available, self-hosted tasks, notes and alarm-grade reminders. Free for
            personal use. Built in the open, one task at a time.
          </p>
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
          <a href="/privacy">Privacy</a> · <a href="/support">Support</a> ·
          <a :href="`mailto:${company.email}`">{{ company.email }}</a>
        </p>
        <p>
          Not affiliated with Apple, Google, Anthropic or OpenAI. Product names are their owners’.
        </p>
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

@media (max-width: 900px) {
  .ftr__top {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .ftr__brand {
    grid-column: 1 / -1;
  }
}
</style>
