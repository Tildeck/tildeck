<script setup lang="ts">
// The activity log, newest first. Append-only on the server; secret values
// were replaced by a marker when they were written.
const { t, te } = useI18n()
const { call } = useAdmin()
const { date } = useFormat()
const errorText = useErrorText()
useHead({ title: () => t('nav.activity') })

interface Entry {
  id: number
  at: string
  actor: string
  source: 'user' | 'admin' | 'system'
  action: string
  entity: string
  entity_id: string | null
  old_value: string | null
  new_value: string | null
}
interface Page { entries: Entry[], more: boolean }

const entries = ref<Entry[]>([])
const more = ref(false)
const loading = ref(false)
const error = ref('')

async function load(reset = false) {
  loading.value = true
  error.value = ''
  try {
    const before = reset || !entries.value.length ? '' : `&before=${entries.value[entries.value.length - 1]!.id}`
    const page = await call<Page>(`/activity?limit=50${before}`)
    entries.value = reset ? page.entries : [...entries.value, ...page.entries]
    more.value = page.more
  }
  catch (e) {
    error.value = errorText(e)
  }
  finally {
    loading.value = false
  }
}

onMounted(() => load(true))

function action(entry: Entry): string {
  return te(`activity.actions.${entry.action}`) ? t(`activity.actions.${entry.action}`) : entry.action
}

function detail(entry: Entry): string {
  if (entry.entity === 'setting' && entry.entity_id) {
    const name = te(`settings.keys.${entry.entity_id}.label`) ? t(`settings.keys.${entry.entity_id}.label`) : entry.entity_id
    return t('activity.settingChange', { name, value: entry.new_value ?? '' })
  }
  return entry.new_value ?? entry.old_value ?? ''
}

const sourceClass: Record<Entry['source'], string> = {
  admin: 'bg-brand/10 text-brand',
  user: 'bg-tint text-muted',
  system: 'bg-line text-muted',
}
</script>

<template>
  <div class="mx-auto flex max-w-5xl flex-col gap-6 px-4 py-8 lg:px-6 lg:py-10">
    <header class="flex items-end justify-between gap-4">
      <div>
        <h1 class="text-3xl font-extrabold tracking-tight">
          {{ t('activity.title') }}
        </h1>
        <p class="mt-2 max-w-2xl text-muted">
          {{ t('activity.intro') }}
        </p>
      </div>
      <button
        type="button"
        class="btn btn-quiet shrink-0"
        :disabled="loading"
        @click="load(true)"
      >
        {{ t('activity.refresh') }}
      </button>
    </header>

    <AppLoading v-if="loading && !entries.length" />
    <AppError
      v-else-if="error && !entries.length"
      :message="error"
      @retry="load(true)"
    />
    <p
      v-else-if="!entries.length"
      class="card p-8 text-center text-muted"
    >
      {{ t('activity.empty') }}
    </p>

    <ol
      v-else
      class="card divide-y divide-line"
    >
      <li
        v-for="entry in entries"
        :key="entry.id"
        class="flex flex-col gap-1 px-4 py-3 sm:flex-row sm:items-center sm:gap-4"
      >
        <span class="shrink-0 text-xs text-muted sm:w-44">{{ date(entry.at) }}</span>
        <span
          class="badge w-fit shrink-0"
          :class="sourceClass[entry.source]"
        >{{ t(`activity.sources.${entry.source}`) }}</span>
        <div class="min-w-0 flex-1">
          <span class="font-semibold">{{ action(entry) }}</span>
          <span
            v-if="detail(entry)"
            class="ms-2 break-all text-sm text-muted"
          >{{ detail(entry) }}</span>
        </div>
        <span
          class="shrink-0 truncate text-xs text-muted sm:max-w-[14rem]"
          dir="ltr"
        >{{ entry.actor }}</span>
      </li>
    </ol>

    <div
      v-if="more"
      class="flex justify-center"
    >
      <button
        type="button"
        class="btn btn-quiet"
        :disabled="loading"
        @click="load()"
      >
        {{ loading ? t('common.working') : t('activity.more') }}
      </button>
    </div>
  </div>
</template>
