<script setup lang="ts">
// First-run setup: the one-time token from the server log, the first
// administrator's name and password, then a TOTP secret to enroll. The
// administrator exists only after a code from that secret is confirmed.
const { t } = useI18n()
const { call, signedIn } = useAdmin()
const errorText = useErrorText()
useHead({ title: () => t('setup.title') })

interface Enrollment { secret: string, uri: string, qr_image: string }

const token = ref('')
const username = ref('')
const password = ref('')
const confirm = ref('')
const code = ref('')
const enrollment = ref<Enrollment | null>(null)
const busy = ref(false)
const error = ref('')

const mismatch = computed(() => confirm.value.length > 0 && confirm.value !== password.value)
const qrSource = computed(() => enrollment.value?.qr_image.startsWith('data:image/svg+xml') ? enrollment.value.qr_image : '')
// The secret in groups of four, easier to type into an authenticator.
const secretGroups = computed(() => enrollment.value?.secret.match(/.{1,4}/g)?.join(' ') ?? '')

async function start() {
  if (password.value.length < 12) {
    error.value = t('setup.passwordShort')
    return
  }
  if (mismatch.value) return
  busy.value = true
  error.value = ''
  try {
    enrollment.value = await call<Enrollment>('/setup/start', {
      method: 'POST',
      body: { setup_token: token.value.trim(), username: username.value.trim(), password: password.value },
    })
  }
  catch (e) {
    error.value = errorText(e)
  }
  finally {
    busy.value = false
  }
}

async function complete() {
  busy.value = true
  error.value = ''
  try {
    const session = await call<{ username: string, csrf_token: string }>('/setup/complete', {
      method: 'POST',
      body: { setup_token: token.value.trim(), code: code.value },
    })
    signedIn(session)
    useState('admin-setup-needed').value = false
    password.value = ''
    confirm.value = ''
    await navigateTo('/')
  }
  catch (e) {
    error.value = errorText(e)
  }
  finally {
    busy.value = false
  }
}
</script>

<template>
  <AuthCard
    :title="t('setup.title')"
    :intro="enrollment ? t('setup.totpIntro') : t('setup.intro')"
  >
    <form
      v-if="!enrollment"
      class="flex flex-col gap-4"
      @submit.prevent="start"
    >
      <div>
        <label
          class="label"
          for="setup-token"
        >{{ t('setup.token') }}</label>
        <input
          id="setup-token"
          v-model="token"
          class="field num"
          autocomplete="off"
          spellcheck="false"
          required
        >
        <p class="mt-1.5 text-xs text-muted">
          {{ t('setup.tokenHelp') }}
        </p>
      </div>
      <div>
        <label
          class="label"
          for="setup-username"
        >{{ t('auth.username') }}</label>
        <input
          id="setup-username"
          v-model="username"
          class="field"
          dir="ltr"
          autocomplete="username"
          pattern="[A-Za-z0-9._@\-]{3,100}"
          :title="t('setup.usernameRule')"
          required
        >
      </div>
      <div>
        <label
          class="label"
          for="setup-password"
        >{{ t('auth.password') }}</label>
        <input
          id="setup-password"
          v-model="password"
          type="password"
          class="field"
          dir="ltr"
          autocomplete="new-password"
          required
        >
        <p class="mt-1.5 text-xs text-muted">
          {{ t('setup.passwordRule') }}
        </p>
      </div>
      <div>
        <label
          class="label"
          for="setup-confirm"
        >{{ t('setup.confirm') }}</label>
        <input
          id="setup-confirm"
          v-model="confirm"
          type="password"
          class="field"
          dir="ltr"
          autocomplete="new-password"
          required
          :aria-invalid="mismatch"
        >
        <p
          v-if="mismatch"
          class="mt-1.5 text-xs text-danger"
        >
          {{ t('setup.mismatch') }}
        </p>
      </div>
      <p
        v-if="error"
        class="text-sm text-danger"
        role="alert"
      >
        {{ error }}
      </p>
      <button
        type="submit"
        class="btn btn-primary"
        :disabled="busy"
      >
        {{ busy ? t('common.working') : t('setup.continue') }}
      </button>
    </form>

    <form
      v-else
      class="flex flex-col gap-4"
      @submit.prevent="complete"
    >
      <!-- An image, not inline markup: nothing from the response reaches the DOM as HTML. -->
      <img
        class="mx-auto w-48 rounded-xl border border-line bg-white p-2"
        :src="qrSource"
        :alt="t('setup.qr')"
      >
      <div>
        <p class="text-xs text-muted">
          {{ t('setup.secret') }}
        </p>
        <p class="num mt-1 select-all break-all rounded-lg bg-tint px-3 py-2 font-mono text-sm">
          {{ secretGroups }}
        </p>
      </div>
      <div>
        <label
          class="label"
          for="setup-code"
        >{{ t('auth.code') }}</label>
        <input
          id="setup-code"
          v-model="code"
          class="field num text-lg tracking-widest"
          inputmode="numeric"
          autocomplete="one-time-code"
          maxlength="6"
          required
        >
      </div>
      <p
        v-if="error"
        class="text-sm text-danger"
        role="alert"
      >
        {{ error }}
      </p>
      <button
        type="submit"
        class="btn btn-primary"
        :disabled="busy"
      >
        {{ busy ? t('common.working') : t('setup.finish') }}
      </button>
    </form>
  </AuthCard>
</template>
