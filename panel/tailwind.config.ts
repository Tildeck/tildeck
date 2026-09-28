import type { Config } from 'tailwindcss'

// Design tokens live in assets/css/tailwind.css as CSS variables with a
// light and a dark value each; Tailwind only names them. No purple.
export default <Partial<Config>>{
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        page: 'rgb(var(--color-page) / <alpha-value>)',
        surface: 'rgb(var(--color-surface) / <alpha-value>)',
        line: 'rgb(var(--color-line) / <alpha-value>)',
        tint: 'rgb(var(--color-tint) / <alpha-value>)',
        ink: 'rgb(var(--color-ink) / <alpha-value>)',
        muted: 'rgb(var(--color-muted) / <alpha-value>)',
        brand: {
          DEFAULT: 'rgb(var(--color-brand) / <alpha-value>)',
          bright: 'rgb(var(--color-brand-bright) / <alpha-value>)',
          contrast: 'rgb(var(--color-brand-contrast) / <alpha-value>)',
        },
        success: 'rgb(var(--color-success) / <alpha-value>)',
        warning: 'rgb(var(--color-warning) / <alpha-value>)',
        danger: 'rgb(var(--color-danger) / <alpha-value>)',
        desk: {
          DEFAULT: 'rgb(var(--color-desk) / <alpha-value>)',
          ink: 'rgb(var(--color-desk-ink) / <alpha-value>)',
          muted: 'rgb(var(--color-desk-muted) / <alpha-value>)',
          bright: 'rgb(var(--color-desk-bright) / <alpha-value>)',
        },
      },
      fontFamily: {
        sans: ['Heebo', 'system-ui', 'sans-serif'],
      },
    },
  },
}
