<script setup lang="ts">
// Overview: what this server is and whether it can serve. Both answers come
// from the public health endpoints, so the page works before any sign-in
// exists. Readiness answers 503 with a stable error code when the database
// is down; that is a state to show, not a failed request.
const { t, te } = useI18n()
useHead({ title: () => t('nav.overview') })

interface ServerInfo { name: string, version: string, protocol_version: number }
interface Readiness { status: 'ok' | 'error', database: 'ok' | 'error', error?: string | null }

const { data: info, error: infoError, status: infoStatus, refresh: refreshInfo } = useFetch<ServerInfo>('/api/info', { server: false })
const { data: ready, status: readyStatus, refresh: refreshReady } = useFetch<Readiness>('/api/health/ready', {
  server: false,
  ignoreResponseError: true,
})

const loading = computed(() => infoStatus.value === 'pending' || readyStatus.value === 'pending')
const databaseOk = computed(() => ready.value?.database === 'ok')
const databaseMessage = computed(() => {
  if (databaseOk.value) return t('overview.database.ok')
  const code = ready.value?.error
  return code && te(`errors.${code}`) ? t(`errors.${code}`) : t('overview.database.unknown')
})

function retry() {
  refreshInfo()
  refreshReady()
}
</script>

<template>
  <div class="mx-auto flex max-w-5xl flex-col gap-8 px-4 py-8 lg:px-6 lg:py-12">
    <header class="flex flex-col gap-2">
      <h1 class="text-3xl font-extrabold tracking-tight lg:text-4xl">
        {{ t('overview.title') }}
      </h1>
      <p class="max-w-2xl text-muted">
        {{ t('overview.intro') }}
      </p>
    </header>

    <AppLoading v-if="loading && !info" />
    <AppError
      v-else-if="infoError"
      @retry="retry"
    />

    <section
      v-else
      class="grid gap-4 sm:grid-cols-3"
      :aria-label="t('overview.status')"
    >
      <div class="flex flex-col gap-2 rounded-2xl border border-line bg-surface p-5">
        <span class="text-xs font-medium uppercase tracking-wide text-muted">{{ t('overview.database.label') }}</span>
        <span class="flex items-center gap-2 text-lg font-bold">
          <i
            class="size-2.5 shrink-0 rounded-full"
            :class="databaseOk ? 'bg-success' : 'bg-danger'"
            aria-hidden="true"
          />
          {{ databaseOk ? t('overview.database.up') : t('overview.database.down') }}
        </span>
        <span class="text-sm text-muted">{{ databaseMessage }}</span>
      </div>

      <div class="flex flex-col gap-2 rounded-2xl border border-line bg-surface p-5">
        <span class="text-xs font-medium uppercase tracking-wide text-muted">{{ t('overview.version') }}</span>
        <span class="num text-3xl font-extrabold tracking-tight">{{ info?.version }}</span>
      </div>

      <div class="flex flex-col gap-2 rounded-2xl border border-line bg-surface p-5">
        <span class="text-xs font-medium uppercase tracking-wide text-muted">{{ t('overview.protocol') }}</span>
        <span class="num text-3xl font-extrabold tracking-tight">{{ info?.protocol_version }}</span>
      </div>
    </section>

    <nav
      class="grid gap-4 sm:grid-cols-3"
      :aria-label="t('shell.areas')"
    >
      <NuxtLink
        v-for="area in ['users', 'settings', 'activity']"
        :key="area"
        :to="`/${area}`"
        class="card group flex flex-col gap-1 p-5 transition-colors hover:border-brand"
      >
        <span class="font-bold group-hover:text-brand">{{ t(`nav.${area}`) }}</span>
        <span class="text-sm text-muted">{{ t(`overview.areas.${area}`) }}</span>
      </NuxtLink>
    </nav>
  </div>
</template>
