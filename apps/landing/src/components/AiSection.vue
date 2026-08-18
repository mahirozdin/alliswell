<script setup>
import { aiSection } from '../content.js';
</script>

<template>
  <section id="ai" v-reveal class="aw-section ai">
    <div class="aw-shell">
      <header class="ai__head">
        <p class="aw-eyebrow">{{ aiSection.eyebrow }}</p>
        <h2>{{ aiSection.title }}</h2>
        <p class="aw-lede ai__lede">{{ aiSection.lede }}</p>
      </header>

      <div class="ai__tracks">
        <article v-for="track in aiSection.tracks" :key="track.title" class="aw-card ai__card">
          <h3>{{ track.title }}</h3>
          <p class="ai__body">{{ track.body }}</p>
          <ul>
            <li v-for="p in track.points" :key="p">{{ p }}</li>
          </ul>
          <a :href="track.link.href" rel="noopener" target="_blank">{{ track.link.label }} →</a>
        </article>
      </div>

      <p class="ai__foot">
        Not interested? Leave it off. AllisWell has no AI account, sends nothing anywhere by
        default, and every capture surface works without a model.
      </p>
    </div>
  </section>
</template>

<style scoped>
.ai__head {
  max-width: 46rem;
  margin-bottom: 2.5rem;
}

.ai__lede {
  margin-bottom: 0;
}

.ai__tracks {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 1.25rem;
}

.ai__card {
  padding: 1.75rem;
  display: flex;
  flex-direction: column;
}

.ai__card h3 {
  margin-bottom: 0.5rem;
}

.ai__body {
  color: var(--aw-text-dim);
}

.ai__card ul {
  margin: 0.5rem 0 1.5rem;
  padding-left: 1.15rem;
  display: grid;
  gap: 0.5rem;
  color: var(--aw-text-dim);
  font-size: 0.95rem;
}

.ai__card a {
  margin-top: auto;
  font-weight: 620;
  text-decoration: none;
}
.ai__card a:hover {
  text-decoration: underline;
}

.ai__foot {
  margin: 2rem 0 0;
  padding: 1rem 1.25rem;
  border-radius: var(--aw-radius);
  border: 1px dashed var(--aw-hairline);
  color: var(--aw-text-dim);
  font-size: 0.95rem;
}
</style>
