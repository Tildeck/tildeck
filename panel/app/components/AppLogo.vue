<script setup lang="ts">
// The product mark: a tilde drawn as one stroke on a rounded tile, the deck
// it sits on. The geometry is identical to public/favicon.svg, so the mark in
// the interface and the mark in the browser tab never drift apart. The mark
// is decorative: the product name next to it carries the accessible name.
// On the desk band the tile takes the bright accent so it stands out from
// the dark band; elsewhere it is the deep brand tile.
withDefaults(defineProps<{ size?: number, variant?: 'brand' | 'desk' }>(), { size: 28, variant: 'brand' })
</script>

<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 32 32"
    fill="none"
    aria-hidden="true"
    focusable="false"
  >
    <rect
      :class="variant === 'desk' ? 'fill-desk-bright' : 'fill-brand'"
      width="32"
      height="32"
      rx="8"
    />
    <path
      :class="variant === 'desk' ? 'stroke-desk' : 'stroke-brand-contrast'"
      stroke-width="3.6"
      stroke-linecap="round"
      d="M7.5 18.5c1.6-3.8 4.4-5 7-2.5s5.4 1.3 7-2.5"
    />
  </svg>
</template>
