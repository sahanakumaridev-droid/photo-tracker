import React, { useEffect, useState, useRef, useContext } from 'react'
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { getProfiles, createProfile, uploadPhoto, getNearby } from '../api'
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

// Delivery Style — fixed choices, sent to the backend as `completion_type`
// (kept in sync with the mobile upload screen).
const DELIVERY_STYLES = ['Personal', 'Sub on 1st', 'Sub on 3rd', 'Posting', 'Stake Out']

// Priority categories — the single source of truth, shared with the Profiles
// page and mobile (asap / special / next_day / standard).
const CATEGORIES = [
  { value: 'asap',     label: 'ASAP',     color: '#ef4444', emoji: '🔴' },
  { value: 'special',  label: 'Special',  color: '#f59e0b', emoji: '🟠' },
  { value: 'next_day', label: 'Next Day', color: '#eab308', emoji: '🟡' },
  { value: 'standard', label: 'Standard', color: '#10b981', emoji: '🟢' },
]
// Map any stored value (incl. legacy rush/airport) to one of the 4 categories.
function normalizeCat(v) {
  const x = (v || 'standard').toLowerCase()
  if (x === 'rush') return 'asap'
  if (x === 'airport') return 'special'
  return CATEGORIES.some(c => c.value === x) ? x : 'standard'
}
const catOf = (v) => CATEGORIES.find(c => c.value === normalizeCat(v)) || CATEGORIES[3]

// PST formatter
function toPST(isoString) {
  if (!isoString) return ''
  return new Date(isoString).toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }) + ' PST'
}

// F5 — key for the resumable in-progress pin draft (survives navigate/refresh)
const DRAFT_KEY = 'upload_draft_v1'

// F6 — read the photo's real capture time from EXIF (DateTimeOriginal), so the
// timestamp reflects when the picture was TAKEN, not when it was uploaded.
// Falls back to the file's last-modified time, then null (caller uses now()).
async function readCaptureTime(file) {
  try {
    if (!file || !/jpe?g$/i.test(file.type) && !/\.jpe?g$/i.test(file.name)) {
      return file?.lastModified ? new Date(file.lastModified).toISOString() : null
    }
    const buf  = await file.slice(0, 256 * 1024).arrayBuffer()
    const view = new DataView(buf)
    if (view.getUint16(0) !== 0xFFD8) return fallback(file)   // not a JPEG
    let offset = 2
    while (offset + 4 < view.byteLength) {
      const marker = view.getUint16(offset)
      if (marker === 0xFFE1) {                                // APP1 (Exif)
        const exifStart = offset + 4
        if (view.getUint32(exifStart) !== 0x45786966) break   // "Exif"
        const tiff   = exifStart + 6
        const little = view.getUint16(tiff) === 0x4949
        const g16 = o => view.getUint16(o, little)
        const g32 = o => view.getUint32(o, little)
        const findTag = (dir, tag) => {
          const n = g16(dir)
          for (let i = 0; i < n; i++) {
            const e = dir + 2 + i * 12
            if (g16(e) === tag) return e
          }
          return -1
        }
        const ifd0    = tiff + g32(tiff + 4)
        const exifPtr = findTag(ifd0, 0x8769)
        if (exifPtr < 0) break
        const exifIFD = tiff + g32(exifPtr + 8)
        let dt = findTag(exifIFD, 0x9003)                     // DateTimeOriginal
        if (dt < 0) dt = findTag(exifIFD, 0x9004)             // DateTimeDigitized
        if (dt < 0) break
        const valOff = tiff + g32(dt + 8)
        let s = ''
        for (let i = 0; i < 19; i++) s += String.fromCharCode(view.getUint8(valOff + i))
        const m = s.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/)
        if (m) {
          const d = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])
          if (!isNaN(d)) return d.toISOString()
        }
        break
      }
      if ((marker & 0xFF00) !== 0xFF00) break
      offset += 2 + view.getUint16(offset + 2)                // skip this segment
    }
  } catch { /* fall through */ }
  return fallback(file)
}
function fallback(file) {
  return file?.lastModified ? new Date(file.lastModified).toISOString() : null
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
  const [deliveryStyle, setDeliveryStyle] = useState('')        // stored as completion_type
  const [category,     setCategory]     = useState('standard')  // F2/F4 service level
  const [payRate,      setPayRate]      = useState('')          // F7 pay rate
  const [takenAt,      setTakenAt]      = useState(null)        // F6 capture time (EXIF)
  // F1 — nearby existing pins (reuse instead of creating a duplicate)
  const [nearbyPins,   setNearbyPins]   = useState([])
  const [reuseGroupId, setReuseGroupId] = useState(null)
  const [nearbyDismissed, setNearbyDismissed] = useState(false)
  // F5 — resumable draft
  const [draftRestored, setDraftRestored] = useState(false)
  const didRestore = useRef(false)
  const pendingSelectId = useRef(null)
  // inline new profile
  const [showNewProf,  setShowNewProf]  = useState(false)
  const [newProfName,  setNewProfName]  = useState('')
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

  // F1 — when location changes, look for an existing pin within 1 mile so the
  // user can append this attempt instead of creating a duplicate pin.
  useEffect(() => {
    if (!location) { setNearbyPins([]); return }
    let alive = true
    // Proximity for searchable/reusable profiles on upload: 1 mile (5280 ft).
    getNearby(location.lat, location.lng, 5280)
      .then(pins => {
        if (!alive) return
        setNearbyPins(Array.isArray(pins) ? pins : [])
        setNearbyDismissed(false)
        // If they had picked a reuse target that's no longer nearby, clear it
        setReuseGroupId(prev =>
          prev && (pins || []).some(p => p.location_group_id === prev) ? prev : null)
      })
      .catch(() => { if (alive) setNearbyPins([]) })
    return () => { alive = false }
  }, [location && location.lat, location && location.lng])

  // F5 — restore an in-progress draft once (note/profile/category/pay/location).
  // The image File can't be serialized, so only the metadata is restored.
  useEffect(() => {
    if (didRestore.current) return
    didRestore.current = true
    try {
      const raw = localStorage.getItem(DRAFT_KEY)
      if (!raw) return
      const d = JSON.parse(raw)
      const hasContent = d && (d.note || d.payRate || d.address ||
        (d.category && d.category !== 'standard') || d.selectedId || d.location)
      if (!hasContent) return
      if (d.note)     setNote(d.note)
      if (d.category) setCategory(d.category)
      if (DELIVERY_STYLES.includes(d.deliveryStyle)) setDeliveryStyle(d.deliveryStyle)
      if (d.payRate)  setPayRate(d.payRate)
      if (d.address)  setAddress(d.address)
      if (d.location) setLocation(d.location)
      if (d.selectedId) {
        // profiles may not be loaded yet; resolve on next profiles update
        pendingSelectId.current = d.selectedId
      }
      setDraftRestored(true)
    } catch { /* ignore */ }
  }, [])

  // Resolve a restored profile id once profiles have loaded
  useEffect(() => {
    if (pendingSelectId.current && profiles.length) {
      const p = profiles.find(x => String(x.id) === String(pendingSelectId.current))
      if (p) setSelected(p)
      pendingSelectId.current = null
    }
  }, [profiles])

  // F5 — persist the draft whenever meaningful fields change
  useEffect(() => {
    if (!didRestore.current) return
    const draft = {
      note, category, deliveryStyle, payRate, address,
      selectedId: selected ? selected.id : null,
      location,
    }
    const empty = !note && !payRate && !address && category === 'standard' &&
      !deliveryStyle && !selected && !location
    try {
      if (empty) localStorage.removeItem(DRAFT_KEY)
      else localStorage.setItem(DRAFT_KEY, JSON.stringify(draft))
    } catch { /* ignore */ }
  }, [note, category, deliveryStyle, payRate, address, selected, location])

  const clearDraft = () => {
    try { localStorage.removeItem(DRAFT_KEY) } catch {}
    setNote(''); setCategory('standard'); setDeliveryStyle(''); setPayRate('')
    setSelected(null); setFile(null); setPreview(null); setTakenAt(null)
    setDraftRestored(false)
  }

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

  const pickFile = async (f) => {
    setFile(f)
    setPreview(URL.createObjectURL(f))
    // F6 — lock timestamp to the photo's actual capture time (EXIF), not upload time
    const captured = await readCaptureTime(f)
    setTakenAt(captured)
  }

  // Create new profile inline
  const handleCreateProfile = async (e) => {
    e.preventDefault()
    if (!newProfName.trim()) return
    setCreatingProf(true)
    const fd = new FormData()
    fd.append('name', newProfName)
    // Service level is chosen per-photo (the "Category" selector) during upload,
    // not on the profile — so new profiles start at the default.
    fd.append('service_type', 'standard')
    try {
      const created = await createProfile(fd)
      await loadProfiles()
      setSelected(created)
      setShowNewProf(false)
      setNewProfName('')
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
    if (deliveryStyle) fd.append('completion_type', deliveryStyle)  // Delivery Style
    fd.append('category',   category)                          // F2/F4 service level
    if (payRate !== '') fd.append('pay_rate', payRate)         // F7 pay rate
    // F6: send the photo's real capture time (EXIF); fall back to now
    fd.append('taken_at',   takenAt || new Date().toISOString())
    // F1: append to an existing pin instead of creating a duplicate
    if (reuseGroupId) fd.append('location_group_id', String(reuseGroupId))
    try {
      await uploadPhoto(fd)
      try { localStorage.removeItem(DRAFT_KEY) } catch {}      // F5: draft consumed
      // Small delay to ensure backend has committed before dashboard re-fetches
      await new Promise(r => setTimeout(r, 300))
      showToast(reuseGroupId ? 'Attempt added to existing pin ✓' : 'Photo uploaded ✓')
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

      {/* F5 — resumed draft banner */}
      {draftRestored && (
        <div style={{
          display:'flex', alignItems:'center', gap:10, marginBottom:16,
          background:'rgba(99,102,241,0.10)', border:'1px solid rgba(99,102,241,0.3)',
          borderRadius:10, padding:'10px 14px', fontSize:13,
        }}>
          <span style={{fontSize:16}}>💾</span>
          <span style={{flex:1}}>Resumed your in-progress pin. Re-select the photo (images can't be auto-restored).</span>
          <button className="btn btn-outline" style={{fontSize:12, padding:'5px 12px'}}
            onClick={clearDraft}>Start fresh</button>
        </div>
      )}

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
                <div style={{fontSize:11.5, color:'rgba(100,100,120,0.7)', marginBottom:12}}>
                  You'll pick the Category when you upload the photo.
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
                    <div className="avatar" style={{background:catOf(p.service_type).color}}>{p.name.charAt(0)}</div>
                    <div style={{flex:1}}>
                      <div style={{fontWeight:700, fontSize:14}}>{p.name}</div>
                      <div style={{fontSize:11, color:'rgba(100,100,120,0.6)', marginTop:1, fontFamily:'Geist Mono, monospace'}}>#{p.id}</div>
                    </div>
                    {(() => { const c = catOf(p.service_type)
                      return <span style={{fontSize:11, fontWeight:700, color:'#fff', background:c.color, borderRadius:8, padding:'3px 9px'}}>{c.emoji} {c.label}</span> })()}
                    {selected?.id === p.id && <span style={{fontWeight:800, color:'#a5b4fc', marginLeft:4}}>✓</span>}
                  </div>
                ))
            }
          </div>

          {/* Delivery Style — below the profile, a fixed dropdown (sent as
              completion_type). Replaces the old free-text "Type". */}
          <div className="card">
            <label style={{marginBottom:6, display:'block'}}>Delivery Style</label>
            <select
              value={deliveryStyle}
              onChange={e => setDeliveryStyle(e.target.value)}
              style={{
                width:'100%', padding:'10px 13px', background:'rgba(0,0,0,0.04)',
                border:'1px solid rgba(0,0,0,0.12)', borderRadius:9, fontSize:13.5,
                color:'inherit', outline:'none', cursor:'pointer',
                fontFamily:'Geist, sans-serif',
              }}
            >
              <option value="">Select a delivery style…</option>
              {DELIVERY_STYLES.map(s => <option key={s} value={s}>{s}</option>)}
            </select>
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
                <div className="loc-row">
                  🕐 {toPST(takenAt || geo.timestamp || new Date().toISOString())}
                  {takenAt && <span style={{marginLeft:6, fontSize:10, color:'#10b981', fontWeight:700}}>· from photo</span>}
                </div>
              </div>
            )}

            {/* F1 — reuse an existing pin within 100 ft instead of duplicating */}
            {nearbyPins.length > 0 && !nearbyDismissed && (
              <div style={{
                marginTop:10, background:'rgba(202,138,4,0.10)',
                border:'1px solid rgba(202,138,4,0.35)', borderRadius:10, padding:'12px 14px',
              }}>
                <div style={{fontSize:13, fontWeight:700, marginBottom:6, color:'#92400e'}}>
                  📍 {nearbyPins.length} existing pin{nearbyPins.length > 1 ? 's' : ''} within 1&nbsp;mile
                </div>
                <div style={{fontSize:12, color:'#78716c', marginBottom:10}}>
                  Add this photo as another attempt to an existing pin instead of creating a duplicate?
                </div>
                <div style={{display:'flex', flexDirection:'column', gap:6}}>
                  {nearbyPins.slice(0, 4).map(p => {
                    const sel = reuseGroupId === p.location_group_id
                    return (
                      <button key={p.location_group_id} type="button"
                        onClick={() => setReuseGroupId(sel ? null : p.location_group_id)}
                        style={{
                          textAlign:'left', display:'flex', alignItems:'center', gap:8,
                          padding:'8px 10px', borderRadius:8, cursor:'pointer', fontSize:12,
                          border:'1px solid ' + (sel ? '#16a34a' : 'rgba(0,0,0,0.12)'),
                          background: sel ? 'rgba(22,163,74,0.12)' : '#fff',
                        }}>
                        <span style={{fontWeight:800, color: sel ? '#16a34a' : '#94a3b8'}}>{sel ? '✓' : '+'}</span>
                        <span style={{flex:1}}>
                          <span style={{fontWeight:600}}>{p.address || `${p.latitude.toFixed(5)}, ${p.longitude.toFixed(5)}`}</span>
                          <span style={{color:'#94a3b8'}}> · {p.attempt_count} attempt{p.attempt_count !== 1 ? 's' : ''} · {p.distance_ft} ft</span>
                        </span>
                      </button>
                    )
                  })}
                </div>
                <div style={{display:'flex', gap:8, marginTop:10}}>
                  {reuseGroupId
                    ? <span style={{fontSize:11.5, color:'#16a34a', fontWeight:700, alignSelf:'center'}}>
                        ✓ This photo will be added to the selected pin
                      </span>
                    : <button className="btn btn-outline" style={{fontSize:12, padding:'5px 12px'}}
                        onClick={() => setNearbyDismissed(true)}>Create a new pin instead</button>}
                </div>
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

            {/* F2/F4 — Category (per-photo service level) */}
            <label style={{marginBottom:4}}>Category</label>
            <div style={{display:'flex', gap:6, marginBottom:12, flexWrap:'wrap'}}>
              {[
                { k:'asap',     l:'ASAP',     c:'#DC2626' },
                { k:'next_day', l:'Next Day', c:'#CA8A04' },
                { k:'standard', l:'Standard', c:'#059669' },
                { k:'special',  l:'Special',  c:'#EA580C' },
              ].map(s => (
                <button key={s.k} type="button" onClick={() => setCategory(s.k)}
                  style={{
                    flex:'1 1 40%', padding:'7px 10px', borderRadius:8, fontSize:12, fontWeight:700, cursor:'pointer',
                    border:'1px solid ' + (category === s.k ? s.c : 'rgba(0,0,0,0.12)'),
                    background: category === s.k ? s.c : 'transparent',
                    color: category === s.k ? '#fff' : '#64748b',
                  }}>{s.l}</button>
              ))}
            </div>

            {/* F7 — Pay rate */}
            <label style={{marginBottom:4}}>Pay Rate ($)</label>
            <input type="number" min="0" step="1" value={payRate}
              onChange={e => setPayRate(e.target.value.replace(/[^0-9]/g, ''))}
              placeholder="e.g. 30"
              style={{width:'100%', padding:'10px 13px', background:'rgba(0,0,0,0.04)',
                border:'1px solid rgba(0,0,0,0.12)', borderRadius:9, fontSize:13.5, marginBottom:12}} />

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
