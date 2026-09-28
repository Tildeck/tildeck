<script setup lang="ts">
// One icon button: shows the mode a click switches to. The icon is the
// message; the accessible name carries the words.
const colorMode = useColorMode()
const { t } = useI18n()
const isDark = computed(() => colorMode.value === 'dark')
const label = computed(() => t(isDark.value ? 'shell.theme.light' : 'shell.theme.dark'))
</script>

<template>
  <button
    type="button"
    :aria-label="label"
    :title="label"
    @click="colorMode.preference = isDark ? 'light' : 'dark'"
  >
    <svg
      v-if="isDark"
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      aria-hidden="true"
    >
      <circle
        cx="12"
        cy="12"
        r="4.5"
      />
      <path d="M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M18.7 5.3l-1.8 1.8M7.1 16.9l-1.8 1.8" />
    </svg>
    <svg
      v-else
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11Z" />
    </svg>
  </button>
</template>
