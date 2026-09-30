<script setup lang="ts">
// Every server setting, where its value comes from, and a way to change it.
// A value set in the environment wins and locks the field here. Secret
// values never come back from the server: the field only says one is set.
const { t } = useI18n()
const { call } = useAdmin()
const errorText = useErrorText()
useHead({ title: () => t('nav.settings') })

interface SettingRow {
  key: string
  secret: boolean
  kind: 'text' | 'choice'
  choices: string[] | null
  locked: boolean
  origin: 'env' | 'database' | 'default'
  configured: boolean
  value?: string | null
}

const GROUPS: { id: string, keys: string[] }[] = [
  { id: 'general', keys: ['public_url', 'registration_mode'] },
  { id: 'email', keys: ['smtp_host', 'smtp_port', 'smtp_security', 'smtp_username', 'smtp_password', 'smtp_from'] },
  { id: 'security', keys: ['device_idle_days', 'signin_limit_per_account', 'signin_limit_per_address'] },
]
const LTR = new Set(['public_url', 'smtp_host', 'smtp_port', 'smtp_username', 'smtp_password', 'smtp_from', 'device_idle_days', 'signin_limit_per_account', 'signin_limit_per_address'])

const { data: rows, error, status, refresh } = useAsyncData('admin-settings', () => call<SettingRow[]>('/settings'), { server: false })
const drafts = reactive<Record<string, string>>({})
const saving = ref<string | null>(null)
const results = reactive<Record<string, { ok: boolean, text: string } | undefined>>({})

watch(rows, (list) => {
  for (const row of list ?? []) drafts[row.key] = row.secret ? '' : (row.value ?? '')
}, { immediate: true })

const byKey = computed(() => Object.fromEntries((rows.value ?? []).map(r => [r.key, r])))

function changed(row: SettingRow): boolean {
  return row.secret ? drafts[row.key] !== '' : drafts[row.key] !== (row.value ?? '')
}

async function save(row: SettingRow) {
  saving.value = row.key
  results[row.key] = undefined
  try {
    await call(`/settings/${row.key}`, { method: 'PUT', body: { value: drafts[row.key] } })
    results[row.key] = { ok: true, text: t('settings.saved') }
    await refresh()
  }
  catch (e) {
    results[row.key] = { ok: false, text: errorText(e) }
  }
  finally {
    saving.value = null
  }
}

function origin(row: SettingRow): string {
  if (row.locked) return t('settings.origin.env')
  if (row.origin === 'database') return t('settings.origin.database')
  return row.configured ? t('settings.origin.default') : t('settings.origin.unset')
}
</script>

<template>
  <div class="mx-auto flex max-w-4xl flex-col gap-8 px-4 py-8 lg:px-6 lg:py-10">
    <header>
      <h1 class="text-3xl font-extrabold tracking-tight">
        {{ t('settings.title') }}
      </h1>
      <p class="mt-2 max-w-2xl text-muted">
        {{ t('settings.intro') }}
      </p>
    </header>

    <AppLoading v-if="status === 'pending' && !rows" />
    <AppError
      v-else-if="error"
      @retry="refresh"
    />

    <template v-else>
      <section
        v-for="group in GROUPS"
        :key="group.id"
        class="flex flex-col gap-3"
      >
        <h2 class="text-xl font-bold">
          {{ t(`settings.groups.${group.id}`) }}
        </h2>
        <div class="card divide-y divide-line">
          <template
            v-for="key in group.keys"
            :key="key"
          >
            <form
              v-if="byKey[key]"
              class="flex flex-col gap-3 p-4 sm:flex-row sm:items-start sm:gap-6"
              @submit.prevent="save(byKey[key]!)"
            >
              <div class="sm:w-2/5">
                <label
                  :for="`setting-${key}`"
                  class="font-semibold"
                >{{ t(`settings.keys.${key}.label`) }}</label>
                <p class="mt-1 text-xs leading-relaxed text-muted">
                  {{ t(`settings.keys.${key}.help`) }}
                </p>
              </div>
              <div class="flex flex-1 flex-col gap-2">
                <select
                  v-if="byKey[key]!.kind === 'choice'"
                  :id="`setting-${key}`"
                  v-model="drafts[key]"
                  class="field"
                  :disabled="byKey[key]!.locked"
                >
                  <option
                    v-for="choice in byKey[key]!.choices ?? []"
                    :key="choice"
                    :value="choice"
                  >
                    {{ t(`settings.choices.${key}.${choice}`) }}
                  </option>
                </select>
                <input
                  v-else
                  :id="`setting-${key}`"
                  v-model="drafts[key]"
                  class="field"
                  :type="byKey[key]!.secret ? 'password' : 'text'"
                  :dir="LTR.has(key) ? 'ltr' : undefined"
                  :disabled="byKey[key]!.locked"
                  :placeholder="byKey[key]!.secret && byKey[key]!.configured ? t('settings.secretSet') : ''"
                  autocomplete="off"
                  spellcheck="false"
                >
                <div class="flex flex-wrap items-center gap-3">
                  <span
                    class="badge"
                    :class="byKey[key]!.locked ? 'bg-warning/10 text-warning' : 'bg-tint text-muted'"
                  >{{ origin(byKey[key]!) }}</span>
                  <button
                    v-if="!byKey[key]!.locked"
                    type="submit"
                    class="btn btn-primary ms-auto px-3 py-1.5"
                    :disabled="!changed(byKey[key]!) || saving === key"
                  >
                    {{ saving === key ? t('common.working') : t('common.save') }}
                  </button>
                </div>
                <p
                  v-if="byKey[key]!.locked"
                  class="text-xs text-muted"
                >
                  {{ t('settings.lockedHelp') }}
                </p>
                <p
                  v-if="results[key]"
                  class="text-xs"
                  :class="results[key]!.ok ? 'text-success' : 'text-danger'"
                  role="status"
                >
                  {{ results[key]!.text }}
                </p>
              </div>
            </form>
          </template>
        </div>
      </section>
    </template>
  </div>
</template>
