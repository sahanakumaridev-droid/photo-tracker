import React, { useEffect, useState, useRef, useContext } from 'react'
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { getProfiles, createProfile, uploadPhoto } from '../api'
import { useNavigate } from 'react-router-dom'
import LocationSearch from '../components/LocationSearch'
import { GeoContext } from '../context/GeoContext'

const pinIcon = new L.Icon({
  iconUrl:   'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-violet.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25,41], iconAnchor: [12,41], popupAnchor: [1,-34],
})

function MapPicker({ location, onPick }) {
  useMapEvents({ click: e => onPick(e.latlng.lat, e.latlng.lng) })
  return location ? <Marker position={[location.lat, location.lng]} icon={pinIcon} /> : null
}

// PST formatter
function toPST(isoString) {
  if (!isoString) return ''
  return new Date(isoString).toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }) + ' PST'
}

export default function Upload({ showToast }) {
  const geo = useContext(GeoContext)   // global geo from App

  const [profiles,     setProfiles]     = useState([])
  const [selected,     setSelected]     = useState(null)
  const [file,         setFile]         = useState(null)
  const [preview,      setPreview]      = useState(null)
  const [location,     setLocation]     = useState(null)
  const [locWarn,      setLocWarn]      = useState(null)
  const [locBusy,      setLocBusy]      = useState(false)
  const [uploading,    setUploading]    = useState(false)
  const [editMode,     setEditMode]     = useState(false)
  const [manualLat,    setManualLat]    = useState('')
  const [manualLng,    setManualLng]    = useState('')
  const [address,      setAddress]      = useState('')
  const [addrLoading,  setAddrLoading]  = useState(false)
  const [note,         setNote]         = useState('')
  // inline new profile
  const [showNewProf,  setShowNewProf]  = useState(false)
  const [newProfName,  setNewProfName]  = useState('')
  const [newProfSvc,   setNewProfSvc]   = useState('standard')
  const [creatingProf, setCreatingProf] = useState(false)

  const fileRef   = useRef()
  const navigate  = useNavigate()

  const loadProfiles = () => getProfiles().then(setProfiles)

  // Use global geo context first, then try to get fresh GPS
  useEffect(() => {
    loadProfiles()
    // If global geo already has location (from app load), use it immediately
    if (geo.location) {
      setLocation(geo.location)
      setLocWarn(null)
    } else {
      // Try to grab fresh GPS
      grabLocation()
    }
  }, [])

  // Keep location in sync with global geo context as it updates
  useEffect(() => {
    if (geo.location && !location) {
      setLocation(geo.location)
      setLocWarn(null)
    }
  }, [geo.location])

  useEffect(() => {
    if (location) {
      setManualLat(location.lat.toFixed(6))
      setManualLng(location.lng.toFixed(6))
      reverseGeocode(location.lat, location.lng)
    }
  }, [location])

  // Reverse geocode to get human-readable address
  const reverseGeocode = async (lat, lng) => {
    setAddrLoading(true)
    try {
      const res = await fetch(
        `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1&extratags=1&_t=${Date.now()}`,
        { headers: { 'Accept-Language': 'en' } }
      )
      const data = await res.json()
      if (data && data.display_name) {
        const a = data.address || {}
        const seen = new Set()
        const parts = []

        // Street
        const road = a.road || a.pedestrian || a.path
        if (road) {
          const street = a.house_number ? `${a.house_number} ${road}` : road
          parts.push(street)
          seen.add(street.toLowerCase())
        }

        // City
        const city = a.city || a.town || a.village || a.municipality
        if (city && !seen.has(city.toLowerCase())) {
          parts.push(city)
          seen.add(city.toLowerCase())
        }

        // State (abbreviation preferred)
        if (a.state_code || a.state) {
          const st = a.state_code || a.state
          if (!seen.has(st.toLowerCase())) parts.push(st)
        }

        // ZIP inline
        if (a.postcode) parts.push(a.postcode)

        setAddress(parts.join(', ') || data.display_name)
      }
    } catch { /* silent */ }
    setAddrLoading(false)
  }

  const grabLocation = () => {
    setLocBusy(true)
    setLocWarn(null)
    if (!navigator.geolocation) {
      setLocWarn('Geolocation not supported by this browser.')
      setLocBusy(false)
      return
    }
    navigator.geolocation.getCurrentPosition(
      pos => {
        setLocation({ lat: pos.coords.latitude, lng: pos.coords.longitude })
        setLocWarn(null)
        setLocBusy(false)
      },
      err => {
        setLocBusy(false)
        if (err.code === 1) {
          setLocWarn('Location permission denied. Please enable GPS in your browser settings.')
        } else {
          setLocWarn('GPS signal weak. Try moving to an open area or set location manually on the map.')
        }
        // Do NOT set any fallback coordinates
      },
      { timeout: 12000, enableHighAccuracy: true, maximumAge: 0 }
    )
  }

  const handleMapPick = (lat, lng) => {
    setLocation({ lat, lng })
    setLocWarn(null)
  }

  const handleManualApply = () => {
    const lat = parseFloat(manualLat), lng = parseFloat(manualLng)
    if (isNaN(lat) || isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) return
    setLocation({ lat, lng })
    setLocWarn(null)
  }

  const pickFile = (f) => { setFile(f); setPreview(URL.createObjectURL(f)) }

  // Create new profile inline
  const handleCreateProfile = async (e) => {
    e.preventDefault()
    if (!newProfName.trim()) return
    setCreatingProf(true)
    const fd = new FormData()
    fd.append('name', newProfName)
    fd.append('service_type', newProfSvc)
    try {
      const created = await createProfile(fd)
      await loadProfiles()
      setSelected(created)
      setShowNewProf(false)
      setNewProfName('')
      setNewProfSvc('standard')
      showToast('Profile created')
    } catch { showToast('Failed to create profile', 'error') }
    setCreatingProf(false)
  }

  const handleUpload = async () => {
    if (!file || !selected || !location) return
    setUploading(true)
    const fd = new FormData()
    fd.append('file',       file)
    fd.append('profile_id', selected.id)
    fd.append('latitude',   location.lat)
    fd.append('longitude',  location.lng)
    fd.append('address',    address)
    fd.append('note',       note)
    try {
      await uploadPhoto(fd)
      // Small delay to ensure backend has committed before dashboard re-fetches
      await new Promise(r => setTimeout(r, 300))
      showToast('Photo uploaded ✓')
      navigate('/')
    } catch { showToast('Upload failed', 'error') }
    setUploading(false)
  }

  const ready = file && selected && location && !uploading
  const stepsDone = [!!selected, !!file, !!location].filter(Boolean).length

  return (
    <div className="page upload-page" style={{display:'flex', flexDirection:'column', height:'100vh'}}>
      <div className="page-header">
        <div>
          <div className="page-title">Upload Photo</div>
          <div className="page-sub">Tag a photo with GPS location and profile</div>
        </div>
        <div className="upload-progress">
          <span className="upload-progress-label">
            {stepsDone === 3 ? 'Ready to upload' : 'Complete the steps'}
          </span>
          <div className="upload-progress-track">
            <div className="upload-progress-fill" style={{ width: `${(stepsDone/3)*100}%` }} />
          </div>
          <span className={`upload-progress-count ${stepsDone === 3 ? 'done' : ''}`}>{stepsDone}/3</span>
        </div>
      </div>

      <div style={{flex:1, overflowY:'auto', padding:'24px 32px'}}>
      <div className="grid-2">

        {/* LEFT — profile */}
        <div>
          <div className="card">
            <div className="step-head">
              <div className="step-num">1</div>
              <div className="step-title">Select profile</div>
              <button
                className="btn btn-outline"
                style={{fontSize:11, padding:'4px 10px', marginLeft:'auto'}}
                onClick={() => setShowNewProf(v => !v)}
              >
                {showNewProf ? '✕ Cancel' : '+ New Profile'}
              </button>
            </div>

            {/* Inline new profile form */}
            {showNewProf && (
              <form onSubmit={handleCreateProfile} style={{
                background:'rgba(99,102,241,0.08)', border:'1px solid rgba(99,102,241,0.2)',
                borderRadius:10, padding:'14px', marginBottom:12,
              }}>
                <label style={{marginBottom:4}}>Name</label>
                <input
                  value={newProfName}
                  onChange={e => setNewProfName(e.target.value)}
                  placeholder="e.g. Alice Johnson"
                  autoFocus required
                  style={{marginBottom:10}}
                />
                <label style={{marginBottom:4}}>Service Type</label>
                <div style={{display:'flex', gap:6, marginBottom:12}}>
                  {['standard','rush'].map(t => (
                    <button
                      key={t} type="button"
                      onClick={() => setNewProfSvc(t)}
                      className={`btn ${newProfSvc === t ? (t==='rush' ? 'btn-dark' : 'btn-green') : 'btn-outline'}`}
                      style={{fontSize:11, padding:'5px 12px', flex:1, justifyContent:'center'}}
                    >
                      {t === 'rush' ? '🔴 Rush' : '🟢 Standard'}
                    </button>
                  ))}
                </div>
                <button className="btn btn-dark" type="submit" disabled={creatingProf} style={{width:'100%', justifyContent:'center', fontSize:12}}>
                  {creatingProf ? 'Creating…' : '+ Create & Select'}
                </button>
              </form>
            )}

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
                      <div style={{fontSize:11, color:'rgba(100,100,120,0.6)', marginTop:1, fontFamily:'Geist Mono, monospace'}}>#{p.id}</div>
                    </div>
                    <span className={`badge badge-${p.service_type}`}>{p.service_type === 'rush' ? '🔴 ASAP' : '🟢 Standard'}</span>
                    {selected?.id === p.id && <span style={{fontWeight:800, color:'#a5b4fc', marginLeft:4}}>✓</span>}
                  </div>
                ))
            }
          </div>
        </div>

        {/* RIGHT */}
        <div>
          {/* Image — camera + gallery */}
          <div className="card">
            <div className="step-head">
              <div className="step-num">2</div>
              <div className="step-title">Choose image</div>
            </div>

            {/* Gallery button */}
            {!file && (
              <div style={{display:'flex', gap:8, marginBottom:12}}>
                <button
                  className="btn btn-outline"
                  style={{flex:1, justifyContent:'center', fontSize:13}}
                  onClick={() => fileRef.current.click()}
                >
                  🖼 Gallery
                </button>
              </div>
            )}

            {/* Gallery input */}
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              style={{display:'none'}}
              onChange={e => e.target.files[0] && pickFile(e.target.files[0])}
            />

            {/* Drop zone — only for drag-drop, NOT clickable to avoid note conflict */}
            <div
              className={`drop-zone ${file ? 'filled' : ''}`}
              onDrop={e => { e.preventDefault(); pickFile(e.dataTransfer.files[0]) }}
              onDragOver={e => e.preventDefault()}
            >
              {preview
                ? <img src={preview} alt="preview"/>
                : <><div className="drop-icon">🖼</div><div className="drop-title">Drag & drop here</div><div className="drop-sub">PNG · JPG · WEBP</div></>
              }
            </div>

            {/* Dedicated upload button — separate from notes */}
            {!file && (
              <button
                className="btn btn-outline"
                style={{width:'100%', justifyContent:'center', fontSize:13, marginTop:8}}
                onClick={() => fileRef.current.click()}
              >
                ↑ Select Photo to Upload
              </button>
            )}

            {file && (
              <button className="btn btn-outline" style={{fontSize:12, padding:'5px 12px', marginTop:8}}
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

            {locBusy && !location && (
              <div className="loading" style={{padding:12}}>
                <div className="spinner"/>
                <span style={{fontSize:12}}>Acquiring GPS… please allow location access</span>
              </div>
            )}

            {!location && !locBusy && locWarn && (
              <div style={{
                background:'rgba(239,68,68,0.08)', border:'1px solid rgba(239,68,68,0.2)',
                borderRadius:8, padding:'10px 14px', fontSize:12, color:'#ef4444', marginBottom:8,
              }}>
                ⚠️ {locWarn}
                <br/>
                <span style={{opacity:0.7, fontSize:11}}>Use the map below to set your location manually.</span>
              </div>
            )}

            {location && (
              <div className="loc-box">
                <div className="loc-head">✓ GPS acquired</div>
                {/* Human-readable address */}
                {addrLoading
                  ? <div style={{fontSize:11, color:'#94a3b8', marginBottom:4}}>📍 Resolving address…</div>
                  : address && <div style={{fontSize:12, fontWeight:600, marginBottom:4}}>📍 {address}</div>
                }
                <div className="loc-row" style={{fontFamily:'Geist Mono, monospace', fontSize:11}}>
                  {location.lat.toFixed(6)}, {location.lng.toFixed(6)}
                </div>
                <div className="loc-row">🕐 {toPST(geo.timestamp || new Date().toISOString())}</div>
              </div>
            )}

            {editMode && (
              <div className="upload-map-wrap">
                <div className="upload-map-hint">👆 Click the map to set location</div>
                <MapContainer
                  center={location ? [location.lat, location.lng] : [32.7157, -117.1611]}
                  zoom={13}
                  style={{height:'100%', width:'100%'}}
                >
                  <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution='&copy; OpenStreetMap contributors' />
                  <MapPicker location={location} onPick={handleMapPick} />
                  <LocationSearch onPick={handleMapPick} />
                </MapContainer>
              </div>
            )}

            {editMode && (
              <div className="manual-coords">
                <div className="manual-coord-field">
                  <label>Latitude</label>
                  <input type="number" step="any" value={manualLat} onChange={e => setManualLat(e.target.value)} placeholder="-90 to 90" style={{marginBottom:0}}/>
                </div>
                <div className="manual-coord-field">
                  <label>Longitude</label>
                  <input type="number" step="any" value={manualLng} onChange={e => setManualLng(e.target.value)} placeholder="-180 to 180" style={{marginBottom:0}}/>
                </div>
                <button className="btn btn-dark" style={{alignSelf:'flex-end', padding:'9px 16px', fontSize:13}} onClick={handleManualApply}>Apply</button>
              </div>
            )}

            {!editMode && (
              <button className="btn btn-outline" style={{fontSize:12, padding:'6px 13px', marginTop:8}} onClick={grabLocation}>
                ↻ Refresh GPS
              </button>
            )}
          </div>

          {/* Metadata — note section */}
          <div className="card">
            <div className="step-head">
              <div className="step-num">4</div>
              <div className="step-title">Metadata</div>
            </div>
            <label>Note</label>
            {/* Note textarea — standalone, no click-to-upload behavior */}
            <textarea
              placeholder="Add a note about this photo…"
              value={note}
              onChange={e => setNote(e.target.value)}
              rows={3}
              onClick={e => e.stopPropagation()}
              style={{
                width:'100%', padding:'10px 13px',
                background:'rgba(0,0,0,0.04)',
                border:'1px solid rgba(0,0,0,0.12)',
                borderRadius:9, fontSize:13.5, color:'inherit',
                outline:'none', resize:'vertical',
                fontFamily:'Geist, sans-serif', marginBottom:0,
                cursor:'text',
              }}
            />
          </div>

          {/* Dedicated Upload Button */}
          <button
            className="btn btn-green"
            style={{width:'100%', padding:'14px', fontSize:15, fontWeight:700, borderRadius:10, justifyContent:'center'}}
            onClick={handleUpload}
            disabled={!ready}
          >
            {uploading
              ? <><div className="spinner" style={{width:15,height:15,borderTopColor:'#fff'}}/>Uploading…</>
              : '↑ Upload Photo'
            }
          </button>

          {!ready && !uploading && (
            <div className="hint" style={{textAlign:'center', marginTop:8, fontSize:12, color:'rgba(255,255,255,0.3)'}}>
              {!selected && '← Select or create a profile first'}
              {selected && !file && '← Choose an image using Gallery above'}
            </div>
          )}
        </div>
      </div>
      </div>
    </div>
  )
}
