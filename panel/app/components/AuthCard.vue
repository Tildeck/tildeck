<script setup lang="ts">
// The frame of the pages before sign-in: one centered card on the page.
defineProps<{ title: string, intro?: string }>()
</script>

<template>
  <div class="flex min-h-full items-start justify-center px-4 py-10 lg:py-16">
    <div class="card w-full max-w-md p-6 shadow-sm sm:p-8">
      <AppLogo :size="40" />
      <h1 class="mt-5 text-2xl font-extrabold tracking-tight">
        {{ title }}
      </h1>
      <p
        v-if="intro"
        class="mt-2 text-sm leading-relaxed text-muted"
      >
        {{ intro }}
      </p>
      <div class="mt-6">
        <slot />
      </div>
    </div>
  </div>
</template>
