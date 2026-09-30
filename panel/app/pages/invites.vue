<script setup lang="ts">
// Invitations: one email address each, single use, seven days. The code is
// shown once, right after creating it; with email configured, the server
// also sends it. Registering with it confirms the address.
const { t, locale } = useI18n()
const { call } = useAdmin()
const { date } = useFormat()
const errorText = useErrorText()
useHead({ title: () => t('nav.invites') })

interface InviteRow { id: string, email: string, created_by: string, created_at: string, expires_at: string, status: 'open' | 'used' | 'revoked' | 'expired' }
interface Created { id: string, email: string, code: string, expires_at: string, emailed: boolean }

const { data: invites, error, status, refresh } = useAsyncData('admin-invites', () => call<InviteRow[]>('/invites'), { server: false })
const email = ref('')
const busy = ref(false)
const formError = ref('')
const created = ref<Created | null>(null)
const copied = ref(false)
const revoking = ref<InviteRow | null>(null)
const revokeBusy = ref(false)

async function create() {
  busy.value = true
  formError.value = ''
  created.value = null
  copied.value = false
  try {
    created.value = await call<Created>('/invites', { method: 'POST', body: { email: email.value.trim(), locale: locale.value } })
    email.value = ''
    await refresh()
  }
  catch (e) {
    formError.value = errorText(e)
  }
  finally {
    busy.value = false
  }
}

async function copy() {
  if (!created.value) return
  await navigator.clipboard.writeText(created.value.code)
  copied.value = true
}

async function revoke() {
  if (!revoking.value) return
  revokeBusy.value = true
  try {
    await call(`/invites/${revoking.value.id}/revoke`, { method: 'POST' })
    await refresh()
  }
  catch (e) {
    formError.value = errorText(e)
  }
  finally {
    revokeBusy.value = false
    revoking.value = null
  }
}

const statusClass: Record<InviteRow['status'], string> = {
  open: 'bg-success/10 text-success',
  used: 'bg-tint text-muted',
  revoked: 'bg-line text-muted',
  expired: 'bg-warning/10 text-warning',
}
</script>

<template>
  <div class="mx-auto flex max-w-4xl flex-col gap-6 px-4 py-8 lg:px-6 lg:py-10">
    <header>
      <h1 class="text-3xl font-extrabold tracking-tight">
        {{ t('invites.title') }}
      </h1>
      <p class="mt-2 max-w-2xl text-muted">
        {{ t('invites.intro') }}
      </p>
    </header>

    <form
      class="card flex flex-col gap-3 p-4 sm:flex-row sm:items-end"
      @submit.prevent="create"
    >
      <div class="flex-1">
        <label
          class="label"
          for="invite-email"
        >{{ t('invites.email') }}</label>
        <input
          id="invite-email"
          v-model="email"
          type="email"
          class="field"
          dir="ltr"
          autocomplete="off"
          required
        >
      </div>
      <button
        type="submit"
        class="btn btn-primary"
        :disabled="busy"
      >
        {{ busy ? t('common.working') : t('invites.create') }}
      </button>
    </form>
    <p
      v-if="formError"
      class="text-sm text-danger"
      role="alert"
    >
      {{ formError }}
    </p>

    <section
      v-if="created"
      class="card flex flex-col gap-3 border-brand p-5"
      role="status"
    >
      <h2 class="font-bold">
        {{ t('invites.createdTitle', { email: created.email }) }}
      </h2>
      <div class="flex flex-wrap items-center gap-3">
        <code class="num select-all rounded-lg bg-tint px-3 py-2 font-mono text-lg">{{ created.code }}</code>
        <button
          type="button"
          class="btn btn-quiet"
          @click="copy"
        >
          {{ copied ? t('invites.copied') : t('invites.copy') }}
        </button>
      </div>
      <p class="text-sm text-muted">
        {{ created.emailed ? t('invites.emailed') : t('invites.notEmailed') }}
        {{ t('invites.onceOnly', { date: date(created.expires_at) }) }}
      </p>
    </section>

    <AppLoading v-if="status === 'pending' && !invites" />
    <AppError
      v-else-if="error"
      @retry="refresh"
    />
    <p
      v-else-if="!invites?.length"
      class="card p-8 text-center text-muted"
    >
      {{ t('invites.empty') }}
    </p>
    <ul
      v-else
      class="card divide-y divide-line"
    >
      <li
        v-for="invite in invites"
        :key="invite.id"
        class="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:gap-3"
      >
        <div class="min-w-0 flex-1">
          <div
            class="break-all font-semibold"
            dir="ltr"
          >
            {{ invite.email }}
          </div>
          <div class="text-xs text-muted">
            {{ t('invites.meta', { by: invite.created_by, created: date(invite.created_at), expires: date(invite.expires_at) }) }}
          </div>
        </div>
        <div class="flex items-center gap-3">
          <span
            class="badge"
            :class="statusClass[invite.status]"
          >{{ t(`invites.status.${invite.status}`) }}</span>
          <button
            v-if="invite.status === 'open'"
            type="button"
            class="btn btn-quiet ms-auto px-3 py-1.5 sm:ms-0"
            @click="revoking = invite"
          >
            {{ t('invites.revoke') }}
          </button>
        </div>
      </li>
    </ul>

    <ConfirmDialog
      :open="!!revoking"
      :title="t('invites.revokeTitle', { email: revoking?.email ?? '' })"
      :body="t('invites.revokeBody')"
      :confirm-label="t('invites.revoke')"
      danger
      :busy="revokeBusy"
      @confirm="revoke"
      @cancel="revoking = null"
    />
  </div>
</template>
