import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// The repo-root VERSION file is the single version source. Docker builds
// cannot reach it, so they pass the same value as the APP_VERSION build
// argument (server/Dockerfile, the workflow scripts, the publish workflow).
function readVersion(): string {
  const fromEnv = (process.env.APP_VERSION || '').trim()
  if (fromEnv) return fromEnv
  const here = path.dirname(fileURLToPath(import.meta.url))
  try {
    return fs.readFileSync(path.resolve(here, '../VERSION'), 'utf-8').trim() || '0.0.0'
  }
  catch {
    return '0.0.0'
  }
}

// A static single-page app: `nuxt generate` writes .output/public, which the
// server image copies in and serves (server/app/panel.py). Cache and security
// headers are set by the server, not here.
export default defineNuxtConfig({
  modules: ['@nuxtjs/i18n', '@nuxtjs/tailwindcss', '@nuxtjs/color-mode', '@nuxt/eslint'],
  ssr: false,
  devtools: { enabled: false },
  app: {
    head: {
      // English LTR before hydration; app.vue keeps lang and dir in sync
      // with the active locale at runtime.
      htmlAttrs: { lang: 'en', dir: 'ltr' },
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'theme-color', content: '#13292d' },
        // An operator console: nothing here belongs in a search index.
        { name: 'robots', content: 'noindex, nofollow' },
      ],
      link: [
        { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' },
      ],
    },
  },
  colorMode: {
    classSuffix: '',
    // Follow the OS theme until the operator explicitly chooses; the choice
    // is stored and then always wins.
    preference: 'system',
    fallback: 'dark',
  },
  runtimeConfig: {
    public: {
      version: readVersion(),
    },
  },
  compatibilityDate: '2025-07-15',
  eslint: {
    config: { stylistic: true },
  },
  i18n: {
    locales: [
      { code: 'en', language: 'en-US', name: 'English', shortName: 'EN', file: 'en.json', dir: 'ltr' },
      { code: 'he', language: 'he-IL', name: 'Hebrew', shortName: 'HE', file: 'he.json', dir: 'rtl' },
    ],
    langDir: 'locales',
    defaultLocale: 'en',
    strategy: 'no_prefix',
    detectBrowserLanguage: {
      useCookie: true,
      cookieKey: 'tildeck_lang',
      redirectOn: 'root',
      alwaysRedirect: false,
      fallbackLocale: 'en',
    },
  },
  tailwindcss: {
    cssPath: '~/assets/css/tailwind.css',
  },
})
