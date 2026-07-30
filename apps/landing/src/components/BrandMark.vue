<script setup>
/** The app's own mark: a white check on the azure→indigo tile (brand_mark.dart). */
defineProps({ size: { type: Number, default: 36 } });
</script>

<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 64 64"
    role="img"
    aria-label="AllisWell"
    focusable="false"
  >
    <defs>
      <linearGradient :id="`awmark-${size}`" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="#2563EB" />
        <stop offset="100%" stop-color="#6D3DEB" />
      </linearGradient>
    </defs>
    <rect width="64" height="64" rx="16" :fill="`url(#awmark-${size})`" />
    <path
      d="M18 33.5 27.5 43 46 22"
      fill="none"
      stroke="#fff"
      stroke-width="6.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  </svg>
</template>
