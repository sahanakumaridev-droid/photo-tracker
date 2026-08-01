/** Hardcoded process-serving company configurations.
 *  Profiles store a company `id` (slug). Keep company-specific logic here.
 */

export const PRIORITY = {
  STANDARD: 'standard',
  NEXT_DAY: 'next_day',
  ASAP: 'asap',
}

export const COMPANIES = [
  {
    id: 'first_legal',
    name: 'First Legal',
    email: 'sdprocess@firstlegal.com',
    attempts_for_diligence: 6,
    payout_schedule: [10, 25],
    pay_rate_structure: {
      standard: '1st 3 attempts $18, $6.50/attempt after',
      next_day: '1st 3 attempts $23.50, $8/attempt after',
      asap: '1st attempt $40, $20/attempt after',
    },
    time_intervals: {
      morning: { start: '7:00 AM', end: '8:00 AM' },
      midday:  { start: '11:00 AM', end: '4:00 PM' },
      evening: { start: '5:30 PM', end: '10:00 PM' },
    },
    available_priority_levels: ['standard', 'next_day', 'asap'],
  },
  {
    id: 'rockstar',
    name: 'Rockstar Process Serving',
    email: 'rockstarlegal.sean@gmail.com',
    attempts_for_diligence: 4,
    payout_schedule: [1, 15],
    pay_rate_structure: {
      standard: '$50',
      next_day: '$60',
      asap: '$70',
    },
    time_intervals: {
      morning: { start: '7:00 AM', end: '10:00 AM' },
      midday:  { start: '11:00 AM', end: '4:00 PM' },
      evening: { start: '6:00 PM', end: '10:00 PM' },
    },
    available_priority_levels: ['standard', 'next_day', 'asap'],
  },
  {
    id: 'knox',
    name: 'Knox Attorney Service',
    email: 'sdprocess@knoxservices.com',
    attempts_for_diligence: 5,
    // [31, 2] ⇒ start Jul 31 2026, every 2 weeks (schedule[0] > schedule[1]).
    payout_schedule: [31, 2],
    pay_rate_structure: {
      standard: '$30',
      asap: '$50',
    },
    time_intervals: {
      morning: { start: '7:00 AM', end: '8:30 AM' },
      midday:  { start: '11:00 AM', end: '4:00 PM' },
      evening: { start: '5:30 PM', end: '10:00 PM' },
    },
    available_priority_levels: ['standard', 'asap'],
  },
]

export const DEFAULT_COMPANY_ID = 'first_legal'

export function getCompany(id) {
  if (!id) return null
  return COMPANIES.find(c => c.id === id) || null
}

export function companyOrDefault(id) {
  return getCompany(id) || getCompany(DEFAULT_COMPANY_ID)
}

export function prioritiesForCompany(companyId, allCategories) {
  const company = getCompany(companyId)
  const allowed = company
    ? company.available_priority_levels
    : ['standard', 'next_day', 'asap']
  return (allCategories || []).filter(c => allowed.includes(c.value))
}

export function defaultPriorityForCompany(companyId) {
  const company = companyOrDefault(companyId)
  const levels = company.available_priority_levels || []
  if (levels.includes('standard')) return 'standard'
  return levels[0] || 'standard'
}
