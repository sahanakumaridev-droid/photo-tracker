import React, { useEffect, useState, useContext } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { getProfilePhotos, updateProfile, updatePhotoNote, uploadPhoto, replacePhotoImage } from '../api'
import { GeoContext } from '../context/GeoContext'

// PST formatter
function toPST(ts) {
  if (!ts) return '—'
  return new Date(ts).toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    month: 'short', day: 'numeric', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }) + ' PST'
}

export default function ProfileDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [data,       setData]       = useState(null)
  const [loading,    setLoading]    = useState(true)
  const [editing,    setEditing]    = useState(false)
  const [editName,   setEditName]   = useState('')
  const [editSvc,    setEditSvc]    = useState('standard')
  const [editNote,   setEditNote]   = useState('')
  const [saving,     setSaving]     = useState(false)
  const [addingPin,  setAddingPin]  = useState(false)

  const load = () => {
    getProfilePhotos(id)
      .then(d => {
        setData(d)
        setEditName(d.profile.name)
        setEditSvc(d.profile.service_type)
        setEditNote(d.profile.note || '')
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }

  useEffect(() => { load() }, [id])

  const handleSave = async () => {
    setSaving(true)
    await updateProfile(id, { name: editName, service_type: editSvc, note: editNote })
    setSaving(false)
    setEditing(false)
    load()
  }

  if (loading) return <div className="dk-loading" style={{height:'100vh'}}><div className="dk-spinner"/>Loading…</div>
  if (!data)   return <div className="page" style={{padding:32}}><p style={{color:'rgba(255,255,255,0.4)'}}>Profile not found.</p></div>

  const { profile, photos } = data

  return (
    <div className="page" style={{display:'flex', flexDirection:'column', height:'100vh'}}>
      {/* Header */}
      <div className="page-header">
        <div style={{display:'flex', alignItems:'center', gap:14}}>
          <button className="back-btn" onClick={() => navigate('/profiles')}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z" fill="currentColor"/></svg>
            Profiles
          </button>
          <div style={{width:1, height:20, background:'rgba(255,255,255,0.1)'}}/>
          <div className={`avatar av-${profile.service_type}`} style={{width:36,height:36,fontSize:15,borderRadius:10}}>
            {profile.name.charAt(0).toUpperCase()}
          </div>
          <div>
            <div className="page-title" style={{fontSize:16}}>{profile.name}</div>
            <div className="page-sub" style={{marginTop:1}}>
              <span className={`badge badge-${profile.service_type}`}>{profile.service_type}</span>
              <span style={{fontFamily:'Geist Mono, monospace', fontSize:10, marginLeft:8, color:'rgba(255,255,255,0.3)'}}>#{profile.id}</span>
            </div>
          </div>
        </div>
        <div style={{display:'flex', alignItems:'center', gap:12}}>
          <button
            className="btn btn-outline"
            style={{fontSize:12, padding:'6px 14px'}}
            onClick={() => setEditing(v => !v)}
          >
            {editing ? '✕ Cancel' : '✏️ Edit Profile'}
          </button>
          <button
            className="btn btn-green"
            style={{fontSize:12, padding:'6px 14px'}}
            onClick={() => setAddingPin(true)}
          >
            📍 Add Pin
          </button>
          <div style={{textAlign:'right'}}>
            <div style={{fontSize:28, fontWeight:900, letterSpacing:'-1px', color:'#fff', fontFamily:'Geist Mono, monospace'}}>{photos.length}</div>
            <div style={{fontSize:10, color:'rgba(255,255,255,0.3)', textTransform:'uppercase', letterSpacing:'0.8px', marginTop:2}}>photos</div>
          </div>
        </div>
      </div>

      {/* Add Pin Modal */}
      {addingPin && (
        <AddPinModal
          profileId={id}
          profileName={profile.name}
          onClose={() => setAddingPin(false)}
          onSaved={() => { setAddingPin(false); load() }}
        />
      )}

      {/* Content */}
      <div style={{flex:1, overflowY:'auto', padding:'20px 28px'}}>

        {/* Edit form */}
        {editing && (
          <div className="card" style={{marginBottom:16}}>
            <div className="step-head" style={{marginBottom:16}}>
              <div className="step-num">✏</div>
              <div className="step-title">Edit Profile</div>
            </div>
            <label>Name</label>
            <input
              value={editName}
              onChange={e => setEditName(e.target.value)}
              placeholder="Profile name"
            />
            <label>Service Type</label>
            <div style={{display:'flex', gap:8, marginBottom:14}}>
              {['standard','rush','airport'].map(t => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setEditSvc(t)}
                  className={`btn ${editSvc === t ? (t === 'rush' ? 'btn-dark' : t === 'airport' ? 'btn-outline' : 'btn-green') : 'btn-outline'}`}
                  style={{fontSize:12, padding:'6px 16px', ...(editSvc === t && t === 'airport' ? {background:'rgba(14,165,233,0.15)', borderColor:'#0ea5e9', color:'#0ea5e9'} : {})}}
                >
                  {t === 'rush' ? '🔴 Rush (ASAP)' : t === 'airport' ? '✈️ Airport' : '🟢 Standard'}
                </button>
              ))}
            </div>
            <label>Profile Note</label>
            <textarea
              value={editNote}
              onChange={e => setEditNote(e.target.value)}
              rows={3}
              placeholder="Add a note about this profile…"
              style={{
                width:'100%', padding:'10px 13px',
                background:'rgba(255,255,255,0.06)',
                border:'1px solid rgba(255,255,255,0.1)',
                borderRadius:9, fontSize:13.5, color:'#e2e8f0',
                outline:'none', resize:'vertical',
                fontFamily:'Geist, sans-serif', marginBottom:14,
              }}
            />
            <button
              className="btn btn-dark"
              onClick={handleSave}
              disabled={saving || !editName.trim()}
            >
              {saving ? <><div className="dk-spinner" style={{width:13,height:13}}/>Saving…</> : '✓ Save Changes'}
            </button>
          </div>
        )}

        {/* Profile note display */}
        {!editing && profile.note && (
          <div className="card" style={{marginBottom:16, borderColor:'rgba(99,102,241,0.2)'}}>
            <div style={{fontSize:10, fontWeight:700, color:'rgba(255,255,255,0.3)', textTransform:'uppercase', letterSpacing:'0.8px', marginBottom:8}}>Profile Note</div>
            <div style={{fontSize:13, color:'rgba(255,255,255,0.7)', lineHeight:1.6}}>{profile.note}</div>
          </div>
        )}

        {/* Photos */}
        <div className="card">
          <div className="sec-header">
            <span className="sec-title" style={{color:'rgba(255,255,255,0.7)'}}>Photos</span>
            <span className="sec-count">{photos.length}</span>
          </div>
          {photos.length === 0
            ? <div className="dk-empty"><div>No photos uploaded yet</div></div>
            : <PhotoGrid photos={photos} onUpdated={load} />
          }
        </div>
      </div>
    </div>
  )
}

/* ── Photo Grid with lightbox ── */
function PhotoGrid({ photos, onUpdated }) {
  const [lightboxId, setLightboxId] = useState(null)
  const lightboxIdx = lightboxId != null ? photos.findIndex(p => p.id === lightboxId) : -1

  return (
    <>
      {lightboxId != null && lightboxIdx >= 0 && (
        <PhotoLightbox
          photos={photos}
          startIdx={lightboxIdx}
          onClose={() => setLightboxId(null)}
        />
      )}
      <div className="dk-photo-grid" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
        {photos.map(p => (
          <PhotoCard
            key={p.id}
            p={p}
            allPhotos={photos}
            onPhotoClick={(id) => setLightboxId(id)}
            onNoteUpdated={onUpdated}
          />
        ))}
      </div>
    </>
  )
}

/* ── Photo Lightbox — full-screen swipeable carousel ── */
function PhotoLightbox({ photos, startIdx, onClose }) {
  const [idx, setIdx] = useState(startIdx)
  const ph = photos[idx]

  const prev = () => setIdx(i => (i - 1 + photos.length) % photos.length)
  const next = () => setIdx(i => (i + 1) % photos.length)

  // Keyboard nav
  useEffect(() => {
    const handler = (e) => {
      if (e.key === 'ArrowLeft')  prev()
      if (e.key === 'ArrowRight') next()
      if (e.key === 'Escape')     onClose()
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  // Touch swipe
  const touchStartX = React.useRef(null)
  const handleTouchStart = (e) => { touchStartX.current = e.touches[0].clientX }
  const handleTouchEnd   = (e) => {
    if (touchStartX.current === null) return
    const dx = e.changedTouches[0].clientX - touchStartX.current
    if (dx < -40) next()
    else if (dx > 40) prev()
    touchStartX.current = null
  }

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 99999,
        background: 'rgba(0,0,0,0.92)',
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
      }}
      onClick={onClose}
    >
      {/* Close */}
      <button onClick={onClose} style={{
        position: 'absolute', top: 16, right: 16,
        background: 'rgba(255,255,255,0.1)', border: 'none',
        color: '#fff', borderRadius: '50%', width: 36, height: 36,
        fontSize: 18, cursor: 'pointer', zIndex: 2,
      }}>✕</button>

      {/* Counter */}
      <div style={{
        position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)',
        color: 'rgba(255,255,255,0.6)', fontSize: 13, fontFamily: 'Geist Mono, monospace',
      }}>
        {idx + 1} / {photos.length}
      </div>

      {/* Image */}
      <div
        style={{ maxWidth: '90vw', maxHeight: '70vh', position: 'relative' }}
        onClick={e => e.stopPropagation()}
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
      >
        <img
          src={ph.image_url}
          alt=""
          style={{
            maxWidth: '90vw', maxHeight: '70vh',
            objectFit: 'contain', borderRadius: 8,
            display: 'block',
          }}
        />

        {photos.length > 1 && (
          <>
            <button onClick={prev} style={{
              position: 'absolute', left: -44, top: '50%', transform: 'translateY(-50%)',
              background: 'rgba(255,255,255,0.15)', border: 'none', color: '#fff',
              borderRadius: '50%', width: 36, height: 36, fontSize: 20,
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>‹</button>
            <button onClick={next} style={{
              position: 'absolute', right: -44, top: '50%', transform: 'translateY(-50%)',
              background: 'rgba(255,255,255,0.15)', border: 'none', color: '#fff',
              borderRadius: '50%', width: 36, height: 36, fontSize: 20,
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>›</button>
          </>
        )}
      </div>

      {/* Meta below image */}
      <div
        onClick={e => e.stopPropagation()}
        style={{
          marginTop: 16, color: 'rgba(255,255,255,0.7)',
          fontSize: 12, textAlign: 'center', lineHeight: 1.8,
        }}
      >
        <div>🕐 {toPST(ph.timestamp)}</div>
        <div style={{fontFamily:'monospace', fontSize:11, opacity:0.6}}>
          📍 {ph.latitude?.toFixed(5)}, {ph.longitude?.toFixed(5)}
        </div>
        {ph.note && <div style={{marginTop:4, fontStyle:'italic', opacity:0.8}}>"{ph.note}"</div>}
      </div>

      {/* Dot strip */}
      {photos.length > 1 && (
        <div style={{ display: 'flex', gap: 6, marginTop: 16 }}>
          {photos.map((_, i) => (
            <button
              key={i}
              onClick={e => { e.stopPropagation(); setIdx(i) }}
              style={{
                width: idx === i ? 20 : 7, height: 7,
                borderRadius: 99, border: 'none',
                background: idx === i ? '#fff' : 'rgba(255,255,255,0.3)',
                cursor: 'pointer', padding: 0, transition: 'all 0.2s',
              }}
            />
          ))}
        </div>
      )}
    </div>
  )
}

function PhotoCard({ p, allPhotos, onPhotoClick, onNoteUpdated }) {
  const [note,       setNote]       = useState(p.note || '')
  const [editNote,   setEditNote]   = useState(false)
  const [savingNote, setSavingNote] = useState(false)
  const [replacing,  setReplacing]  = useState(false)
  const replaceRef = React.useRef()

  const saveNote = async () => {
    setSavingNote(true)
    await updatePhotoNote(p.id, note)
    setSavingNote(false)
    setEditNote(false)
    onNoteUpdated()
  }

  const handleReplace = async (e) => {
    const file = e.target.files[0]
    if (!file) return
    setReplacing(true)
    await replacePhotoImage(p.id, file)
    setReplacing(false)
    onNoteUpdated()
  }

  return (
    <div className="dk-photo-card">
      {/* Clickable image → opens lightbox */}
      <div style={{position:'relative', cursor:'pointer'}} onClick={() => onPhotoClick(p.id)}>
        <img
          src={p.image_url} alt=""
          onError={e => { e.target.src='https://via.placeholder.com/400x300/1e1b4b/6366f1?text=Photo' }}
        />
        {/* Replace button */}
        <div className="dk-photo-actions">
          <button
            className="dk-photo-btn"
            title="Replace image"
            onClick={e => { e.stopPropagation(); replaceRef.current.click() }}
            disabled={replacing}
          >
            {replacing
              ? <div className="dk-spinner" style={{width:10,height:10}}/>
              : <svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
            }
          </button>
        </div>
        {/* Expand hint */}
        <div style={{
          position:'absolute', bottom:6, right:6,
          background:'rgba(0,0,0,0.5)', color:'#fff',
          fontSize:10, padding:'2px 6px', borderRadius:4,
          pointerEvents:'none',
        }}>🔍 tap to expand</div>
        <input ref={replaceRef} type="file" accept="image/*" style={{display:'none'}} onChange={handleReplace} />
      </div>

      <div className="dk-photo-meta">
        {/* Timestamp */}
        <div style={{
          fontSize: 12, fontWeight: 600,
          color: 'var(--text-2, #475569)',
          marginBottom: 4,
        }}>
          🕐 {toPST(p.timestamp)}
        </div>

        {/* Coordinates */}
        <div style={{
          fontSize: 11, fontFamily: 'Geist Mono, monospace',
          color: 'var(--text-3, #64748b)',
          marginBottom: 6,
        }}>
          📍 {p.latitude?.toFixed(5)}, {p.longitude?.toFixed(5)}
        </div>

        {/* ── Note row — always visible, click to edit ── */}
        <div style={{
          padding: '6px 10px',
          background: 'var(--bg-subtle, #f8fafc)',
          border: '1px solid var(--border-c, #e2e8f0)',
          borderRadius: 7,
        }}>
          {editNote ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-2, #475569)', marginBottom: 0 }}>📝 Note</label>
              <textarea
                value={note}
                onChange={e => setNote(e.target.value)}
                rows={3}
                autoFocus
                placeholder="Add a note…"
                style={{
                  width: '100%', padding: '8px 10px', fontSize: 13,
                  background: 'var(--bg-input, #fff)',
                  border: '2px solid #6366f1',
                  borderRadius: 6, color: 'var(--text-1, #0f172a)',
                  outline: 'none', resize: 'vertical',
                  fontFamily: 'Geist, sans-serif', marginBottom: 0,
                  boxSizing: 'border-box',
                }}
              />
              <div style={{ display: 'flex', gap: 6 }}>
                <button
                  onClick={saveNote}
                  disabled={savingNote}
                  style={{
                    flex: 1, background: '#6366f1', color: '#fff', border: 'none',
                    borderRadius: 6, padding: '7px 0', fontSize: 12,
                    fontWeight: 700, cursor: 'pointer',
                  }}
                >
                  {savingNote ? 'Saving…' : '✓ Save'}
                </button>
                <button
                  onClick={() => { setEditNote(false); setNote(p.note || '') }}
                  style={{
                    flex: 1, background: 'transparent', color: 'var(--text-2, #475569)',
                    border: '1px solid var(--border-c, #e2e8f0)',
                    borderRadius: 6, padding: '7px 0', fontSize: 12,
                    cursor: 'pointer', fontWeight: 600,
                  }}
                >✕ Cancel</button>
              </div>
            </div>
          ) : (
            <div
              onClick={() => setEditNote(true)}
              style={{
                display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between',
                gap: 8, cursor: 'pointer',
              }}
            >
              <span style={{
                fontSize: 12, color: note ? 'var(--text-1, #0f172a)' : 'var(--text-3, #94a3b8)',
                fontStyle: note ? 'normal' : 'italic', lineHeight: 1.5, flex: 1,
              }}>
                {note || 'Add note…'}
              </span>
              <span style={{
                fontSize: 10, color: '#6366f1', fontWeight: 600,
                background: 'rgba(99,102,241,0.08)', padding: '2px 7px',
                borderRadius: 4, border: '1px solid rgba(99,102,241,0.2)',
                flexShrink: 0,
              }}>✏️ Edit</span>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

/* ── Add Pin Modal — pick location on map, upload a photo to this profile ── */
const pinIcon = new L.Icon({
  iconUrl:   'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-violet.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25,41], iconAnchor: [12,41],
})

function MapPicker({ location, onPick }) {
  useMapEvents({ click: e => onPick(e.latlng.lat, e.latlng.lng) })
  return location ? <Marker position={[location.lat, location.lng]} icon={pinIcon} /> : null
}

function AddPinModal({ profileId, profileName, onClose, onSaved }) {
  const geo = useContext(GeoContext)
  const [location,  setLocation]  = useState(geo.location || null)
  const [file,      setFile]      = useState(null)
  const [preview,   setPreview]   = useState(null)
  const [note,      setNote]      = useState('')
  const [uploading, setUploading] = useState(false)
  const [locBusy,   setLocBusy]   = useState(!geo.location)
  const fileRef   = React.useRef()

  // Use global geo first, then try fresh GPS
  React.useEffect(() => {
    if (geo.location) {
      setLocation(geo.location)
      setLocBusy(false)
      return
    }
    if (!navigator.geolocation) { setLocBusy(false); return }
    navigator.geolocation.getCurrentPosition(
      p => { setLocation({ lat: p.coords.latitude, lng: p.coords.longitude }); setLocBusy(false) },
      () => setLocBusy(false),
      { timeout: 8000, enableHighAccuracy: true }
    )
  }, [])

  const pickFile = (f) => { setFile(f); setPreview(URL.createObjectURL(f)) }

  const handleUpload = async () => {
    if (!file || !location) return
    setUploading(true)
    const fd = new FormData()
    fd.append('file',       file)
    fd.append('profile_id', profileId)
    fd.append('latitude',   location.lat)
    fd.append('longitude',  location.lng)
    fd.append('note',       note)
    try {
      await uploadPhoto(fd)
      onSaved()
    } catch { alert('Upload failed') }
    setUploading(false)
  }

  return (
    <div style={{
      position:'fixed', inset:0, background:'rgba(0,0,0,0.7)',
      zIndex:9999, display:'flex', alignItems:'center', justifyContent:'center',
    }}>
      <div style={{
        background:'#1e1b4b', borderRadius:16, width:'min(680px, 95vw)',
        maxHeight:'90vh', overflowY:'auto', padding:24,
        border:'1px solid rgba(255,255,255,0.1)',
        boxShadow:'0 24px 64px rgba(0,0,0,0.6)',
      }}>
        {/* Header */}
        <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:20}}>
          <div>
            <div style={{fontSize:16, fontWeight:700, color:'#fff'}}>📍 Add New Pin</div>
            <div style={{fontSize:12, color:'rgba(255,255,255,0.4)', marginTop:2}}>for {profileName}</div>
          </div>
          <button onClick={onClose} style={{background:'none', border:'none', color:'rgba(255,255,255,0.4)', fontSize:20, cursor:'pointer'}}>✕</button>
        </div>

        {/* Map */}
        <div style={{borderRadius:10, overflow:'hidden', height:260, marginBottom:12, border:'1px solid rgba(255,255,255,0.1)'}}>
          {locBusy ? (
            <div style={{height:'100%', display:'flex', alignItems:'center', justifyContent:'center', color:'rgba(255,255,255,0.4)', gap:10}}>
              <div className="dk-spinner"/> Acquiring GPS…
            </div>
          ) : location ? (
            <>
              <div style={{fontSize:11, color:'rgba(255,255,255,0.4)', padding:'6px 10px', background:'rgba(0,0,0,0.3)'}}>
                👆 Click the map to adjust pin location
              </div>
              <MapContainer center={[location.lat, location.lng]} zoom={15} style={{height:'calc(100% - 28px)', width:'100%'}}>
                <TileLayer
                  url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
                  attribution='&copy; OpenStreetMap &copy; CARTO'
                />
                <MapPicker location={location} onPick={(lat, lng) => setLocation({ lat, lng })} />
              </MapContainer>
            </>
          ) : (
            <div style={{height:'100%', display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', color:'rgba(255,255,255,0.4)', gap:8}}>
              <div>📍 No GPS available</div>
              <div style={{fontSize:11}}>Tap the map after enabling location</div>
            </div>
          )}
        </div>

        {location && (
          <div style={{fontSize:11, color:'rgba(255,255,255,0.4)', marginBottom:12, fontFamily:'monospace'}}>
            📍 {location.lat.toFixed(6)}, {location.lng.toFixed(6)}
          </div>
        )}

        {/* ── Photo — Gallery button ── */}
        <input ref={fileRef} type="file" accept="image/*" style={{display:'none'}}
          onChange={e => { const f = e.target.files[0]; if(f) pickFile(f) }} />

        {!file ? (
          <div style={{display:'flex', gap:8, marginBottom:12}}>
            <button
              className="btn btn-outline"
              style={{flex:1, justifyContent:'center', fontSize:13, padding:'10px'}}
              onClick={() => fileRef.current.click()}
            >
              🖼 Gallery
            </button>
          </div>
        ) : (
          <div style={{marginBottom:12, position:'relative'}}>
            <img src={preview} alt="" style={{width:'100%', maxHeight:180, objectFit:'cover', borderRadius:8, display:'block'}} />
            <button
              onClick={() => { setFile(null); setPreview(null); fileRef.current.value='' }}
              style={{position:'absolute', top:6, right:6, background:'rgba(0,0,0,0.65)', border:'none', color:'#fff', borderRadius:6, padding:'4px 10px', cursor:'pointer', fontSize:12, fontWeight:600}}
            >✕ Remove</button>
          </div>
        )}

        <div style={{marginBottom:16}}>
          <label style={{fontSize:11, color:'rgba(255,255,255,0.4)', display:'block', marginBottom:4}}>Note</label>
          <textarea
            value={note} onChange={e => setNote(e.target.value)}
            rows={2} placeholder="Add a note…"
            style={{
              width:'100%', padding:'8px 12px',
              background:'rgba(255,255,255,0.06)', border:'1px solid rgba(255,255,255,0.1)',
              borderRadius:8, fontSize:13, color:'#e2e8f0',
              outline:'none', resize:'vertical', fontFamily:'inherit',
            }}
          />
        </div>

        {/* Actions */}
        <div style={{display:'flex', gap:10}}>
          <button className="btn btn-outline" style={{flex:1, justifyContent:'center'}} onClick={onClose}>Cancel</button>
          <button
            className="btn btn-green"
            style={{flex:2, justifyContent:'center', opacity: (!file || !location) ? 0.5 : 1}}
            onClick={handleUpload}
            disabled={!file || !location || uploading}
          >
            {uploading ? '⏳ Uploading…' : '📍 Save Pin'}
          </button>
        </div>
      </div>
    </div>
  )
}
