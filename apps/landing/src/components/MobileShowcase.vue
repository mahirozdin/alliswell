<script setup>
import ScreenshotFrame from './ScreenshotFrame.vue';

/**
 * The phone strip. Every image here is a real capture off a booted device —
 * iOS from the simulator at native 1320×2868, Android from the emulator — so
 * the status bars, the safe areas and the platform's own type rendering are
 * the device's, not a mock-up's.
 */
const shots = [
  { src: '/shots/ios/01-home.jpg', caption: 'Home — iPhone', alt: 'AllisWell Home on iPhone with the month calendar and overdue tasks' },
  { src: '/shots/ios/07-task-detail-repeat.jpg', caption: 'A repeating task', alt: 'Task detail on iPhone: urgent alarm, repeat rule “every month on day 31”, due 30 September' },
  { src: '/shots/ios/08-repeat-dialog.jpg', caption: 'The next five days', alt: 'The Repeat dialog on iPhone showing a live preview of the next five occurrences' },
  { src: '/shots/android/01-home.jpg', caption: 'Home — Android', alt: 'AllisWell Home on an Android phone' },
  { src: '/shots/android/09-alarm-ring.jpg', caption: 'An alarm, on Android', alt: 'AllisWell’s full-screen urgent reminder on Android, with an Acknowledge button and snooze presets' },
  { src: '/shots/android/04-projects.jpg', caption: 'Projects — Android', alt: 'AllisWell Projects on an Android phone' },
];
</script>

<template>
  <section class="aw-section mob" v-reveal>
    <div class="aw-shell">
      <header class="mob__head">
        <p class="aw-eyebrow">One codebase</p>
        <h2>The same app, everywhere you are</h2>
        <p class="aw-lede">
          iPhone, Android, the browser, and native builds for macOS, Windows and Linux — from one
          Flutter codebase, with a local database on each of them.
        </p>
      </header>

      <div class="mob__rail">
        <figure v-for="s in shots" :key="s.src" class="mob__item">
          <ScreenshotFrame variant="phone" :src="s.src" :alt="s.alt" />
          <figcaption>{{ s.caption }}</figcaption>
        </figure>
      </div>
    </div>
  </section>
</template>

<style scoped>
.mob__head {
  max-width: 46rem;
  margin-bottom: 2.5rem;
}

.mob__rail {
  display: flex;
  gap: 1.5rem;
  overflow-x: auto;
  padding-bottom: 1rem;
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
}

.mob__item {
  margin: 0;
  flex: 0 0 auto;
  width: min(240px, 62vw);
  scroll-snap-align: center;
}

.mob__item figcaption {
  margin-top: 0.85rem;
  text-align: center;
  font-size: 0.86rem;
  color: var(--aw-text-dim);
}
</style>
