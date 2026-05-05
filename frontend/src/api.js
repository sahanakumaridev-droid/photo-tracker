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
export const createProfile    = (data)     => api.post('/profiles', data, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data).then(r => { invalidate('profiles'); return r })
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
