/**
 * `v-reveal` — fades a section in the first time it scrolls into view.
 *
 * A directive rather than a component so it can be dropped on any element
 * without adding a wrapper to the DOM, and an IntersectionObserver rather than
 * a scroll listener so it costs nothing while the user is reading. Elements are
 * unobserved once shown: this is an entrance, not a state.
 *
 * Honours `prefers-reduced-motion` by revealing immediately — the CSS also
 * flattens the transition, but an element must never be left invisible if the
 * observer never fires.
 */

const prefersReducedMotion = () =>
  typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

let observer = null;

function ensureObserver() {
  if (observer || typeof IntersectionObserver === 'undefined') return observer;
  observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add('is-in');
        observer.unobserve(entry.target);
      }
    },
    { rootMargin: '0px 0px -12% 0px', threshold: 0.08 },
  );
  return observer;
}

export const revealDirective = {
  mounted(el, binding) {
    el.classList.add('aw-reveal');
    if (binding.value?.delay) el.style.transitionDelay = `${binding.value.delay}ms`;

    const io = ensureObserver();
    if (!io || prefersReducedMotion()) {
      el.classList.add('is-in');
      return;
    }
    io.observe(el);
  },
  unmounted(el) {
    observer?.unobserve(el);
  },
};
