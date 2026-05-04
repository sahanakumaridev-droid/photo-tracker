import React, { useEffect, useState, useRef } from 'react'
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { getProfiles, createProfile, uploadPhoto } from '../api'
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
  const [zipCode,      setZipCode]      = useState('')
  const [note,         setNote]         = useState('')
  // inline new profile
  const [showNewProf,  setShowNewProf]  = useState(false)
  const [newProfName,  setNewProfName]  = useState('')
  const [newProfSvc,   setNewProfSvc]   = useState('standard')
  const [creatingProf, setCreatingProf] = useState(false)

  const fileRef   = useRef()
  const cameraRef = useRef()
  const navigate  = useNavigate()

  const loadProfiles = () => getProfiles().then(setProfiles)

  useEffect(() => { loadProfiles(); grabLocation() }, [])

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
        setLocation({ lat: 32.7157 + (Math.random()-.5)*.05, lng: -117.1611 + (Math.random()-.5)*.05 })
        setLocBusy(false)
      },
      { timeout: 8000 }
    )
  }

  const handleMapPick = (lat, lng) => { setLocation({ lat, lng }); setLocWarn(null) }

  const handleManualApply = () => {
    const lat = parseFloat(manualLat), lng = parseFloat(manualLng)
    if (isNaN(lat) || isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) return
    setLocation({ lat, lng }); setLocWarn(null)
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
    fd.append('zip_code',   zipCode)
    fd.append('note',       note)
    try {
      await uploadPhoto(fd)
      showToast('Photo uploaded')
      navigate('/')
    } catch { showToast('Upload failed', 'error') }
    setUploading(false)
  }

  const ready = file && selected && location && !uploading

  return (
    <div className="page" style={{display:'flex', flexDirection:'column', height:'100vh'}}>
      <div className="page-header">
        <div>
          <div className="page-title">Upload Photo</div>
          <div className="page-sub">Tag a photo with GPS location and profile</div>
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
                      <div style={{fontWeight:700, fontSize:14, color:'#fff'}}>{p.name}</div>
                      <div style={{fontSize:11, color:'rgba(255,255,255,0.4)', marginTop:1, fontFamily:'Geist Mono, monospace'}}>#{p.id}</div>
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

            {/* Two buttons: Camera + Gallery */}
            {!file && (
              <div style={{display:'flex', gap:8, marginBottom:12}}>
                <button
                  className="btn btn-outline"
                  style={{flex:1, justifyContent:'center', fontSize:13}}
                  onClick={() => cameraRef.current.click()}
                >
                  📷 Camera
                </button>
                <button
                  className="btn btn-outline"
                  style={{flex:1, justifyContent:'center', fontSize:13}}
                  onClick={() => fileRef.current.click()}
                >
                  🖼 Gallery
                </button>
              </div>
            )}

            {/* Camera input (capture) */}
            <input
              ref={cameraRef}
              type="file"
              accept="image/*"
              capture="environment"
              style={{display:'none'}}
              onChange={e => e.target.files[0] && pickFile(e.target.files[0])}
            />
            {/* Gallery input */}
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              style={{display:'none'}}
              onChange={e => e.target.files[0] && pickFile(e.target.files[0])}
            />

            <div
              className={`drop-zone ${file ? 'filled' : ''}`}
              onClick={() => !file && fileRef.current.click()}
              onDrop={e => { e.preventDefault(); pickFile(e.dataTransfer.files[0]) }}
              onDragOver={e => e.preventDefault()}
            >
              {preview
                ? <img src={preview} alt="preview"/>
                : <><div className="drop-icon">🖼</div><div className="drop-title">Or drag & drop here</div><div className="drop-sub">PNG · JPG · WEBP</div></>
              }
            </div>

            {file && (
              <button className="btn btn-outline" style={{fontSize:12, padding:'5px 12px'}}
                onClick={() => { setFile(null); setPreview(null); fileRef.current.value=''; cameraRef.current.value='' }}>
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

            {locBusy && <div className="loading" style={{padding:12}}><div className="spinner"/>Acquiring GPS…</div>}
            {location && (
              <div className={`loc-box ${locWarn ? 'warn' : ''}`}>
                <div className="loc-head">{locWarn ? '⚠ Fallback location' : '✓ GPS acquired'}</div>
                {locWarn && <div style={{fontSize:11, color:'#fbbf24', marginBottom:6}}>{locWarn}</div>}
                <div className="loc-row">📍 {location.lat.toFixed(6)}, {location.lng.toFixed(6)}</div>
                <div className="loc-row">🕐 {new Date().toLocaleString()}</div>
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

          {/* Metadata */}
          <div className="card">
            <div className="step-head">
              <div className="step-num">4</div>
              <div className="step-title">Metadata</div>
            </div>
            <label>Zip Code</label>
            <input
              type="text"
              placeholder="e.g. 92101"
              value={zipCode}
              onChange={e => setZipCode(e.target.value)}
              style={{marginBottom:14}}
            />
            <label>Note</label>
            <textarea
              placeholder="Add a note about this photo…"
              value={note}
              onChange={e => setNote(e.target.value)}
              rows={3}
              style={{
                width:'100%', padding:'10px 13px',
                background:'rgba(255,255,255,0.06)',
                border:'1px solid rgba(255,255,255,0.1)',
                borderRadius:9, fontSize:13.5, color:'#e2e8f0',
                outline:'none', resize:'vertical',
                fontFamily:'Geist, sans-serif', marginBottom:0,
              }}
            />
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
            <div className="hint" style={{textAlign:'center', marginTop:8, fontSize:12, color:'rgba(255,255,255,0.3)'}}>
              {!selected && '← Select or create a profile first'}
              {selected && !file && '← Choose an image'}
            </div>
          )}
        </div>
      </div>
      </div>
    </div>
  )
}
