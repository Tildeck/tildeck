<script setup lang="ts">
// One waiting state for the whole panel: a quiet ring and the word, in the
// middle of whatever room the page gives it. Screen readers hear it once,
// politely, instead of a silent blank screen.
const props = defineProps<{ label?: string }>()
const { t } = useI18n()
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-3 py-16 text-sm text-muted"
    role="status"
  >
    <svg
      width="26"
      height="26"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      class="spinner"
    >
      <circle
        cx="12"
        cy="12"
        r="9"
        stroke="rgb(var(--color-line))"
        stroke-width="3"
      />
      <path
        d="M12 3a9 9 0 0 1 9 9"
        stroke="rgb(var(--color-brand))"
        stroke-width="3"
        stroke-linecap="round"
      />
    </svg>
    {{ props.label || t('common.loading') }}
  </div>
</template>

<style scoped>
@media (prefers-reduced-motion: no-preference) {
  .spinner { animation: spin 0.9s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
}
</style>
