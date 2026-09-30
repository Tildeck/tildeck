<script setup lang="ts">
// Password and a code from the authenticator app. A wrong answer says only
// that the details are wrong, whichever part it was.
const { t } = useI18n()
const { signIn } = useAdmin()
const errorText = useErrorText()
useHead({ title: () => t('signin.title') })

const username = ref('')
const password = ref('')
const code = ref('')
const busy = ref(false)
const error = ref('')

async function submit() {
  busy.value = true
  error.value = ''
  try {
    await signIn(username.value.trim(), password.value, code.value)
    password.value = ''
    await navigateTo('/')
  }
  catch (e) {
    error.value = errorText(e)
    code.value = ''
  }
  finally {
    busy.value = false
  }
}
</script>

<template>
  <AuthCard
    :title="t('signin.title')"
    :intro="t('signin.intro')"
  >
    <form
      class="flex flex-col gap-4"
      @submit.prevent="submit"
    >
      <div>
        <label
          class="label"
          for="signin-username"
        >{{ t('auth.username') }}</label>
        <input
          id="signin-username"
          v-model="username"
          class="field"
          dir="ltr"
          autocomplete="username"
          required
        >
      </div>
      <div>
        <label
          class="label"
          for="signin-password"
        >{{ t('auth.password') }}</label>
        <input
          id="signin-password"
          v-model="password"
          type="password"
          class="field"
          dir="ltr"
          autocomplete="current-password"
          required
        >
      </div>
      <div>
        <label
          class="label"
          for="signin-code"
        >{{ t('auth.code') }}</label>
        <input
          id="signin-code"
          v-model="code"
          class="field num tracking-widest"
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
        {{ busy ? t('common.working') : t('signin.submit') }}
      </button>
    </form>
  </AuthCard>
</template>
