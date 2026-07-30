<script setup>
import BrandMark from './BrandMark.vue';
import PlatformIcon from './PlatformIcon.vue';
import ScreenshotFrame from './ScreenshotFrame.vue';
import { hero, platforms, REPO_URL } from '../content.js';
import { useGithubStars } from '../composables/useGithubStars.js';

const { stars, loaded, format } = useGithubStars();
</script>

<template>
  <section id="top" class="hero">
    <div class="aw-shell hero__inner">
      <p class="aw-eyebrow">
        <BrandMark :size="16" />
        {{ hero.eyebrow }}
      </p>

      <h1>{{ hero.title }}</h1>
      <p class="aw-lede hero__lede">{{ hero.lede }}</p>

      <div class="hero__cta">
        <a class="aw-btn" :href="hero.primary.href">
          {{ hero.primary.label }}
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
            <path d="M13.2 5.4 20 12l-6.8 6.6-1.4-1.4 4.2-4.2H4v-2h12l-4.2-4.2z" />
          </svg>
        </a>
        <a class="aw-btn aw-btn--ghost" :href="hero.secondary.href">{{ hero.secondary.label }}</a>
        <a class="aw-btn aw-btn--ghost" :href="REPO_URL" rel="noopener" target="_blank">
          <svg viewBox="0 0 16 16" width="17" height="17" fill="currentColor" aria-hidden="true">
            <path
              d="M8 0a8 8 0 0 0-2.5 15.6c.4.1.5-.2.5-.4v-1.4c-2.2.5-2.7-1-2.7-1-.4-1-.9-1.2-.9-1.2-.7-.5.1-.5.1-.5.8.1 1.2.8 1.2.8.7 1.2 1.9.9 2.4.7 0-.5.3-.9.5-1.1-1.8-.2-3.6-.9-3.6-3.9 0-.9.3-1.6.8-2.1 0-.2-.3-1 .1-2.1 0 0 .7-.2 2.2.8a7.6 7.6 0 0 1 4 0c1.5-1 2.2-.8 2.2-.8.4 1.1.2 1.9.1 2.1.5.5.8 1.2.8 2.1 0 3-1.8 3.7-3.6 3.9.3.3.5.8.5 1.6v2.2c0 .2.1.5.6.4A8 8 0 0 0 8 0z"
            />
          </svg>
          <span v-if="loaded && stars !== null">{{ format(stars) }} stars</span>
          <span v-else>Source on GitHub</span>
        </a>
      </div>

      <p class="hero__note">{{ hero.note }}</p>

      <ul class="hero__platforms" aria-label="Available on">
        <li v-for="p in platforms" :key="p.name">
          <PlatformIcon :name="p.icon" :size="17" />
          {{ p.name }}
        </li>
      </ul>
    </div>

    <div class="aw-shell hero__shots">
      <ScreenshotFrame
        class="hero__desktop"
        src="/shots/web/home-light.jpg"
        alt="AllisWell on the web: Home with overdue and today groups, project badges, tag chips, a quick-access rail and a month calendar"
        eager
      />
      <ScreenshotFrame
        class="hero__phone"
        variant="phone"
        src="/shots/ios/01-home.jpg"
        alt="AllisWell on iPhone: the same day, with the month calendar and the overdue group"
        eager
      />
    </div>
  </section>
</template>

<style scoped>
.hero {
  padding-top: clamp(2.5rem, 6vw, 5rem);
  overflow: hidden;
}

.hero__inner {
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.hero h1 {
  max-width: 16ch;
  background: linear-gradient(
    170deg,
    var(--aw-text) 30%,
    color-mix(in srgb, var(--aw-primary) 70%, var(--aw-text))
  );
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.hero__lede {
  margin-bottom: 2rem;
}

.hero__cta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  justify-content: center;
}

.hero__note {
  margin-top: 1.25rem;
  font-size: 0.92rem;
  color: var(--aw-text-dim);
}

.hero__platforms {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem 1.5rem;
  justify-content: center;
  margin: 1.5rem 0 0;
  padding: 0;
  list-style: none;
  color: var(--aw-text-dim);
  font-size: 0.88rem;
  font-weight: 560;
}

.hero__platforms li {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
}

.hero__shots {
  position: relative;
  margin-top: clamp(2.5rem, 5vw, 4rem);
}

.hero__phone {
  position: absolute;
  right: -1rem;
  bottom: -2rem;
  width: 23%;
  max-width: 240px;
}

@media (max-width: 760px) {
  .hero__phone {
    display: none;
  }
}
</style>
