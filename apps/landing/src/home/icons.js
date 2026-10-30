/*! @license
 * Icon geometry from Lucide (https://lucide.dev), ISC License.
 * Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part
 * of Feather (MIT). All other copyright (c) for Lucide are held by Lucide
 * Contributors 2022. Permission to use, copy, modify, and/or distribute this
 * software for any purpose with or without fee is hereby granted, provided that
 * the above copyright notice and this permission notice appear in all copies.
 * The full notice is in src/enterprise/icons.js.
 */

/**
 * The homepage's icons: one library, one stroke, 24-unit grid (Hallmark,
 * imagery § 8). A string is a path; an object is a rect or circle.
 */
const rect = (x, y, width, height, rx) => ({ el: 'rect', x, y, width, height, rx });
const circle = (cx, cy, r) => ({ el: 'circle', cx, cy, r });

export const ICONS = Object.freeze({
  check: ['M20 6 9 17l-5-5'],
  x: ['M18 6 6 18', 'm6 6 12 12'],
  minus: ['M5 12h14'],
  globe: [circle(12, 12, 10), 'M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20', 'M2 12h20'],
  'tablet-smartphone': [rect(3, 8, 10, 14, 2), 'M5 4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2h-2.4', 'M8 18h.01'],
  smartphone: [rect(5, 2, 14, 20, 2), 'M12 18h.01'],
  monitor: [rect(2, 3, 20, 14, 2), 'M8 21h8', 'M12 17v4'],
  terminal: ['m4 17 6-6-6-6', 'M12 19h8'],
  laptop: [
    'M18 5a2 2 0 0 1 2 2v8.526a2 2 0 0 0 .212.897l1.068 2.127a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45l1.068-2.127A2 2 0 0 0 4 15.526V7a2 2 0 0 1 2-2z',
    'M20.054 15.987H3.946',
  ],
  pause: [rect(14, 4, 4, 16, 1), rect(6, 4, 4, 16, 1)],
  play: ['M6 3 20 12 6 21Z'],
  copy: [rect(8, 8, 14, 14, 2), 'M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2'],
  menu: ['M4 6h16', 'M4 12h16', 'M4 18h16'],
  plus: ['M5 12h14', 'M12 5v14'],
});

/** Which icon each platform row wears. */
export const PLATFORM_ICON = Object.freeze({
  web: 'globe',
  ios: 'tablet-smartphone',
  android: 'smartphone',
  windows: 'monitor',
  linux: 'terminal',
  macos: 'laptop',
});
