<script setup lang="ts">
// Confirmation before an action that cannot be undone or that locks someone
// out. The native dialog traps focus and closes on Escape.
const props = defineProps<{ open: boolean, title: string, body: string, confirmLabel: string, danger?: boolean, busy?: boolean }>()
const emit = defineEmits<{ confirm: [], cancel: [] }>()
const { t } = useI18n()
const dialog = ref<HTMLDialogElement | null>(null)

watch(() => props.open, (open) => {
  if (open) dialog.value?.showModal()
  else dialog.value?.close()
})
</script>

<template>
  <dialog
    ref="dialog"
    class="card w-[min(28rem,calc(100vw-2rem))] p-6 text-ink backdrop:bg-black/50"
    @cancel.prevent="emit('cancel')"
  >
    <h2 class="text-lg font-bold">
      {{ title }}
    </h2>
    <p class="mt-2 text-sm leading-relaxed text-muted">
      {{ body }}
    </p>
    <div class="mt-6 flex justify-end gap-2">
      <button
        type="button"
        class="btn btn-quiet"
        :disabled="busy"
        @click="emit('cancel')"
      >
        {{ t('common.cancel') }}
      </button>
      <button
        type="button"
        class="btn"
        :class="danger ? 'btn-danger' : 'btn-primary'"
        :disabled="busy"
        @click="emit('confirm')"
      >
        {{ busy ? t('common.working') : confirmLabel }}
      </button>
    </div>
  </dialog>
</template>
