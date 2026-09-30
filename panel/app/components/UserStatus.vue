<script setup lang="ts">
// An account's state in one badge: disabled wins, then an unconfirmed
// address (it cannot sync yet), then active.
defineProps<{ user: { disabled: boolean, email_verified: boolean } }>()
const { t } = useI18n()
</script>

<template>
  <span
    v-if="user.disabled"
    class="badge bg-danger/10 text-danger"
  >{{ t('users.disabled') }}</span>
  <span
    v-else-if="!user.email_verified"
    class="badge bg-warning/10 text-warning"
  >{{ t('users.unconfirmed') }}</span>
  <span
    v-else
    class="badge bg-success/10 text-success"
  >{{ t('users.active') }}</span>
</template>
