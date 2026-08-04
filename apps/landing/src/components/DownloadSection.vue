<script setup>
import PlatformIcon from './PlatformIcon.vue';
import { download, selfHost } from '../content.js';
</script>

<template>
  <section id="get" class="aw-section get" v-reveal>
    <div class="aw-shell">
      <header class="get__head">
        <p class="aw-eyebrow">{{ download.eyebrow }}</p>
        <h2>{{ download.title }}</h2>
        <p class="aw-lede">{{ download.lede }}</p>
      </header>

      <div class="get__grid">
        <article class="aw-card get__card get__card--live">
          <span class="get__badge get__badge--live">{{ download.web.status }}</span>
          <h3>
            <PlatformIcon name="globe" :size="22" />
            {{ download.web.title }}
          </h3>
          <p>{{ download.web.body }}</p>
          <a class="aw-btn" :href="download.web.cta.href">{{ download.web.cta.label }}</a>
        </article>

        <article
          v-for="store in download.stores"
          :key="store.name"
          class="aw-card get__card"
          :class="{ 'get__card--live': store.cta }"
        >
          <span class="get__badge" :class="{ 'get__badge--live': store.cta }">{{
            store.status
          }}</span>
          <h3>
            <PlatformIcon :name="store.icon" :size="22" />
            {{ store.name }}
          </h3>
          <p>{{ store.body }}</p>
          <a
            v-if="store.cta"
            class="aw-btn"
            :href="store.cta.href"
            rel="noopener"
            target="_blank"
            >{{ store.cta.label }}</a
          >
          <span v-else class="get__soon">Coming soon</span>
        </article>
      </div>

      <p class="get__note">
        {{ download.selfHostNote }}
        <a :href="selfHost.link.href" rel="noopener" target="_blank">{{ selfHost.link.label }} →</a>
      </p>
    </div>
  </section>
</template>

<style scoped>
.get__head {
  max-width: 46rem;
  margin-bottom: 2.25rem;
}

.get__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 1.15rem;
}

.get__card {
  padding: 1.75rem;
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
}

.get__card--live {
  border-color: color-mix(in srgb, var(--aw-primary) 40%, var(--aw-hairline));
  box-shadow: 0 18px 44px -22px color-mix(in srgb, var(--aw-primary) 70%, transparent);
}

.get__card h3 {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  margin: 0;
}

.get__card p {
  margin: 0;
  color: var(--aw-text-dim);
  font-size: 0.95rem;
  flex-grow: 1;
}

.get__card .aw-btn {
  margin-top: 0.75rem;
  align-self: flex-start;
}

.get__badge {
  align-self: flex-start;
  padding: 0.22rem 0.7rem;
  border-radius: 999px;
  background: var(--aw-surface-2);
  color: var(--aw-text-dim);
  font-size: 0.73rem;
  font-weight: 660;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.get__badge--live {
  background: color-mix(in srgb, var(--aw-success) 16%, transparent);
  color: var(--aw-success);
}

.get__soon {
  margin-top: 0.75rem;
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--aw-text-dim);
}

.get__note {
  margin: 1.75rem 0 0;
  font-size: 0.95rem;
  color: var(--aw-text-dim);
}
</style>
