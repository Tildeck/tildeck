// Dates and sizes in the panel's language.
export function useFormat() {
  const { locale, t } = useI18n()

  function date(value: string | null | undefined): string {
    if (!value) return t('common.never')
    return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  }

  function bytes(value: number): string {
    const units = ['byte', 'kilobyte', 'megabyte', 'gigabyte']
    let n = value
    let unit = 0
    while (n >= 1024 && unit < units.length - 1) {
      n /= 1024
      unit++
    }
    return new Intl.NumberFormat(locale.value, {
      style: 'unit',
      unit: units[unit],
      unitDisplay: 'short',
      maximumFractionDigits: unit === 0 ? 0 : 1,
    }).format(n)
  }

  function count(value: number): string {
    return new Intl.NumberFormat(locale.value).format(value)
  }

  return { date, bytes, count }
}
