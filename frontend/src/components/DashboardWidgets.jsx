import React, { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getProfiles, updatePhotoNote, replacePhotoImage, uploadPhoto } from '../api'

function toPST(ts) {
  if (!ts) return ''
  return new Date(ts).toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    month: 'short', day: 'numeric', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }) + ' PST'
}

/* ── Profile Pills with overflow dropdown ── */
const MAX_VISIBLE = 4

export function ProfilePills({ profiles, photos, filterProfile, setFilterProfile }) {
  const [open, setOpen] = useState(false)

  const visible  = profiles.slice(0, MAX_VISIBLE)
  const overflow = profiles.slice(MAX_VISIBLE)
  const hasMore  = overflow.length > 0

  // close dropdown on outside click
  const ref = React.useRef()
  useEffect(() => {
    const handler = e => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const Pill = ({ p }) => {
    const count = photos.filter(ph => ph.profile_id === p.id).length
    const color = p.service_type === 'rush' ? '#f43f5e' : '#10b981'
    const active = filterProfile === String(p.id)
    return (
      <button
        className={`dk-pill ${active ? 'dk-pill-active' : ''}`}
        style={active ? {'--pill-color': color} : {}}
        onClick={() => { setFilterProfile(String(p.id)); setOpen(false) }}
      >
        <span className="dk-pill-dot" style={{background: color}}/>
        {p.name.split(' ')[0]}
        <span className="dk-pill-count">{count}</span>
      </button>
    )
  }

  return (
    <div className="dk-filter-pills" style={{position:'relative'}} ref={ref}>
      {/* All pill */}
      <button className={`dk-pill ${filterProfile === 'all' ? 'dk-pill-active' : ''}`}
        onClick={() => setFilterProfile('all')}>
        All <span className="dk-pill-count">{photos.length}</span>
      </button>

      {/* Visible pills */}
      {visible.map(p => <Pill key={p.id} p={p} />)}

      {/* +N more button */}
      {hasMore && (
        <button
          className={`dk-pill dk-pill-more ${open ? 'dk-pill-active' : ''}`}
          onClick={() => setOpen(v => !v)}
        >
          +{overflow.length} more
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" style={{marginLeft:2, transform: open ? 'rotate(180deg)' : 'none', transition:'transform 0.15s'}}>
            <path d="M6 9l6 6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
      )}

      {/* Overflow dropdown */}
      {open && hasMore && (
        <div className="dk-pills-dropdown">
          {overflow.map(p => {
            const count = photos.filter(ph => ph.profile_id === p.id).length
            const color = p.service_type === 'rush' ? '#f43f5e' : '#10b981'
            const active = filterProfile === String(p.id)
            return (
              <button
                key={p.id}
                className={`dk-dropdown-item ${active ? 'dk-dropdown-item-active' : ''}`}
                onClick={() => { setFilterProfile(String(p.id)); setOpen(false) }}
              >
                <span className="dk-pill-dot" style={{background: color, boxShadow: `0 0 5px ${color}`}}/>
                <span style={{flex:1}}>{p.name}</span>
                <span className={`badge badge-${p.service_type}`} style={{fontSize:9, padding:'1px 6px'}}>{p.service_type}</span>
                <span className="dk-pill-count">{count}</span>
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

/* ── Grouped Pin Popup — profile tabs + per-profile photo carousel ── */
export function GroupedPinPopup({ profileGroups, lat, lng, onUpdated }) {
  const [activeProfile, setActiveProfile] = useState(0)
  const [addingPhoto,   setAddingPhoto]   = useState(false)

  const pg = profileGroups[activeProfile]

  // Reset photo index when switching profiles
  const [photoIdx, setPhotoIdx] = useState(0)
  useEffect(() => { setPhotoIdx(0); setAddingPhoto(false) }, [activeProfile])

  const photos = pg.photos
  const ph     = photos[photoIdx]

  const prev = () => setPhotoIdx(i => (i - 1 + photos.length) % photos.length)
  const next = () => setPhotoIdx(i => (i + 1) % photos.length)

  // Touch swipe
  const touchStartX = React.useRef(null)
  const onTouchStart = e => { touchStartX.current = e.touches[0].clientX }
  const onTouchEnd   = e => {
    if (touchStartX.current === null) return
    const dx = e.changedTouches[0].clientX - touchStartX.current
    if (dx < -40) next()
    else if (dx > 40) prev()
    touchStartX.current = null
  }

  const totalPhotos = profileGroups.reduce((s, g) => s + g.photos.length, 0)

  return (
    <div style={{ minWidth: 280, maxWidth: 320 }}>

      {/* ── Profile tabs ── */}
      <div style={{
        display: 'flex', background: '#0f0e1a',
        borderRadius: '6px 6px 0 0', overflow: 'hidden',
        borderBottom: '1px solid rgba(255,255,255,0.08)',
      }}>
        {profileGroups.map((g, i) => {
          const color   = g.serviceType === 'rush' ? '#ef4444' : g.serviceType === 'airport' ? '#0ea5e9' : '#10b981'
          const isActive = activeProfile === i
          return (
            <button
              key={g.profileId}
              onClick={() => setActiveProfile(i)}
              style={{
                flex: 1, padding: '8px 6px', border: 'none', cursor: 'pointer',
                background: isActive ? 'rgba(255,255,255,0.08)' : 'transparent',
                borderBottom: isActive ? `2px solid ${color}` : '2px solid transparent',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
                transition: 'all 0.15s',
              }}
            >
              {/* Profile avatar */}
              <div style={{
                width: 28, height: 28, borderRadius: '50%',
                background: `linear-gradient(135deg, ${color}cc, ${color}55)`,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: 12, fontWeight: 800, color: '#fff',
                border: isActive ? `2px solid ${color}` : '2px solid transparent',
              }}>
                {g.profileName.charAt(0).toUpperCase()}
              </div>
              {/* Name + photo count badge */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
                <span style={{
                  fontSize: 10, fontWeight: 700,
                  color: isActive ? '#fff' : 'rgba(255,255,255,0.4)',
                  maxWidth: 60, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>
                  {g.profileName.split(' ')[0]}
                </span>
                <span style={{
                  fontSize: 9, fontWeight: 800, padding: '1px 5px',
                  borderRadius: 99, background: isActive ? color : 'rgba(255,255,255,0.1)',
                  color: isActive ? '#fff' : 'rgba(255,255,255,0.4)',
                }}>
                  {g.photos.length}
                </span>
              </div>
            </button>
          )
        })}

        {/* Total count on far right if multiple profiles */}
        {profileGroups.length > 1 && (
          <div style={{
            padding: '8px 8px', display: 'flex', alignItems: 'center',
            borderLeft: '1px solid rgba(255,255,255,0.06)',
          }}>
            <span style={{
              fontSize: 9, color: 'rgba(255,255,255,0.3)',
              fontFamily: 'Geist Mono, monospace', whiteSpace: 'nowrap',
            }}>
              {totalPhotos} total
            </span>
          </div>
        )}
      </div>

      {/* ── Photo carousel for active profile ── */}
      <div
        style={{ position: 'relative', background: '#0f0e1a', overflow: 'hidden' }}
        onTouchStart={onTouchStart}
        onTouchEnd={onTouchEnd}
      >
        <img
          src={ph.image_url}
          alt=""
          style={{ display: 'block', width: '100%', height: 155, objectFit: 'cover', userSelect: 'none' }}
          onError={e => { e.target.style.display = 'none' }}
        />

        {/* Carousel nav — only if this profile has multiple photos */}
        {photos.length > 1 && (
          <>
            <button onClick={prev} style={{
              position: 'absolute', left: 6, top: '50%', transform: 'translateY(-50%)',
              background: 'rgba(0,0,0,0.6)', border: 'none', borderRadius: '50%',
              width: 26, height: 26, color: '#fff', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14,
            }}>‹</button>
            <button onClick={next} style={{
              position: 'absolute', right: 6, top: '50%', transform: 'translateY(-50%)',
              background: 'rgba(0,0,0,0.6)', border: 'none', borderRadius: '50%',
              width: 26, height: 26, color: '#fff', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14,
            }}>›</button>

            {/* Dots */}
            <div style={{
              position: 'absolute', bottom: 6, left: 0, right: 0,
              display: 'flex', justifyContent: 'center', gap: 4,
            }}>
              {photos.map((_, i) => (
                <button key={i} onClick={() => setPhotoIdx(i)} style={{
                  width: photoIdx === i ? 14 : 5, height: 5, borderRadius: 99,
                  background: photoIdx === i ? '#fff' : 'rgba(255,255,255,0.4)',
                  border: 'none', cursor: 'pointer', padding: 0, transition: 'all 0.2s',
                }}/>
              ))}
            </div>

            {/* Counter */}
            <div style={{
              position: 'absolute', top: 6, right: 6,
              background: 'rgba(0,0,0,0.65)', color: '#fff',
              fontSize: 10, fontWeight: 700, padding: '2px 6px',
              borderRadius: 99, fontFamily: 'Geist Mono, monospace',
            }}>
              {photoIdx + 1}/{photos.length}
            </div>
          </>
        )}

        {/* + Add Photo button */}
        <button
          onClick={() => setAddingPhoto(v => !v)}
          style={{
            position: 'absolute', top: 6, left: 6,
            background: addingPhoto ? 'rgba(239,68,68,0.85)' : 'rgba(99,102,241,0.85)',
            border: 'none', borderRadius: 5, color: '#fff',
            fontSize: 10, fontWeight: 700, padding: '3px 8px',
            cursor: 'pointer', backdropFilter: 'blur(4px)',
          }}
        >
          {addingPhoto ? '✕ Cancel' : '📷 + Add Photo'}
        </button>
      </div>

      {/* ── Add photo form ── */}
      {addingPhoto && (
        <PinAddPhotoForm
          lat={lat}
          lng={lng}
          profileId={pg.profileId}
          onDone={() => { setAddingPhoto(false); onUpdated() }}
        />
      )}

      {/* ── Photo detail for active photo ── */}
      {!addingPhoto && <PinPopup ph={ph} onNoteUpdated={onUpdated} />}
    </div>
  )
}

/* ── Inline photo upload form inside pin popup ── */
export function PinAddPhotoForm({ lat, lng, profileId, onDone }) {
  const [file,      setFile]      = useState(null)
  const [preview,   setPreview]   = useState(null)
  const [note,      setNote]      = useState('')
  const [uploading, setUploading] = useState(false)
  const [profiles,  setProfiles]  = useState([])
  const [selProfile, setSelProfile] = useState(profileId)

  useEffect(() => {
    getProfiles().then(setProfiles)
  }, [])

  const pickFile = (f) => { setFile(f); setPreview(URL.createObjectURL(f)) }

  const handleUpload = async () => {
    if (!file) return
    setUploading(true)

    // Reverse geocode the pin location
    let address = ''
    try {
      const res = await fetch(
        `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1&extratags=1&_t=${Date.now()}`,
        { headers: { 'Accept-Language': 'en' } }
      )
      const data = await res.json()
      if (data?.address) {
        const a = data.address
        const seen = new Set()
        const parts = []
        const road = a.road || a.pedestrian || a.path
        if (road) {
          const street = a.house_number ? `${a.house_number} ${road}` : road
          parts.push(street)
          seen.add(street.toLowerCase())
        }
        const city = a.city || a.town || a.village || a.municipality
        if (city && !seen.has(city.toLowerCase())) parts.push(city)
        if (a.state_code || a.state) {
          const st = a.state_code || a.state
          if (!seen.has(st.toLowerCase())) parts.push(st)
        }
        if (a.postcode) parts.push(a.postcode)
        address = parts.join(', ') || data.display_name || ''
      }
    } catch { /* non-critical */ }

    const fd = new FormData()
    fd.append('file',       file)
    fd.append('profile_id', selProfile)
    fd.append('latitude',   lat)
    fd.append('longitude',  lng)
    if (address) fd.append('address', address)
    fd.append('note',       note)
    try {
      await uploadPhoto(fd)
      onDone()
    } catch { alert('Upload failed') }
    setUploading(false)
  }

  return (
    <div style={{
      background: '#1a1830', padding: '12px 14px',
      borderTop: '1px solid rgba(255,255,255,0.08)',
    }}>
      <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.4)', marginBottom: 8 }}>
        📍 Adding photo at this pin location
      </div>

      {/* Profile selector */}
      {profiles.length > 0 && (
        <div style={{ marginBottom: 8 }}>
          <label style={{ fontSize: 10, color: 'rgba(255,255,255,0.4)', display: 'block', marginBottom: 4 }}>Profile</label>
          <select
            value={selProfile}
            onChange={e => setSelProfile(e.target.value)}
            style={{
              width: '100%', padding: '6px 8px', fontSize: 12,
              background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)',
              borderRadius: 6, color: '#e2e8f0', outline: 'none', marginBottom: 0,
            }}
          >
            {profiles.map(p => (
              <option key={p.id} value={p.id}>{p.name} ({p.service_type})</option>
            ))}
          </select>
        </div>
      )}

      {/* Photo picker */}
      {!file ? (
        <div style={{ display: 'flex', gap: 6, marginBottom: 8 }}>
          <button
            style={{
              flex: 1, padding: '8px', background: 'rgba(255,255,255,0.05)',
              border: '1px solid rgba(255,255,255,0.1)', borderRadius: 6,
              color: 'rgba(255,255,255,0.6)', fontSize: 12, fontWeight: 700, cursor: 'pointer',
            }}
            onClick={() => {
              const input = document.createElement('input')
              input.type = 'file'; input.accept = 'image/*'
              input.onchange = e => { const f = e.target.files[0]; if(f) pickFile(f) }
              input.click()
            }}
          >🖼 Gallery</button>
        </div>
      ) : (
        <div style={{ position: 'relative', marginBottom: 8 }}>
          <img src={preview} alt="" style={{ width: '100%', height: 100, objectFit: 'cover', borderRadius: 6, display: 'block' }}/>
          <button
            onClick={() => { setFile(null); setPreview(null) }}
            style={{
              position: 'absolute', top: 4, right: 4,
              background: 'rgba(0,0,0,0.7)', border: 'none', color: '#fff',
              borderRadius: 4, padding: '2px 7px', fontSize: 11, cursor: 'pointer',
            }}
          >✕</button>
        </div>
      )}

      {/* Note */}
      <textarea
        value={note}
        onChange={e => setNote(e.target.value)}
        placeholder="Add a note… (optional)"
        rows={2}
        style={{
          width: '100%', padding: '6px 8px', fontSize: 12,
          background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)',
          borderRadius: 6, color: '#e2e8f0', outline: 'none', resize: 'none',
          fontFamily: 'inherit', marginBottom: 8, boxSizing: 'border-box',
        }}
      />

      {/* Upload button */}
      <button
        onClick={handleUpload}
        disabled={!file || uploading}
        style={{
          width: '100%', padding: '9px', background: file ? '#6366f1' : 'rgba(255,255,255,0.05)',
          border: 'none', borderRadius: 6, color: file ? '#fff' : 'rgba(255,255,255,0.3)',
          fontSize: 13, fontWeight: 700, cursor: file ? 'pointer' : 'not-allowed',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        }}
      >
        {uploading
          ? <><div className="dk-spinner" style={{width:12,height:12}}/>Uploading…</>
          : '↑ Upload to this pin'
        }
      </button>
    </div>
  )
}

/* ── Pin Popup (shows all profiles at this pin + editable note) ── */
export function PinPopup({ ph, onNoteUpdated }) {
  const [note,    setNote]    = useState(ph.note || '')
  const [editing, setEditing] = useState(false)
  const [saving,  setSaving]  = useState(false)
  const [address, setAddress] = useState('')
  const navigate = useNavigate()

  // Reverse geocode on mount
  useEffect(() => {
    if (!ph.latitude || !ph.longitude) return
    fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${ph.latitude}&lon=${ph.longitude}&zoom=18&addressdetails=1&extratags=1&_t=${Date.now()}`,
      { headers: { 'Accept-Language': 'en' } }
    )
      .then(r => r.json())
      .then(data => {
        if (data?.address) {
          const a = data.address
          const seen = new Set()
          const parts = []
          const road = a.road || a.pedestrian || a.path
          if (road) {
            const street = a.house_number ? `${a.house_number} ${road}` : road
            parts.push(street)
            seen.add(street.toLowerCase())
          }
          const city = a.city || a.town || a.village || a.municipality
          if (city && !seen.has(city.toLowerCase())) {
            parts.push(city)
            seen.add(city.toLowerCase())
          }
          if (a.state_code || a.state) {
            const st = a.state_code || a.state
            if (!seen.has(st.toLowerCase())) parts.push(st)
          }
          if (a.postcode) parts.push(a.postcode)
          setAddress(parts.join(', ') || data.display_name || '')
        }
      })
      .catch(() => {})
  }, [ph.latitude, ph.longitude])

  const profiles = ph.profiles && ph.profiles.length > 0
    ? ph.profiles
    : [{ id: ph.profile_id, name: ph.profile_name, service_type: ph.service_type }]

  const saveNote = async () => {
    setSaving(true)
    await updatePhotoNote(ph.id, note)
    setSaving(false)
    setEditing(false)
    onNoteUpdated()
  }

  return (
    <>
      <div className="popup-body">
        {/* All profiles at this pin — each clickable */}
        <div className="popup-profiles-label">Profiles at this pin</div>
        <div className="popup-profiles">
          {profiles.map((p, i) => (
            <div
              key={i}
              className="popup-profile-row"
              onClick={() => p.id && navigate(`/profiles/${p.id}`)}
              style={{ cursor: p.id ? 'pointer' : 'default', transition: 'background 0.12s' }}
              title={p.id ? `View ${p.name}'s profile` : ''}
            >
              <span className={`popup-profile-dot ${p.service_type === 'rush' ? 'dot-rush' : 'dot-std'}`} />
              <span className="popup-profile-name" style={{ flex: 1 }}>{p.name}</span>
              <span className={`badge badge-${p.service_type}`} style={{ fontSize: 9, padding: '1px 6px' }}>
                {p.service_type === 'rush' ? 'ASAP' : 'Standard'}
              </span>
              {p.id && (
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" style={{ marginLeft: 4, opacity: 0.4 }}>
                  <path d="M9 18l6-6-6-6" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              )}
            </div>
          ))}
        </div>

        <div className="popup-row" style={{ marginTop: 8 }}>🕐 {toPST(ph.timestamp)}</div>
        {address
          ? <div className="popup-row">📍 {address}</div>
          : <div className="popup-row" style={{fontFamily:'monospace', fontSize:10}}>
              {ph.latitude?.toFixed(5)}, {ph.longitude?.toFixed(5)}
            </div>
        }
        <div className="popup-row" style={{fontFamily:'monospace', fontSize:10, opacity:0.6}}>
          {ph.latitude?.toFixed(5)}, {ph.longitude?.toFixed(5)}
        </div>

        {/* Editable note */}
        <div className="popup-note-section">
          {editing ? (
            <>
              <textarea
                value={note}
                onChange={e => setNote(e.target.value)}
                rows={2}
                className="popup-note-input"
                placeholder="Add a note…"
                autoFocus
                onClick={e => e.stopPropagation()}
              />
              <div style={{ display: 'flex', gap: 6, marginTop: 6 }}>
                <button className="popup-save-btn" onClick={saveNote} disabled={saving}>
                  {saving ? 'Saving…' : 'Save'}
                </button>
                <button className="popup-cancel-btn" onClick={() => { setEditing(false); setNote(ph.note || '') }}>
                  Cancel
                </button>
              </div>
            </>
          ) : (
            <div className="popup-note-row" onClick={() => setEditing(true)}>
              <span className="popup-note-text">{note || <em style={{ opacity: 0.4 }}>Add note…</em>}</span>
              <span className="popup-note-edit">✏️</span>
            </div>
          )}
        </div>
      </div>
    </>
  )
}

/* ── Photo Grid ── */
export function PhotoGrid({ photos, empty, onDelete, onEditLocation }) {
  const [confirming, setConfirming] = useState(null)
  const replaceRef = React.useRef()
  const [replacingId, setReplacingId] = useState(null)

  const handleReplace = async (e, photoId) => {
    const file = e.target.files[0]
    if (!file) return
    await replacePhotoImage(photoId, file)
    onEditLocation(true)
    setReplacingId(null)
  }

  if (photos.length === 0) return (
    <div className="dk-empty">
      <svg width="40" height="40" viewBox="0 0 24 24" fill="none" opacity="0.3"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z" fill="currentColor"/></svg>
      <div>{empty}</div>
    </div>
  )
  return (
    <>
      {/* Hidden file input for replace */}
      <input
        ref={replaceRef} type="file" accept="image/*" style={{display:'none'}}
        onChange={e => handleReplace(e, replacingId)}
      />
      <div className="dk-photo-grid">
        {photos.map(p => (
          <div className="dk-photo-card" key={p.id}>
            <div style={{position:'relative'}}>
              <img src={p.image_url} alt="" onError={e => { e.target.src='https://via.placeholder.com/400x300/1e1b4b/6366f1?text=Photo' }}/>
              <div className={`dk-photo-badge dk-badge-${p.service_type}`}>{p.service_type}</div>
              <div className="dk-photo-actions">
                <button className="dk-photo-btn" title="Replace image"
                  onClick={() => { setReplacingId(p.id); replaceRef.current.click() }}>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
                </button>
                {confirming === p.id ? (
                  <div className="dk-confirm">
                    <button className="dk-confirm-yes" onClick={() => { onDelete(p.id); setConfirming(null) }}>Yes</button>
                    <button className="dk-confirm-no"  onClick={() => setConfirming(null)}>No</button>
                  </div>
                ) : (
                  <button className="dk-photo-btn dk-photo-del" onClick={() => setConfirming(p.id)} title="Delete">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z" fill="currentColor"/></svg>
                  </button>
                )}
              </div>
            </div>
              <div className="dk-photo-meta">
              <div className="dk-photo-name">{p.profile_name}</div>
              <div style={{marginBottom:4}}>
                <span className={`badge badge-${p.service_type}`}>
                  {p.service_type === 'rush' ? '🔴 ASAP' : '🟢 Standard'}
                </span>
              </div>
              <div className="dk-photo-info">📍 {p.latitude?.toFixed(3)}, {p.longitude?.toFixed(3)}</div>
              <div className="dk-photo-info">🕐 {new Date(p.timestamp).toLocaleDateString()}</div>
            </div>
          </div>
        ))}
      </div>
    </>
  )
}

/* ── Photo List ── */
export function PhotoList({ photos, empty, onDelete, onEditLocation }) {
  const [confirming, setConfirming] = useState(null)
  if (photos.length === 0) return (
    <div className="dk-empty"><div>{empty}</div></div>
  )
  return (
    <>
      <div className="dk-list">
        {photos.map(p => (
          <div className="dk-list-row" key={p.id}>
            <img className="dk-list-thumb" src={p.image_url} alt=""
              onError={e => { e.target.src='https://via.placeholder.com/56x56/1e1b4b/6366f1?text=P' }}/>
            <div className="dk-list-info">
              <div className="dk-list-name">{p.profile_name}</div>
              <div className="dk-list-meta">📍 {p.latitude?.toFixed(4)}, {p.longitude?.toFixed(4)} · 🕐 {new Date(p.timestamp).toLocaleString()}</div>
            </div>
            <span className={`dk-badge dk-badge-${p.service_type}`}>
              {p.service_type === 'rush' ? '🔴 ASAP' : '🟢 Standard'}
            </span>
            <div className="dk-list-actions">
              {confirming === p.id ? (
                <>
                  <button className="dk-confirm-yes" style={{padding:'4px 10px',fontSize:11}} onClick={() => { onDelete(p.id); setConfirming(null) }}>Yes</button>
                  <button className="dk-confirm-no"  style={{padding:'4px 10px',fontSize:11}} onClick={() => setConfirming(null)}>No</button>
                </>
              ) : (
                <button className="dk-list-btn dk-list-del" onClick={() => setConfirming(p.id)} title="Delete">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z" fill="currentColor"/></svg>
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </>
  )
}
