import React, { useEffect, useState, useRef } from 'react'
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { getProfiles, uploadPhoto } from '../api'
import { useNavigate } from 'react-router-dom'
import LocationSearch from '../components/LocationSearch'

const pinIcon = new L.Icon({
  iconUrl:   'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-violet.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25,41], iconAnchor: [12,41], popupAnchor: [1,-34],
})

function MapPicker({ location, onPick }) {
  useMapEvents({ click: e => onPick(e.latlng.lat, e.latlng.lng) })
  return location ? <Marker position={[location.lat, location.lng]} icon={pinIcon} /> : null
}

export default function Upload({ showToast }) {
  const [profiles,  setProfiles]  = useState([])
  const [selected,  setSelected]  = useState(null)
  const [file,      setFile]      = useState(null)
  const [preview,   setPreview]   = useState(null)
  const [location,  setLocation]  = useState(null)
  const [locWarn,   setLocWarn]   = useState(null)
  const [locBusy,   setLocBusy]   = useState(false)
  const [uploading, setUploading] = useState(false)
  const [editMode,  setEditMode]  = useState(false)   // show map picker
  const [manualLat, setManualLat] = useState('')
  const [manualLng, setManualLng] = useState('')
  const fileRef = useRef()
  const navigate = useNavigate()

  useEffect(() => { getProfiles().then(setProfiles); grabLocation() }, [])

  // Keep manual inputs in sync with location state
  useEffect(() => {
    if (location) {
      setManualLat(location.lat.toFixed(6))
      setManualLng(location.lng.toFixed(6))
    }
  }, [location])

  const grabLocation = () => {
    setLocBusy(true); setLocWarn(null)
    if (!navigator.geolocation) {
      setLocWarn('Geolocation unavailable — using default.')
      setLocation({ lat: 37.7749, lng: -122.4194 })
      setLocBusy(false); return
    }
    navigator.geolocation.getCurrentPosition(
      p => { setLocation({ lat: p.coords.latitude, lng: p.coords.longitude }); setLocBusy(false) },
      () => {
        setLocWarn('GPS unavailable — using default location.')
        setLocation({ lat: 37.7749 + (Math.random()-.5)*.05, lng: -122.4194 + (Math.random()-.5)*.05 })
        setLocBusy(false)
      },
      { timeout: 8000 }
    )
  }

  const handleMapPick = (lat, lng) => {
    setLocation({ lat, lng })
    setLocWarn(null)
  }

  const handleManualApply = () => {
    const lat = parseFloat(manualLat)
    const lng = parseFloat(manualLng)
    if (isNaN(lat) || isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) return
    setLocation({ lat, lng })
    setLocWarn(null)
  }

  const pickFile = (f) => { setFile(f); setPreview(URL.createObjectURL(f)) }

  const handleUpload = async () => {
    if (!file || !selected || !location) return
    setUploading(true)
    const fd = new FormData()
    fd.append('file', file)
    fd.append('profile_id', selected.id)
    fd.append('latitude',   location.lat)
    fd.append('longitude',  location.lng)
    try {
      await uploadPhoto(fd)
      showToast('Photo uploaded')
      navigate('/')
    } catch { showToast('Upload failed', 'error') }
    setUploading(false)
  }

  const ready = file && selected && location && !uploading

  return (
    <div className="page">
      <div className="page-header">
        <div>
          <div className="page-title">Upload Photo</div>
          <div className="page-sub">Tag a photo with GPS location and profile</div>
        </div>
      </div>

      <div className="grid-2">
        {/* LEFT — profile */}
        <div>
          <div className="card">
            <div className="step-head">
              <div className="step-num">1</div>
              <div className="step-title">Select profile</div>
            </div>
            {profiles.length === 0
              ? <div className="loading" style={{padding:20}}><div className="spinner"/></div>
              : profiles.map(p => (
                  <div
                    key={p.id}
                    className={`profile-row ${selected?.id === p.id ? 'selected' : ''}`}
                    onClick={() => setSelected(p)}
                  >
                    <div className={`avatar av-${p.service_type}`}>{p.name.charAt(0)}</div>
                    <div style={{flex:1}}>
                      <div style={{fontWeight:700, fontSize:14}}>{p.name}</div>
                      <div style={{fontSize:11, color:'var(--text3)', marginTop:1}}>#{p.id}</div>
                    </div>
                    <span className={`badge badge-${p.service_type}`}>{p.service_type}</span>
                    {selected?.id === p.id && <span style={{fontWeight:800, color:'var(--text)', marginLeft:4}}>✓</span>}
                  </div>
                ))
            }
          </div>
        </div>

        {/* RIGHT */}
        <div>
          {/* Image */}
          <div className="card">
            <div className="step-head">
              <div className="step-num">2</div>
              <div className="step-title">Choose image</div>
            </div>
            <div
              className={`drop-zone ${file ? 'filled' : ''}`}
              onClick={() => fileRef.current.click()}
              onDrop={e => { e.preventDefault(); pickFile(e.dataTransfer.files[0]) }}
              onDragOver={e => e.preventDefault()}
            >
              {preview
                ? <img src={preview} alt="preview"/>
                : <><div className="drop-icon">🖼</div><div className="drop-title">Click or drag & drop</div><div className="drop-sub">PNG · JPG · WEBP</div></>
              }
            </div>
            <input ref={fileRef} type="file" accept="image/*" style={{display:'none'}}
              onChange={e => e.target.files[0] && pickFile(e.target.files[0])} />
            {file && (
              <button className="btn btn-outline" style={{fontSize:12, padding:'5px 12px'}}
                onClick={() => { setFile(null); setPreview(null); fileRef.current.value='' }}>
                ✕ Remove
              </button>
            )}
          </div>

          {/* Location */}
          <div className="card">
            <div className="step-head">
              <div className="step-num">3</div>
              <div className="step-title">Location & timestamp</div>
              <button
                className="btn btn-outline"
                style={{fontSize:12, padding:'5px 12px', marginLeft:'auto'}}
                onClick={() => setEditMode(v => !v)}
              >
                {editMode ? '✕ Close map' : '✏️ Edit location'}
              </button>
            </div>

            {/* GPS status */}
            {locBusy && <div className="loading" style={{padding:12}}><div className="spinner"/>Acquiring GPS…</div>}
            {location && (
              <div className={`loc-box ${locWarn ? 'warn' : ''}`}>
                <div className="loc-head">{locWarn ? '⚠ Fallback location' : '✓ GPS acquired'}</div>
                {locWarn && <div style={{fontSize:11, color:'var(--amber)', marginBottom:6}}>{locWarn}</div>}
                <div className="loc-row">📍 {location.lat.toFixed(6)}, {location.lng.toFixed(6)}</div>
                <div className="loc-row">🕐 {new Date().toLocaleString()}</div>
              </div>
            )}

            {/* Map picker */}
            {editMode && (
              <div className="upload-map-wrap">
                <div className="upload-map-hint">👆 Click the map to set location</div>
                <MapContainer
                  center={location ? [location.lat, location.lng] : [37.7749, -122.4194]}
                  zoom={13}
                  style={{height:'100%', width:'100%'}}
                >
                  <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="© OpenStreetMap" />
                  <MapPicker location={location} onPick={handleMapPick} />
                  <LocationSearch onPick={handleMapPick} />
                </MapContainer>
              </div>
            )}

            {/* Manual coordinate inputs */}
            {editMode && (
              <div className="manual-coords">
                <div className="manual-coord-field">
                  <label>Latitude</label>
                  <input
                    type="number" step="any"
                    value={manualLat}
                    onChange={e => setManualLat(e.target.value)}
                    placeholder="-90 to 90"
                    style={{marginBottom:0}}
                  />
                </div>
                <div className="manual-coord-field">
                  <label>Longitude</label>
                  <input
                    type="number" step="any"
                    value={manualLng}
                    onChange={e => setManualLng(e.target.value)}
                    placeholder="-180 to 180"
                    style={{marginBottom:0}}
                  />
                </div>
                <button className="btn btn-dark" style={{alignSelf:'flex-end', padding:'9px 16px', fontSize:13}} onClick={handleManualApply}>
                  Apply
                </button>
              </div>
            )}

            {!editMode && (
              <button className="btn btn-outline" style={{fontSize:12, padding:'6px 13px', marginTop:8}} onClick={grabLocation}>
                ↻ Refresh GPS
              </button>
            )}
          </div>

          <button
            className="btn btn-green"
            style={{width:'100%', padding:'14px', fontSize:15, fontWeight:700, borderRadius:10, justifyContent:'center'}}
            onClick={handleUpload}
            disabled={!ready}
          >
            {uploading
              ? <><div className="spinner" style={{width:15,height:15,borderTopColor:'#fff'}}/>Uploading…</>
              : '↑ Upload photo'
            }
          </button>

          {!ready && !uploading && (
            <div className="hint">
              {!selected && 'Select a profile'}
              {selected && !file && 'Choose an image'}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
