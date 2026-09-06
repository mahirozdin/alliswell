<script setup>
import { useTheme } from '../composables/useTheme.js';

/**
 * The light/dark switch, lifted out of TheHeader (EE-143).
 *
 * It was twenty-five lines of inline SVG inside a header that is about to grow
 * a second caller — the enterprise page has its own nav, and copying a control
 * is how two headers start disagreeing about what "dark" means. `useTheme`'s
 * refs are module-scoped, so both callers read and write the same theme without
 * any wiring between them.
 */
const { theme, toggle } = useTheme();
</script>

<template>
  <button
    class="aw-icon-btn"
    type="button"
    :aria-label="theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'"
    @click="toggle"
  >
    <svg
      v-if="theme === 'dark'"
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="currentColor"
      aria-hidden="true"
    >
      <path
        d="M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 3a1 1 0 0 1 1 1v1a1 1 0 1 1-2 0v-1a1 1 0 0 1 1-1zm0-18a1 1 0 0 1 1 1v1a1 1 0 1 1-2 0V3a1 1 0 0 1 1-1zm10 10a1 1 0 0 1-1 1h-1a1 1 0 1 1 0-2h1a1 1 0 0 1 1 1zM4 12a1 1 0 0 1-1 1H2a1 1 0 1 1 0-2h1a1 1 0 0 1 1 1zm14.4 6.4a1 1 0 0 1-1.4 0l-.7-.7a1 1 0 0 1 1.4-1.4l.7.7a1 1 0 0 1 0 1.4zM7.7 7.7a1 1 0 0 1-1.4 0l-.7-.7a1 1 0 0 1 1.4-1.4l.7.7a1 1 0 0 1 0 1.4zm10.7-2.1a1 1 0 0 1 0 1.4l-.7.7a1 1 0 1 1-1.4-1.4l.7-.7a1 1 0 0 1 1.4 0zM7.7 16.3a1 1 0 0 1 0 1.4l-.7.7a1 1 0 0 1-1.4-1.4l.7-.7a1 1 0 0 1 1.4 0z"
      />
    </svg>
    <svg v-else viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
      <path d="M21 13.2A9 9 0 1 1 10.8 3a7 7 0 0 0 10.2 10.2z" />
    </svg>
  </button>
</template>
