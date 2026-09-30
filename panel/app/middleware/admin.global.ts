// Every page but setup and sign-in needs a signed-in administrator. A server
// without administrators sends everyone to first-run setup.

const PUBLIC = new Set(['/setup', '/signin'])

export default defineNuxtRouteMiddleware(async (to) => {
  const { check } = useAdmin()
  const setupNeeded = useState<boolean | null>('admin-setup-needed', () => null)

  if (setupNeeded.value === null || setupNeeded.value) {
    try {
      setupNeeded.value = (await $fetch<{ needed: boolean }>('/api/admin/setup')).needed
    }
    catch {
      // The server did not answer: let the page show its own error.
      return
    }
  }
  if (setupNeeded.value) return to.path === '/setup' ? undefined : navigateTo('/setup')
  if (to.path === '/setup') return navigateTo('/signin')

  const session = await check()
  if (!session && !PUBLIC.has(to.path)) return navigateTo('/signin')
  if (session && to.path === '/signin') return navigateTo('/')
})
