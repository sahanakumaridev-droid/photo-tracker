import axios from 'axios'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api'
})

// ── Simple in-memory + localStorage cache ──────────────────────────────────
const MEM = {}  // key → { data, ts }
const TTL = 30 * 1000  // 30 seconds before background refresh

function fromStorage(key) {
  try {
    const raw = localStorage.getItem(`cache_${key}`)
    if (!raw) return null
    const { data, ts } = JSON.parse(raw)
    return { data, ts }
  } catch { return null }
}

function toStorage(key, data) {
  try { localStorage.setItem(`cache_${key}`, JSON.stringify({ data, ts: Date.now() })) } catch {}
}

// Returns cached data immediately (if any), always fetches fresh in background
// onData(data, fromCache) called once with cache, then again with fresh data
async function cached(key, fetcher, onData) {
  // 1. Return from memory cache instantly
  if (MEM[key]) {
    onData(MEM[key].data, true)
  } else {
    // 2. Try localStorage
    const stored = fromStorage(key)
    if (stored) {
      MEM[key] = stored
      onData(stored.data, true)
    }
  }

  // 3. Fetch fresh if cache is stale or missing
  const age = MEM[key] ? Date.now() - MEM[key].ts : Infinity
  if (age > TTL || !MEM[key]) {
    const fresh = await fetcher()
    MEM[key] = { data: fresh, ts: Date.now() }
    toStorage(key, fresh)
    onData(fresh, false)
    return fresh
  }
  return MEM[key].data
}

// Invalidate cache keys after mutations
function invalidate(...keys) {
  keys.forEach(k => {
    delete MEM[k]
    try { localStorage.removeItem(`cache_${k}`) } catch {}
  })
}

// ── API calls ───────────────────────────────────────────────────────────────

// These return a promise AND call onData with cached data first
export const getPhotosLive   = (onData) => cached('photos',   () => api.get('/photos').then(r => r.data),   onData)
export const getProfilesLive = (onData) => cached('profiles', () => api.get('/profiles').then(r => r.data), onData)

// Standard promise-based (used where caching not needed)
export const getProfiles      = ()         => api.get('/profiles').then(r => r.data)
export const getCompanies     = ()         => api.get('/companies').then(r => r.data)
export const createProfile    = (data)     => {
  // Callers may pass FormData; backend expects JSON Body(...)
  const payload = data instanceof FormData
    ? {
        name: data.get('name'),
        service_type: data.get('service_type'),
        company: data.get('company') || undefined,
      }
    : data
  return api.post('/profiles', payload).then(r => r.data).then(r => { invalidate('profiles'); return r })
}
export const updateProfile    = (id, data) => api.patch(`/profiles/${id}`, data).then(r => r.data).then(r => { invalidate('profiles'); return r })
export const deleteProfile    = (id)       => api.delete(`/profiles/${id}`).then(r => r.data).then(r => { invalidate('profiles', 'photos'); return r })

export const getPhotos        = ()         => api.get('/photos').then(r => r.data)
export const getProfilePhotos = (id)       => api.get(`/profiles/${id}/photos`).then(r => r.data)
export const uploadPhoto      = (formData) => api.post('/upload', formData, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data).then(r => { invalidate('photos', 'profiles'); return r })
export const deletePhoto      = (id)       => api.delete(`/photos/${id}`).then(r => r.data).then(r => { invalidate('photos'); return r })
export const updatePhotoLocation = (id, lat, lng) => api.patch(`/photos/${id}/location`, { latitude: lat, longitude: lng }).then(r => r.data).then(r => { invalidate('photos'); return r })
export const updatePhotoNote     = (id, note)     => api.patch(`/photos/${id}/note`, { note }).then(r => r.data).then(r => { invalidate('photos'); return r })
export const updatePhotoProfiles = (id, profile_ids) => api.patch(`/photos/${id}/profiles`, { profile_ids }).then(r => r.data).then(r => { invalidate('photos'); return r })
export const replacePhotoImage   = (id, file) => { const fd = new FormData(); fd.append('file', file); return api.patch(`/photos/${id}/image`, fd, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data).then(r => { invalidate('photos'); return r }) }

export const getLog = (params) => api.get('/log', { params }).then(r => r.data)

export const exportLogEmail = (to, records) => api.post('/export/email', { to, records }).then(r => r.data)

// ── F1: master pins / attempt history ───────────────────────────────────────
export const getLocations      = (params)   => api.get('/locations', { params }).then(r => r.data)
export const getNearby         = (lat, lng, radius_ft = 100) => api.get('/locations/nearby', { params: { lat, lng, radius_ft } }).then(r => r.data)
export const getAttempts       = (groupId)  => api.get(`/locations/${groupId}/attempts`).then(r => r.data)

// ── F4: scheduling queues ────────────────────────────────────────────────────
export const getSchedule       = (queue)    => api.get('/schedule', { params: queue ? { queue } : {} }).then(r => r.data)

// ── F6: timestamp edit + audit ───────────────────────────────────────────────
export const editTimestamp     = (id, timestamp, user_id) => api.patch(`/photos/${id}/timestamp`, { timestamp, user_id }).then(r => r.data).then(r => { invalidate('photos'); return r })
export const getTimestampHistory = (id)     => api.get(`/photos/${id}/timestamp-history`).then(r => r.data)

// ── F7: pay rate ─────────────────────────────────────────────────────────────
export const updatePayRate     = (id, pay_rate) => api.patch(`/photos/${id}/pay-rate`, { pay_rate }).then(r => r.data).then(r => { invalidate('photos'); return r })

// ── F10: archive / status ────────────────────────────────────────────────────
export const updateStatus      = (id, status) => api.patch(`/photos/${id}/status`, { status }).then(r => r.data).then(r => { invalidate('photos'); return r })
export const getArchive        = (params)    => api.get('/archive', { params }).then(r => r.data)

// ── F8/F9: earnings + payouts ────────────────────────────────────────────────
export const getEarnings       = (period = 'today', user_id) => api.get('/earnings/summary', { params: { period, ...(user_id ? { user_id } : {}) } }).then(r => r.data)
export const getPayouts        = (user_id)   => api.get('/payouts', { params: user_id ? { user_id } : {} }).then(r => r.data)
export const finalizePayout    = (data)      => api.post('/payouts/finalize', data).then(r => r.data)

// ── F5: drafts ───────────────────────────────────────────────────────────────
export const saveDraft         = (data)      => api.put('/drafts', data).then(r => r.data)
export const getDrafts         = (user_id)   => api.get('/drafts', { params: user_id ? { user_id } : {} }).then(r => r.data)
export const deleteDraft       = (id)        => api.delete(`/drafts/${id}`).then(r => r.data)

// ── F11: saved recipients + Excel export ─────────────────────────────────────
export const getRecipients     = (user_id)   => api.get('/recipients', { params: user_id ? { user_id } : {} }).then(r => r.data)
export const addRecipient      = (data)      => api.post('/recipients', data).then(r => r.data)
export const editRecipient     = (id, data)  => api.patch(`/recipients/${id}`, data).then(r => r.data)
export const deleteRecipient   = (id)        => api.delete(`/recipients/${id}`).then(r => r.data)
// include_photo=true → manual (selected) export: one row per profile with the
// most recent photo embedded (watermarked). false → full-list export, no photo.
export const exportExcel       = (recipients, records, include_photo = false) => api.post('/export/excel', { recipients, records, include_photo }).then(r => r.data)

// Single-job "Service Record": detailed Excel (one row per attempt: ID, Date,
// Service, Address, Lat/Long, Status, Agent, Notes) + the photo(s) attached.
// Pass recipients:[] to get the .xlsx back as file_base64 for a local download.
// payload = { recipients, records, attachments, subject, body, base_name }
export const exportJobExcel    = (payload) => api.post('/export/job', payload).then(r => r.data)
