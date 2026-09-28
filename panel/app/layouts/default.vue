<script setup lang="ts">
// The desk: one dark band across the top carries the brand, the areas, and
// the operator controls. Everything below is the work surface of the current
// area, full width. Later phases add areas (users, devices, settings,
// activity) and the signed-in administrator.
const { t } = useI18n()
const route = useRoute()

const areas = computed(() => [
  { to: '/', label: t('nav.overview'), on: route.path === '/' },
])

// Which build is running. Quiet, at the bottom, but there: after an upgrade
// it is the fastest way to see that the new version is really up.
const version = useRuntimeConfig().public.version

// On small screens the areas and controls sit behind a menu button;
// navigating closes it so the content is what the operator lands on.
const menuOpen = ref(false)
watch(() => route.fullPath, () => {
  menuOpen.value = false
})

const control = 'rounded-md border border-desk-ink/25 px-2 py-0.5 text-xs text-desk-muted transition-colors hover:text-desk-ink focus-visible:outline focus-visible:outline-2 focus-visible:outline-desk-bright'
</script>

<template>
  <div class="flex h-svh flex-col overflow-hidden bg-page text-ink">
    <header class="flex h-14 shrink-0 items-center gap-3 bg-desk px-4 text-desk-ink lg:px-6 xl:gap-5">
      <NuxtLink
        to="/"
        class="flex shrink-0 items-center gap-2.5 text-lg font-extrabold tracking-tight"
      >
        <AppLogo
          :size="26"
          variant="desk"
        />{{ t('app.name') }}
      </NuxtLink>

      <nav
        class="hidden h-full items-stretch lg:flex"
        :aria-label="t('shell.areas')"
      >
        <NuxtLink
          v-for="area in areas"
          :key="area.to"
          :to="area.to"
          class="flex items-center whitespace-nowrap border-y-[3px] border-transparent px-3 text-sm font-medium transition-colors"
          :class="area.on ? 'border-b-desk-bright text-white' : 'text-desk-muted hover:text-white'"
          :aria-current="area.on ? 'page' : undefined"
        >
          {{ area.label }}
        </NuxtLink>
      </nav>

      <div class="ms-auto hidden items-center gap-2 lg:flex">
        <LocaleToggle :class="control" />
        <ThemeToggle :class="control + ' p-1'" />
      </div>

      <button
        type="button"
        class="ms-auto rounded-lg border border-desk-ink/25 p-2 lg:hidden"
        :aria-label="t('shell.menu')"
        :aria-expanded="menuOpen"
        aria-controls="shell-menu"
        @click="menuOpen = !menuOpen"
      >
        <svg
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          aria-hidden="true"
        >
          <path
            v-if="menuOpen"
            d="M6 6l12 12M18 6L6 18"
          />
          <path
            v-else
            d="M4 7h16M4 12h16M4 17h16"
          />
        </svg>
      </button>
    </header>

    <div
      v-if="menuOpen"
      id="shell-menu"
      class="shrink-0 border-t border-desk-ink/10 bg-desk px-4 pb-4 pt-2 text-desk-ink lg:hidden"
    >
      <nav
        class="flex flex-col"
        :aria-label="t('shell.areas')"
      >
        <NuxtLink
          v-for="area in areas"
          :key="area.to"
          :to="area.to"
          class="border-s-[3px] px-3 py-2 text-sm font-medium"
          :class="area.on ? 'border-desk-bright text-white' : 'border-transparent text-desk-muted'"
          :aria-current="area.on ? 'page' : undefined"
        >
          {{ area.label }}
        </NuxtLink>
      </nav>
      <div class="mt-3 flex items-center justify-end gap-1.5 px-3">
        <LocaleToggle :class="control" />
        <ThemeToggle :class="control + ' p-1'" />
      </div>
    </div>

    <main class="app-scroll min-h-0 min-w-0 flex-1">
      <slot />
    </main>

    <footer class="flex shrink-0 justify-end px-4 py-1 text-[11px] text-muted lg:px-6">
      <span>{{ t('shell.version') }} <span class="num">{{ version }}</span></span>
    </footer>
  </div>
</template>
