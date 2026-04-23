import React, { useState, useEffect } from 'react'
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { updatePhotoLocation } from '../api'
import LocationSearch from './LocationSearch'

const pinIcon = new L.Icon({
  iconUrl:   'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-violet.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25,41], iconAnchor: [12,41],
})

function ClickPicker({ onPick }) {
  useMapEvents({ click: e => onPick(e.latlng.lat, e.latlng.lng) })
  return null
}

export default function EditLocationModal({ photo, onClose, onSaved }) {
  const [lat, setLat] = useState(String(photo.latitude ?? ''))
  const [lng, setLng] = useState(String(photo.longitude ?? ''))
  const [saving, setSaving] = useState(false)
  const [error,  setError]  = useState('')

  const numLat = parseFloat(lat)
  const numLng = parseFloat(lng)
  const valid  = !isNaN(numLat) && !isNaN(numLng) && numLat >= -90 && numLat <= 90 && numLng >= -180 && numLng <= 180

  const handlePick = (la, ln) => {
    setLat(la.toFixed(6))
    setLng(ln.toFixed(6))
    setError('')
  }

  const handleSave = async () => {
    if (!valid) { setError('Enter valid coordinates.'); return }
    setSaving(true)
    try {
      await updatePhotoLocation(photo.id, numLat, numLng)
      onSaved()
      onClose()
    } catch { setError('Failed to save. Try again.') }
    setSaving(false)
  }

  // close on Escape
  useEffect(() => {
    const fn = e => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', fn)
    return () => window.removeEventListener('keydown', fn)
  }, [onClose])

  const center = valid ? [numLat, numLng] : [37.7749, -122.4194]

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={e => e.stopPropagation()}>

        {/* Header */}
        <div className="modal-header">
          <div>
            <div className="modal-title">Edit Location</div>
            <div className="modal-sub">Click the map to move the pin, or type coordinates</div>
          </div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        {/* Photo info strip */}
        <div className="modal-photo-strip">
          <img src={photo.image_url} alt="" className="modal-thumb"
            onError={e => { e.target.src='https://via.placeholder.com/48x48/f5f5f4/a8a29e?text=📷' }} />
          <div>
            <div className="modal-photo-name">{photo.profile_name}</div>
            <div className="modal-photo-time">🕐 {new Date(photo.timestamp).toLocaleString()}</div>
          </div>
          <span className={`badge badge-${photo.service_type}`} style={{marginLeft:'auto'}}>{photo.service_type}</span>
        </div>

        {/* Map */}
        <div className="modal-map">
          <MapContainer center={center} zoom={13} style={{height:'100%',width:'100%'}}>
            <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="© OpenStreetMap" />
            <ClickPicker onPick={handlePick} />
            <LocationSearch onPick={handlePick} />
            {valid && <Marker position={[numLat, numLng]} icon={pinIcon} />}
          </MapContainer>
          <div className="modal-map-hint">👆 Click map · or search above</div>
        </div>

        {/* Coordinate inputs */}
        <div className="modal-coords">
          <div className="modal-coord-field">
            <label>Latitude</label>
            <input
              type="number"
              step="any"
              value={lat}
              onChange={e => { setLat(e.target.value); setError('') }}
              placeholder="-90 to 90"
            />
          </div>
          <div className="modal-coord-field">
            <label>Longitude</label>
            <input
              type="number"
              step="any"
              value={lng}
              onChange={e => { setLng(e.target.value); setError('') }}
              placeholder="-180 to 180"
            />
          </div>
        </div>

        {error && <div className="modal-error">✕ {error}</div>}

        {/* Actions */}
        <div className="modal-actions">
          <button className="btn btn-outline" onClick={onClose}>Cancel</button>
          <button className="btn btn-green" onClick={handleSave} disabled={!valid || saving}>
            {saving ? <><div className="spinner" style={{width:13,height:13,borderTopColor:'#fff'}}/>Saving…</> : '✓ Save location'}
          </button>
        </div>

      </div>
    </div>
  )
}
