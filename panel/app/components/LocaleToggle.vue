<script setup lang="ts">
// Switches to the other locale. The label is that language's own name, taken
// from its own locale file (`shell.nativeName`), so every language is named
// in its own script without that text living anywhere else. Locale files load
// lazily, so the other one is fetched first; until it arrives the short code
// from the locale list stands in.
const { t, te, locale, locales, setLocale } = useI18n()
const { $i18n } = useNuxtApp()
const other = computed(() => locales.value.find(l => l.code !== locale.value))

// Message loading is not reactive for `te`, so record which locale has
// arrived and let the label depend on that.
const loaded = ref<string | null>(null)
watch(other, async (next) => {
  if (!next) return
  await $i18n.loadLocaleMessages(next.code)
  loaded.value = next.code
}, { immediate: true })

const label = computed(() => {
  const code = other.value?.code
  if (!code) return ''
  if (loaded.value === code && te('shell.nativeName', code)) return t('shell.nativeName', {}, { locale: code })
  return (other.value as { shortName?: string }).shortName ?? code.toUpperCase()
})
</script>

<template>
  <button
    v-if="other"
    type="button"
    :lang="other.language"
    @click="setLocale(other.code)"
  >
    {{ label }}
  </button>
</template>
