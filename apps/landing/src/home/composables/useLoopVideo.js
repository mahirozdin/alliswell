import { onBeforeUnmount, onMounted, ref } from 'vue';

/**
 * Play a muted loop only while it is on screen (ADR-0061).
 *
 * The markup ships a poster picture and a `<video>` with no source and no
 * `autoplay`, so nothing is downloaded until the loop scrolls into view, and
 * a reader who asked for reduced motion, or for less data, only ever gets
 * the picture. Leaving the screen, hiding the tab or pressing the pause
 * button stops it; a paused loop stays paused until pressed again.
 *
 * Everything that touches the browser happens in onMounted, so the server
 * render and the first client render are the same markup.
 */
let observer = null;
const handlers = new WeakMap();

function shared() {
  if (!observer) {
    observer = new IntersectionObserver(
      (entries) => entries.forEach((e) => handlers.get(e.target)?.(e.isIntersecting)),
      { threshold: 0.35 },
    );
  }
  return observer;
}

export function useLoopVideo(src) {
  const video = ref(null);
  const playing = ref(false);
  const paused = ref(false);
  const enabled = ref(false);
  let visible = false;
  let motion = null;

  const play = () => {
    const el = video.value;
    if (!el || paused.value || !enabled.value || document.hidden) return;
    if (!el.getAttribute('src')) el.setAttribute('src', src);
    el.muted = true;
    el.play().catch(() => {});
  };
  const stop = () => video.value?.pause();

  const onVisibility = () => (document.hidden ? stop() : visible && play());
  const onMotion = () => {
    enabled.value = !motion.matches;
    if (enabled.value) {
      if (visible) play();
    } else stop();
  };

  onMounted(() => {
    const el = video.value;
    if (!el || !src) return;
    motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const saveData = navigator.connection?.saveData === true;
    enabled.value = !motion.matches && !saveData;
    motion.addEventListener('change', onMotion);
    el.addEventListener('playing', () => (playing.value = true));
    el.addEventListener('pause', () => (playing.value = false));
    handlers.set(el, (isVisible) => {
      visible = isVisible;
      if (isVisible) play();
      else stop();
    });
    shared().observe(el);
    document.addEventListener('visibilitychange', onVisibility);
  });

  onBeforeUnmount(() => {
    if (video.value) {
      shared().unobserve(video.value);
      handlers.delete(video.value);
    }
    motion?.removeEventListener('change', onMotion);
    document.removeEventListener('visibilitychange', onVisibility);
  });

  const toggle = () => {
    paused.value = !paused.value;
    if (paused.value) stop();
    else play();
  };

  return { video, playing, paused, enabled, toggle };
}
