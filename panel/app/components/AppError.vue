<script setup lang="ts">
// A failed fetch must never leave a blank screen: say that the data did not
// arrive and offer the one action that helps, another try.
withDefaults(defineProps<{ message?: string }>(), { message: '' })
const emit = defineEmits<{ retry: [] }>()
const { t } = useI18n()
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-3 py-16 text-center"
    role="alert"
  >
    <p class="max-w-sm text-sm text-muted">
      {{ message || t('common.loadFailed') }}
    </p>
    <button
      type="button"
      class="rounded-lg bg-ink px-4 py-1.5 text-sm font-medium text-surface transition-colors hover:bg-brand"
      @click="emit('retry')"
    >
      {{ t('common.retry') }}
    </button>
  </div>
</template>
