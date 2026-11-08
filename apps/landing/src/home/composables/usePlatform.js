import { onMounted, ref } from 'vue';

import { platformOf } from '../platform.js';

/**
 * OPH-412: the visitor's platform, `desktop` until the page has hydrated.
 * The server cannot know the device, so the first client render agrees with
 * the HTML and the store button arrives one tick later (src/home/platform.js).
 */
export function usePlatform() {
  const platform = ref('desktop');
  onMounted(() => {
    platform.value = platformOf(navigator.userAgent, navigator.maxTouchPoints ?? 0);
  });
  return platform;
}
