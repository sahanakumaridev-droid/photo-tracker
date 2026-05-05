import React, { useEffect, useState, useCallback } from 'react'
import { MapContainer, TileLayer, Marker, Popup, useMap, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { useNavigate } from 'react-router-dom'
import { getPhotos, getProfiles, getPhotosLive, getProfilesLive, deletePhoto, updatePhotoNote, replacePhotoImage } from '../api'
import EditLocationModal from '../components/EditLocationModal'
import MapUploadModal from '../components/MapUploadModal'
import { useTheme } from '../context/ThemeContext'

delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl:       'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl:     'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
})

function photoIcon(imageUrl, serviceType) {
  const color = serviceType === 'rush' ? '#f43f5e' : '#10b981'
  const glow  = serviceType === 'rush' ? 'rgba(244,63,94,0.5)' : 'rgba(16,185,129,0.5)'
  const html = `
    <div style="position:relative;display:flex;flex-direction:column;align-items:center;">
      <div style="width:48px;height:48px;border-radius:50%;border:2.5px solid ${color};overflow:hidden;
        box-shadow:0 0 0 4px ${glow},0 4px 16px rgba(0,0,0,0.5);background:#1e1b4b;cursor:pointer;">
        <img src="${imageUrl}" style="width:100%;height:100%;object-fit:cover;"
          onerror="this.src='https://via.placeholder.com/48x48/1e1b4b/6366f1?text=📷'" />
      </div>
      <div style="width:2px;height:8px;background:${color};margin-top:-1px;"></div>
      <div style="width:6px;height:6px;border-radius:50%;background:${color};margin-top:-1px;box-shadow:0 0 6px ${color};"></div>
    </div>`
  return L.divIcon({ html, className: '', iconSize: [48, 68], iconAnchor: [24, 68], popupAnchor: [0, -72] })
}

function MapClickHandler({ onMapClick }) {
  useMapEvents({ click: e => onMapClick(e.latlng.lat, e.latlng.lng) })
  return null
}

function FlyToFilter({ photos }) {
  const map = useMap()
  useEffect(() => {
    const valid = photos.filter(p => p.latitude && p.longitude)
    if (valid.length > 0) map.flyTo([valid[0].latitude, valid[0].longitude], 13, { duration: 1 })
  }, [photos, map])
  return null
}

const VIEWS = [
  { key: 'map',    label: 'Map View',
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><path d="M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z" fill="currentColor"/></svg> },
  { key: 'grid',   label: 'Grid View',
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="7" height="7" rx="1" fill="currentColor"/><rect x="14" y="3" width="7" height="7" rx="1" fill="currentColor"/><rect x="3" y="14" width="7" height="7" rx="1" fill="currentColor"/><rect x="14" y="14" width="7" height="7" rx="1" fill="currentColor"/></svg> },
  { key: 'list',   label: 'List View',
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><line x1="8" y1="6" x2="21" y2="6" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><line x1="8" y1="12" x2="21" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><line x1="8" y1="18" x2="21" y2="18" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><circle cx="3" cy="6" r="1.5" fill="currentColor"/><circle cx="3" cy="12" r="1.5" fill="currentColor"/><circle cx="3" cy="18" r="1.5" fill="currentColor"/></svg> },
]

export default function Dashboard() {
  const [photos,        setPhotos]        = useState([])
  const [profiles,      setProfiles]      = useState([])
  const [loading,       setLoading]       = useState(true)
  const [busy,          setBusy]          = useState(false)
  const [view,          setView]          = useState('map')
  const [filterProfile, setFilterProfile] = useState('all')
  const [mapUpload,     setMapUpload]     = useState(null)
  const [search,        setSearch]        = useState('')

  const { accentPreset, setSettings } = useTheme()

  const load = useCallback(async (silent = false) => {
    if (!silent && photos.length === 0 && profiles.length === 0) setLoading(true)
    setBusy(true)
    await Promise.all([
      getPhotosLive(data => { setPhotos(data); setLoading(false) }),
      getProfilesLive(data => { setProfiles(data) }),
    ])
    setBusy(false)
  }, [])

  useEffect(() => { load() }, [load])

  const rush     = profiles.filter(p => p.service_type === 'rush').length
  const standard = profiles.filter(p => p.service_type === 'standard').length

  const mapPhotos = filterProfile === 'all'
    ? photos
    : photos.filter(p => String(p.profile_id) === String(filterProfile))

  const selectedProfile = profiles.find(p => String(p.id) === String(filterProfile))

  const filteredPhotos = photos.filter(p =>
    !search || p.profile_name?.toLowerCase().includes(search.toLowerCase())
  )

  const STATS = [
    {
      val: photos.length, label: 'Total Photos', color: '#6366f1',
      bar: 100,
      icon: <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z" fill="currentColor"/></svg>,
    },
    {
      val: profiles.length, label: 'Profiles', color: '#8b5cf6',
      bar: profiles.length > 0 ? Math.min(100, profiles.length * 10) : 0,
      icon: <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z" fill="currentColor"/></svg>,
    },
    {
      val: rush, label: 'Rush Priority', color: '#f43f5e',
      bar: profiles.length > 0 ? Math.round((rush / profiles.length) * 100) : 0,
      icon: <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M7 2v11h3v9l7-12h-4l4-8z" fill="currentColor"/></svg>,
    },
    {
      val: standard, label: 'Standard', color: '#10b981',
      bar: profiles.length > 0 ? Math.round((standard / profiles.length) * 100) : 0,
      icon: <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" fill="currentColor"/></svg>,
    },
    {
      val: `${photos.filter(p => p.latitude && p.longitude).length}`, label: 'Geotagged', color: '#f59e0b',
      bar: photos.length > 0 ? Math.round((photos.filter(p => p.latitude && p.longitude).length / photos.length) * 100) : 0,
      icon: <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/></svg>,
    },
  ]

  return (
    <div className="dk-shell">

      {/* ── Top header bar ── */}
      <div className="dk-header">
        <div className="dk-header-left">
          <button className="dk-menu-btn">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
              <line x1="3" y1="6"  x2="21" y2="6"  stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="3" y1="12" x2="21" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="3" y1="18" x2="21" y2="18" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
            </svg>
          </button>
          <div>
            <div className="dk-header-title">Map View</div>
            <div className="dk-header-sub">Live photo tracking overview</div>
          </div>
        </div>

        <div className="dk-header-right">
          {/* View switcher */}
          <div className="dk-view-switch">
            {VIEWS.map(v => (
              <button key={v.key} className={`dk-view-btn ${view === v.key ? 'dk-view-active' : ''}`}
                onClick={() => setView(v.key)} title={v.label}>
                {v.icon}
              </button>
            ))}
          </div>

          <button className="dk-refresh-btn" onClick={() => load(true)} disabled={busy} title="Refresh">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" style={{transform: busy ? 'rotate(360deg)' : 'none', transition: busy ? 'transform 1s linear' : 'none'}}>
              <path d="M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z" fill="currentColor"/>
            </svg>
          </button>

          <div className="dk-header-user" onClick={() => setSettings(true)} title="Settings" style={{cursor:'pointer'}}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><path d="M12 12c2.7 0 4.8-2.1 4.8-4.8S14.7 2.4 12 2.4 7.2 4.5 7.2 7.2 9.3 12 12 12zm0 2.4c-3.2 0-9.6 1.6-9.6 4.8v2.4h19.2v-2.4c0-3.2-6.4-4.8-9.6-4.8z" fill="currentColor"/></svg>
          </div>
        </div>
      </div>

      {/* ── Stat cards row ── */}
      <div className="dk-stats">
        {STATS.map((s, i) => (
          <div className="dk-stat" key={i} style={{'--accent': s.color}}>
            <div className="dk-stat-icon" style={{color: s.color}}>{s.icon}</div>
            <div className="dk-stat-body">
              <div className="dk-stat-val">{s.val}</div>
              <div className="dk-stat-label">{s.label}</div>
              <div className="dk-stat-bar-track">
                <div className="dk-stat-bar-fill" style={{width: `${s.bar}%`, background: s.color}}/>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* ── Search + filter toolbar ── */}
      <div className="dk-toolbar">
        <div className="dk-search">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
            <circle cx="11" cy="11" r="8" stroke="currentColor" strokeWidth="2"/>
            <path d="m21 21-4.35-4.35" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
          </svg>
          <input placeholder="Search profiles…" value={search} onChange={e => setSearch(e.target.value)}/>
        </div>

        <ProfilePills
          profiles={profiles}
          photos={photos}
          filterProfile={filterProfile}
          setFilterProfile={setFilterProfile}
        />

        <div className="dk-legend">
          <span className="dk-legend-item"><span className="dk-legend-dot" style={{background:'#f43f5e', boxShadow:'0 0 6px #f43f5e'}}/>Rush</span>
          <span className="dk-legend-item"><span className="dk-legend-dot" style={{background:'#10b981', boxShadow:'0 0 6px #10b981'}}/>Standard</span>
        </div>
      </div>

      {/* ── Main content ── */}
      <div className="dk-content">
        {mapUpload && (
          <MapUploadModal lat={mapUpload.lat} lng={mapUpload.lng}
            onClose={() => setMapUpload(null)}
            onUploaded={() => { setMapUpload(null); load(true) }}/>
        )}

        {loading ? (
          <div className="dk-loading">
            <div className="dk-spinner"/>
            <span>Loading data…</span>
          </div>
        ) : (
          <>
            {/* MAP VIEW — fills entire content area */}
            {view === 'map' && (
              <div className="dk-map-wrap">
                <div className="dk-map-hint">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/></svg>
                  Click anywhere to upload a photo at that location
                </div>
                <MapContainer center={[32.7157,-117.1611]} zoom={13} style={{height:'100%',width:'100%'}} zoomControl={true}>
                  <TileLayer
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                  />
                  <FlyToFilter photos={mapPhotos}/>
                  <MapClickHandler onMapClick={(lat, lng) => setMapUpload({ lat, lng })}/>
                  {/* Group photos by exact lat/lng — show all in one popup */}
                  {Object.values(
                    mapPhotos
                      .filter(ph => ph.latitude && ph.longitude)
                      .reduce((acc, ph) => {
                        const key = `${ph.latitude.toFixed(6)}_${ph.longitude.toFixed(6)}`
                        if (!acc[key]) acc[key] = []
                        acc[key].push(ph)
                        return acc
                      }, {})
                  ).map(group => {
                    const first = group[0]
                    // pick dominant service type for pin color (rush wins)
                    const svcType = group.some(p => p.service_type === 'rush') ? 'rush' : 'standard'
                    return (
                      <Marker
                        key={`${first.latitude}_${first.longitude}`}
                        position={[first.latitude, first.longitude]}
                        icon={photoIcon(first.image_url, svcType)}
                      >
                        <Popup className="dk-popup">
                          <GroupedPinPopup photos={group} onUpdated={() => load(true)} />
                        </Popup>
                      </Marker>
                    )
                  })}
                </MapContainer>
              </div>
            )}

            {/* GRID VIEW */}
            {view === 'grid' && (
              <div className="dk-scroll-area">
                <PhotoGrid
                  photos={filteredPhotos.slice().reverse()}
                  empty="No photos yet"
                  onDelete={id => deletePhoto(id).then(() => load(true))}
                  onEditLocation={load}
                />
              </div>
            )}

            {/* LIST VIEW */}
            {view === 'list' && (
              <div className="dk-scroll-area">
                <PhotoList
                  photos={filteredPhotos.slice().reverse()}
                  empty="No photos yet"
                  onDelete={id => deletePhoto(id).then(() => load(true))}
                  onEditLocation={load}
                />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

/* ── Profile Pills with overflow dropdown ── */
const MAX_VISIBLE = 4

function ProfilePills({ profiles, photos, filterProfile, setFilterProfile }) {
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

/* ── Grouped Pin Popup — multiple photos at same location ── */
function GroupedPinPopup({ photos, onUpdated }) {
  const [activeIdx, setActiveIdx] = useState(0)
  const ph = photos[activeIdx]

  return (
    <div style={{ minWidth: 240, maxWidth: 280 }}>
      {/* If multiple photos — show tab strip */}
      {photos.length > 1 && (
        <div style={{
          display: 'flex', gap: 4, padding: '8px 10px 0',
          background: '#0f0e1a', flexWrap: 'wrap',
          borderRadius: '6px 6px 0 0',
        }}>
          {photos.map((p, i) => {
            const color = p.service_type === 'rush' ? '#ef4444' : '#10b981'
            return (
              <button
                key={p.id}
                onClick={() => setActiveIdx(i)}
                style={{
                  display: 'flex', alignItems: 'center', gap: 5,
                  padding: '4px 8px', borderRadius: 6, border: 'none',
                  background: activeIdx === i ? color : 'rgba(255,255,255,0.08)',
                  color: activeIdx === i ? '#fff' : 'rgba(255,255,255,0.5)',
                  fontSize: 11, fontWeight: 700, cursor: 'pointer',
                  fontFamily: 'Geist, sans-serif',
                  transition: 'all 0.12s',
                }}
              >
                <img
                  src={p.image_url}
                  style={{ width: 18, height: 18, borderRadius: '50%', objectFit: 'cover' }}
                  onError={e => { e.target.style.display = 'none' }}
                />
                {p.profile_name?.split(' ')[0] || `#${p.id}`}
              </button>
            )
          })}
          <span style={{
            marginLeft: 'auto', fontSize: 10,
            color: 'rgba(255,255,255,0.3)',
            alignSelf: 'center', fontFamily: 'Geist Mono, monospace',
          }}>
            {photos.length} at this pin
          </span>
        </div>
      )}

      {/* Active photo detail */}
      <PinPopup ph={ph} onNoteUpdated={onUpdated} />
    </div>
  )
}

/* ── Pin Popup (shows all profiles at this pin + editable note) ── */
function PinPopup({ ph, onNoteUpdated }) {
  const [note,    setNote]    = useState(ph.note || '')
  const [editing, setEditing] = useState(false)
  const [saving,  setSaving]  = useState(false)
  const navigate = useNavigate()

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
      <img src={ph.image_url} className="popup-img" alt=""
        onError={e => { e.target.style.display = 'none' }} />
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

        <div className="popup-row" style={{ marginTop: 8 }}>🕐 {new Date(ph.timestamp).toLocaleString()}</div>
        <div className="popup-row">📍 {ph.latitude?.toFixed(4)}, {ph.longitude?.toFixed(4)}</div>
        {ph.zip_code && <div className="popup-row">📮 {ph.zip_code}</div>}

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
function PhotoGrid({ photos, empty, onDelete, onEditLocation }) {
  const [confirming, setConfirming] = useState(null)
  const [editing,    setEditing]    = useState(null)
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
      {editing && <EditLocationModal photo={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); onEditLocation(true) }}/>}
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
                <button className="dk-photo-btn" onClick={() => setEditing(p)} title="Edit location">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z" fill="currentColor"/></svg>
                </button>
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
function PhotoList({ photos, empty, onDelete, onEditLocation }) {
  const [confirming, setConfirming] = useState(null)
  const [editing,    setEditing]    = useState(null)

  if (photos.length === 0) return (
    <div className="dk-empty"><div>{empty}</div></div>
  )
  return (
    <>
      {editing && <EditLocationModal photo={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); onEditLocation(true) }}/>}
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
              <button className="dk-list-btn" onClick={() => setEditing(p)} title="Edit location">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z" fill="currentColor"/></svg>
              </button>
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
