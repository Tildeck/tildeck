<script setup lang="ts">
// Every account with its metadata. The panel never sees a vault's contents:
// counts and sizes are all there is.
const { t } = useI18n()
const { call } = useAdmin()
const { date, bytes, count } = useFormat()
useHead({ title: () => t('nav.users') })

interface UserRow {
  id: string
  email: string
  email_verified: boolean
  disabled: boolean
  created_at: string
  last_seen_at: string | null
  devices: number
  records: number
  storage_bytes: number
}

const { data: users, error, status, refresh } = useAsyncData('admin-users', () => call<UserRow[]>('/users'), { server: false })
const query = ref('')
const shown = computed(() => {
  const q = query.value.trim().toLowerCase()
  return (users.value ?? []).filter(u => !q || u.email.includes(q))
})
</script>

<template>
  <div class="mx-auto flex max-w-6xl flex-col gap-6 px-4 py-8 lg:px-6 lg:py-10">
    <header class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 class="text-3xl font-extrabold tracking-tight">
          {{ t('users.title') }}
        </h1>
        <p class="mt-2 max-w-2xl text-muted">
          {{ t('users.intro') }}
        </p>
      </div>
      <input
        v-model="query"
        type="search"
        class="field sm:max-w-xs"
        dir="ltr"
        :placeholder="t('users.search')"
        :aria-label="t('users.search')"
      >
    </header>

    <AppLoading v-if="status === 'pending' && !users" />
    <AppError
      v-else-if="error"
      @retry="refresh"
    />
    <p
      v-else-if="!shown.length"
      class="card p-8 text-center text-muted"
    >
      {{ users?.length ? t('users.noMatch') : t('users.empty') }}
    </p>

    <!-- Narrow screens: one card per account instead of a wide table. -->
    <template v-else>
      <ul class="card divide-y divide-line sm:hidden">
        <li
          v-for="user in shown"
          :key="user.id"
        >
          <NuxtLink
            :to="`/users/${user.id}`"
            class="flex flex-col gap-1.5 px-4 py-3 hover:bg-tint/60"
          >
            <div class="flex items-start justify-between gap-3">
              <span
                class="min-w-0 break-all font-semibold"
                dir="ltr"
              >{{ user.email }}</span>
              <UserStatus :user="user" />
            </div>
            <span class="text-xs text-muted">
              {{ t('users.deviceCount', user.devices) }}, {{ t('users.itemCount', user.records) }}
              · <span class="num">{{ bytes(user.storage_bytes) }}</span>
            </span>
            <span class="text-xs text-muted">{{ t('users.lastSeen') }}: {{ date(user.last_seen_at) }}</span>
          </NuxtLink>
        </li>
      </ul>

      <div class="card hidden overflow-x-auto sm:block">
        <table class="w-full min-w-[44rem] text-sm">
          <thead class="border-b border-line text-start text-xs uppercase tracking-wide text-muted">
            <tr>
              <th class="px-4 py-3 text-start font-medium">
                {{ t('users.email') }}
              </th>
              <th class="px-4 py-3 text-start font-medium">
                {{ t('users.status') }}
              </th>
              <th class="px-4 py-3 text-end font-medium">
                {{ t('users.devices') }}
              </th>
              <th class="px-4 py-3 text-end font-medium">
                {{ t('users.records') }}
              </th>
              <th class="px-4 py-3 text-end font-medium">
                {{ t('users.storage') }}
              </th>
              <th class="px-4 py-3 text-start font-medium">
                {{ t('users.lastSeen') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="user in shown"
              :key="user.id"
              class="border-b border-line last:border-0 hover:bg-tint/60"
            >
              <td class="px-4 py-3">
                <NuxtLink
                  :to="`/users/${user.id}`"
                  class="font-semibold text-ink hover:text-brand"
                  dir="ltr"
                >{{ user.email }}</NuxtLink>
                <div class="text-xs text-muted">
                  {{ t('users.created', { date: date(user.created_at) }) }}
                </div>
              </td>
              <td class="px-4 py-3">
                <UserStatus :user="user" />
              </td>
              <td class="num px-4 py-3 text-end">
                {{ count(user.devices) }}
              </td>
              <td class="num px-4 py-3 text-end">
                {{ count(user.records) }}
              </td>
              <td class="px-4 py-3 text-end">
                <span class="num">{{ bytes(user.storage_bytes) }}</span>
              </td>
              <td class="px-4 py-3 text-muted">
                {{ date(user.last_seen_at) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
