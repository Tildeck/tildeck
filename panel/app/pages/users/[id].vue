<script setup lang="ts">
// One account: its metadata and devices, and what an administrator can do
// about it. Disabling stops every device at once and can be undone;
// deleting removes the account, its devices, and its records for good.
const { t } = useI18n()
const route = useRoute()
const { call } = useAdmin()
const { date, bytes, count } = useFormat()
const errorText = useErrorText()

interface DeviceRow { id: string, name: string, status: 'pending' | 'active' | 'revoked', created_at: string, last_seen_at: string | null }
interface UserDetail {
  id: string
  email: string
  email_verified: boolean
  disabled: boolean
  created_at: string
  last_seen_at: string | null
  devices: number
  records: number
  storage_bytes: number
  locale: string
  device_list: DeviceRow[]
}

const id = computed(() => String(route.params.id))
const { data: user, error, status, refresh } = useAsyncData(
  () => `admin-user-${id.value}`,
  () => call<UserDetail>(`/users/${id.value}`),
  { server: false },
)
useHead({ title: () => user.value?.email ?? t('nav.users') })

type Pending = { kind: 'disable' | 'enable' | 'delete' } | { kind: 'revoke', device: DeviceRow }
const pending = ref<Pending | null>(null)
const busy = ref(false)
const actionError = ref('')

const dialog = computed(() => {
  const p = pending.value
  if (!p || !user.value) return null
  const email = user.value.email
  switch (p.kind) {
    case 'disable': return { title: t('user.disableTitle', { email }), body: t('user.disableBody'), label: t('user.disable'), danger: true }
    case 'enable': return { title: t('user.enableTitle', { email }), body: t('user.enableBody'), label: t('user.enable'), danger: false }
    case 'delete': return { title: t('user.deleteTitle', { email }), body: t('user.deleteBody'), label: t('user.delete'), danger: true }
    case 'revoke': return { title: t('user.revokeTitle', { device: p.device.name }), body: t('user.revokeBody'), label: t('user.revoke'), danger: true }
  }
  return null
})

async function run() {
  const p = pending.value
  if (!p) return
  busy.value = true
  actionError.value = ''
  try {
    if (p.kind === 'revoke') await call(`/devices/${p.device.id}/revoke`, { method: 'POST' })
    else if (p.kind === 'delete') await call(`/users/${id.value}`, { method: 'DELETE' })
    else await call(`/users/${id.value}/${p.kind}`, { method: 'POST' })
    pending.value = null
    if (p.kind === 'delete') await navigateTo('/users')
    else await refresh()
  }
  catch (e) {
    actionError.value = errorText(e)
    pending.value = null
  }
  finally {
    busy.value = false
  }
}

const statusClass: Record<DeviceRow['status'], string> = {
  active: 'bg-success/10 text-success',
  pending: 'bg-warning/10 text-warning',
  revoked: 'bg-line text-muted',
}
</script>

<template>
  <div class="mx-auto flex max-w-5xl flex-col gap-6 px-4 py-8 lg:px-6 lg:py-10">
    <NuxtLink
      to="/users"
      class="text-sm font-medium text-muted hover:text-brand"
    >
      <span
        class="inline-block rtl:rotate-180"
        aria-hidden="true"
      >&larr;</span> {{ t('user.back') }}
    </NuxtLink>

    <AppLoading v-if="status === 'pending' && !user" />
    <AppError
      v-else-if="error || !user"
      :message="errorText(error)"
      @retry="refresh"
    />

    <template v-else>
      <header class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <h1
            class="break-all text-2xl font-extrabold tracking-tight lg:text-3xl"
            dir="ltr"
          >
            {{ user.email }}
          </h1>
          <div class="mt-2 flex flex-wrap items-center gap-2 text-sm text-muted">
            <UserStatus :user="user" />
            <span>{{ t('users.created', { date: date(user.created_at) }) }}</span>
          </div>
        </div>
        <div class="flex shrink-0 gap-2">
          <button
            v-if="user.disabled"
            type="button"
            class="btn btn-quiet"
            @click="pending = { kind: 'enable' }"
          >
            {{ t('user.enable') }}
          </button>
          <button
            v-else
            type="button"
            class="btn btn-quiet"
            @click="pending = { kind: 'disable' }"
          >
            {{ t('user.disable') }}
          </button>
          <button
            type="button"
            class="btn btn-danger"
            @click="pending = { kind: 'delete' }"
          >
            {{ t('user.delete') }}
          </button>
        </div>
      </header>

      <p
        v-if="actionError"
        class="text-sm text-danger"
        role="alert"
      >
        {{ actionError }}
      </p>

      <section
        class="grid gap-4 sm:grid-cols-4"
        :aria-label="t('user.summary')"
      >
        <div
          v-for="item in [
            { label: t('users.devices'), value: count(user.devices) },
            { label: t('users.records'), value: count(user.records) },
            { label: t('users.storage'), value: bytes(user.storage_bytes) },
            { label: t('users.lastSeen'), value: date(user.last_seen_at) },
          ]"
          :key="item.label"
          class="card flex flex-col gap-1 p-4"
        >
          <span class="text-xs font-medium uppercase tracking-wide text-muted">{{ item.label }}</span>
          <span class="num text-lg font-bold">{{ item.value }}</span>
        </div>
      </section>

      <section class="flex flex-col gap-3">
        <h2 class="text-xl font-bold">
          {{ t('user.devicesTitle') }}
        </h2>
        <p
          v-if="!user.device_list.length"
          class="card p-6 text-center text-muted"
        >
          {{ t('user.noDevices') }}
        </p>
        <ul
          v-else
          class="card divide-y divide-line"
        >
          <li
            v-for="device in user.device_list"
            :key="device.id"
            class="flex flex-wrap items-center gap-3 px-4 py-3"
          >
            <div class="min-w-0 flex-1">
              <div class="font-semibold">
                {{ device.name }}
              </div>
              <div class="text-xs text-muted">
                {{ t('user.deviceSeen', { created: date(device.created_at), seen: date(device.last_seen_at) }) }}
              </div>
            </div>
            <span
              class="badge"
              :class="statusClass[device.status]"
            >{{ t(`user.deviceStatus.${device.status}`) }}</span>
            <button
              v-if="device.status !== 'revoked'"
              type="button"
              class="btn btn-quiet px-3 py-1.5"
              @click="pending = { kind: 'revoke', device }"
            >
              {{ t('user.revoke') }}
            </button>
          </li>
        </ul>
      </section>
    </template>

    <ConfirmDialog
      :open="!!dialog"
      :title="dialog?.title ?? ''"
      :body="dialog?.body ?? ''"
      :confirm-label="dialog?.label ?? ''"
      :danger="dialog?.danger"
      :busy="busy"
      @confirm="run"
      @cancel="pending = null"
    />
  </div>
</template>
