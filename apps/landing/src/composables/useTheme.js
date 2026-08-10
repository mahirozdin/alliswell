import { onMounted, ref, watch } from 'vue';

const KEY = 'aw_theme';

/**
 * Light / dark, with the same rule the app follows: the system decides until
 * the visitor says otherwise, and then their choice sticks.
 *
 * `data-theme` on <html> is what the stylesheet keys off — not a class — so the
 * override wins over `color-scheme` inheritance without a specificity fight.
 */
// Module scope on purpose: the header owns the toggle, but screenshots read the
// theme too (a dark shot for a dark page). Per-call refs would leave the second
// consumer stuck on whatever it booted with — the toggle would move the page and
// not the pictures.
const theme = ref('light');
const explicit = ref(false);
let wired = false;

export function useTheme() {
  const apply = (value) => {
    document.documentElement.dataset.theme = value;
    theme.value = value;
  };

  onMounted(() => {
    if (wired) return;
    wired = true;
    const stored = localStorage.getItem(KEY);
    if (stored === 'light' || stored === 'dark') {
      explicit.value = true;
      apply(stored);
      return;
    }
    const media = matchMedia('(prefers-color-scheme: dark)');
    apply(media.matches ? 'dark' : 'light');
    media.addEventListener('change', (e) => {
      if (!explicit.value) apply(e.matches ? 'dark' : 'light');
    });
  });

  watch(explicit, (isExplicit) => {
    if (isExplicit) localStorage.setItem(KEY, theme.value);
  });

  const toggle = () => {
    explicit.value = true;
    const next = theme.value === 'dark' ? 'light' : 'dark';
    apply(next);
    localStorage.setItem(KEY, next);
  };

  return { theme, toggle };
}
