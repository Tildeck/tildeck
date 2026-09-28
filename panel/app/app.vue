<script setup lang="ts">
// Root shell: locale-driven lang and dir on <html>; everything else lives in
// the layout and pages.
const { locale, locales } = useI18n()
const dir = computed(() => locales.value.find(l => l.code === locale.value)?.dir ?? 'ltr')
useHead({
  htmlAttrs: { lang: locale, dir },
  titleTemplate: title => (title ? `${title} · Tildeck` : 'Tildeck'),
})
</script>

<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>
