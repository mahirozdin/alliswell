<script setup>
/**
 * Cloud, or your own servers (EE-164).
 *
 * This replaces the "install it yourself" terminal block that the page carried
 * from the homepage. That block was true of the free edition and wrong for
 * this one: an enterprise customer never runs `docker compose` — either they
 * use the hosted service under their own address, or our team installs it on
 * their hardware. A sales page that hands the buyer a shell command has told
 * them the wrong thing about who does the work.
 *
 * Two cards, same shape, because the offer really is symmetrical: the same
 * product, and the reader picks where the data lives. Each card ends in the
 * action that follows from choosing it — the cloud card points at the package
 * table, the on-premise card at the form, because there is no package table
 * for on-premise: the limits are set with the customer at installation.
 */
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lede: { type: String, default: '' },
  /** `[{ key, icon, title, tagline, points, cta: { label, href } }]` */
  options: { type: Array, required: true },
  footnote: { type: String, default: '' },
  anchor: { type: String, default: 'deploy' },
});
</script>

<template>
  <section :id="anchor" v-reveal class="aw-section deploy">
    <div class="aw-shell">
      <header class="deploy__head">
        <p v-if="eyebrow" class="aw-eyebrow">{{ eyebrow }}</p>
        <h2>{{ title }}</h2>
        <p v-if="lede" class="aw-lede">{{ lede }}</p>
      </header>

      <div class="deploy__grid">
        <article v-for="o in options" :key="o.key" class="aw-card deploy__card">
          <span class="deploy__icon" aria-hidden="true">{{ o.icon }}</span>
          <h3>{{ o.title }}</h3>
          <p class="deploy__tagline">{{ o.tagline }}</p>
          <ul class="deploy__points">
            <li v-for="p in o.points" :key="p">
              <svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true">
                <circle cx="10" cy="10" r="9" fill="currentColor" opacity="0.14" />
                <path
                  d="M6 10.2 8.7 13 14 7.4"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
              <span>{{ p }}</span>
            </li>
          </ul>
          <a class="aw-btn" :class="{ 'aw-btn--ghost': o.key !== 'self' }" :href="o.cta.href">
            {{ o.cta.label }}
          </a>
        </article>
      </div>

      <p v-if="footnote" class="deploy__foot">{{ footnote }}</p>
    </div>
  </section>
</template>

<style scoped>
.deploy__head {
  max-width: 46rem;
  margin-bottom: 2rem;
}

.deploy__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 22rem), 1fr));
  gap: 1.25rem;
}

.deploy__card {
  display: flex;
  flex-direction: column;
  padding: clamp(1.5rem, 3vw, 2.1rem);
}

.deploy__icon {
  display: block;
  font-size: 2rem;
  line-height: 1;
  margin-bottom: 0.85rem;
}

.deploy__card h3 {
  margin-bottom: 0.25rem;
}

.deploy__tagline {
  margin: 0 0 1.1rem;
  color: var(--aw-text-dim);
  font-weight: 560;
}

.deploy__points {
  list-style: none;
  margin: 0 0 1.5rem;
  padding: 0;
  display: grid;
  gap: 0.65rem;
  flex: 1;
}

.deploy__points li {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.65rem;
  align-items: start;
  font-size: 0.97rem;
  color: var(--aw-text-dim);
}

.deploy__points svg {
  color: var(--aw-success);
  margin-top: 2px;
}

.deploy__card .aw-btn {
  align-self: flex-start;
}

.deploy__foot {
  margin: 1.25rem 0 0;
  font-size: 0.92rem;
  color: var(--aw-text-dim);
  max-width: 62ch;
}
</style>
