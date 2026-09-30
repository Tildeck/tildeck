// The signed-in administrator and the one way to call the admin API.
//
// The session lives in an HttpOnly cookie the panel never sees; the server
// hands out the CSRF token, which every change sends back. A 401 means the
// session ended (30 idle minutes, 12 hours, or signed out elsewhere): the
// panel forgets it and goes to the sign-in page.

export interface AdminSession {
  username: string
  csrf_token: string
}

/** A refusal with the server's stable error code. */
export class AdminApiError extends Error {
  constructor(public status: number, public code: string | null, public key: string | null = null) {
    super(code ?? `HTTP ${status}`)
  }
}

export function useAdmin() {
  const session = useState<AdminSession | null>('admin-session', () => null)
  const checked = useState<boolean>('admin-checked', () => false)

  async function call<T>(path: string, options: { method?: string, body?: unknown } = {}): Promise<T> {
    const method = options.method ?? 'GET'
    const headers: Record<string, string> = {}
    if (method !== 'GET' && session.value) headers['X-CSRF-Token'] = session.value.csrf_token
    try {
      return await $fetch<T>(`/api/admin${path}`, { method: method as 'GET', body: options.body as Record<string, unknown>, headers, credentials: 'same-origin' })
    }
    catch (e: unknown) {
      const err = e as { status?: number, statusCode?: number, data?: { error?: string, key?: string } }
      const status = err.status ?? err.statusCode ?? 0
      if (status === 401 && session.value && !path.startsWith('/session')) {
        session.value = null
        await navigateTo('/signin')
      }
      throw new AdminApiError(status, err.data?.error ?? null, err.data?.key ?? null)
    }
  }

  /** Learns whether a session is open; once per page load. */
  async function check(): Promise<AdminSession | null> {
    if (!checked.value) {
      try {
        session.value = await call<AdminSession>('/session')
      }
      catch {
        session.value = null
      }
      checked.value = true
    }
    return session.value
  }

  async function signIn(username: string, password: string, code: string) {
    session.value = await call<AdminSession>('/session', { method: 'POST', body: { username, password, code } })
    checked.value = true
  }

  function signedIn(value: AdminSession) {
    session.value = value
    checked.value = true
  }

  async function signOut() {
    try {
      await call('/session', { method: 'DELETE' })
    }
    finally {
      session.value = null
      await navigateTo('/signin')
    }
  }

  return { session, call, check, signIn, signedIn, signOut }
}

/** The localized message for a failed call. */
export function useErrorText() {
  const { t, te } = useI18n()
  return (e: unknown) => {
    const code = e instanceof AdminApiError ? e.code : null
    if (code && te(`errors.${code}`)) return t(`errors.${code}`)
    if (e instanceof AdminApiError && e.status === 0) return t('common.loadFailed')
    return t('errors.unknown')
  }
}
