import { getMileage, pingMileage } from './api'

const KEY = 'mileage_tracking'
const listeners = new Set()

let tracking = localStorage.getItem(KEY) === '1'
let watchId = null
let lastPing = 0
let snapshot = { total_miles: 0, today_miles: 0, week_miles: 0 }

function email() {
  try {
    return (JSON.parse(localStorage.getItem('geo_user')) || {}).email || ''
  } catch {
    return ''
  }
}

function day() {
  const n = new Date()
  const m = String(n.getMonth() + 1).padStart(2, '0')
  const d = String(n.getDate()).padStart(2, '0')
  return `${n.getFullYear()}-${m}-${d}`
}

function emit() {
  listeners.forEach((fn) => fn({ tracking, ...snapshot }))
}

async function send(pos, on) {
  const data = await pingMileage({
    email: email(),
    tracking: on,
    day: day(),
    ...(pos
      ? { latitude: pos.coords.latitude, longitude: pos.coords.longitude }
      : {}),
  })
  snapshot = {
    total_miles: data.total_miles || 0,
    today_miles: data.today_miles || 0,
    week_miles: data.week_miles || 0,
  }
  emit()
}

function onPosition(pos) {
  const now = Date.now()
  if (now - lastPing < 8000) return
  lastPing = now
  send(pos, true).catch(() => {})
}

function watch() {
  if (watchId != null || !navigator.geolocation) return
  watchId = navigator.geolocation.watchPosition(onPosition, () => {}, {
    enableHighAccuracy: true,
    maximumAge: 5000,
  })
}

function unwatch() {
  if (watchId == null || !navigator.geolocation) return
  navigator.geolocation.clearWatch(watchId)
  watchId = null
}

export function mileageState() {
  return { tracking, ...snapshot }
}

export function subscribeMileage(fn) {
  listeners.add(fn)
  fn(mileageState())
  return () => listeners.delete(fn)
}

export async function refreshMileage() {
  try {
    const data = await getMileage(email())
    snapshot = {
      total_miles: data.total_miles || 0,
      today_miles: data.today_miles || 0,
      week_miles: data.week_miles || 0,
    }
    emit()
  } catch {
    /* keep last numbers */
  }
}

export async function setMileageTracking(on) {
  tracking = on
  localStorage.setItem(KEY, on ? '1' : '0')
  emit()
  if (on) {
    watch()
  } else {
    unwatch()
    lastPing = 0
    try { await send(null, false) } catch { /* offline */ }
  }
}

if (tracking) watch()
refreshMileage()
