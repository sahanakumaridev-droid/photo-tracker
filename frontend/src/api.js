import axios from 'axios'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api'
})

export const getProfiles      = ()         => api.get('/profiles').then(r => r.data)
export const createProfile    = (data)     => api.post('/profiles', data, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data)
export const updateProfile    = (id, data) => api.patch(`/profiles/${id}`, data).then(r => r.data)
export const deleteProfile    = (id)       => api.delete(`/profiles/${id}`).then(r => r.data)

export const getPhotos        = ()         => api.get('/photos').then(r => r.data)
export const getProfilePhotos = (id)       => api.get(`/profiles/${id}/photos`).then(r => r.data)
export const uploadPhoto      = (formData) => api.post('/upload', formData, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data)
export const deletePhoto      = (id)       => api.delete(`/photos/${id}`).then(r => r.data)
export const updatePhotoLocation = (id, lat, lng) => api.patch(`/photos/${id}/location`, { latitude: lat, longitude: lng }).then(r => r.data)
export const updatePhotoNote     = (id, note)     => api.patch(`/photos/${id}/note`, { note }).then(r => r.data)
export const updatePhotoProfiles = (id, profile_ids) => api.patch(`/photos/${id}/profiles`, { profile_ids }).then(r => r.data)

export const getLog = (params) => api.get('/log', { params }).then(r => r.data)
