import React, { useEffect, useState, useCallback, useContext } from 'react'
import { MapContainer, TileLayer, Marker, Popup, useMap, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { useNavigate, useLocation } from 'react-router-dom'
import { getPhotos, getProfiles, getPhotosLive, getProfilesLive, deletePhoto, updatePhotoNote, replacePhotoImage, uploadPhoto } from '../api'
import EditLocationModal from '../components/EditLocationModal'
import MapUploadModal from '../components/MapUploadModal'
import { useTheme } from '../context/ThemeContext'
import { GeoContext } from '../context/GeoContext'

delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl:       'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl:     'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
})

// PST formatter
function toPST(ts) {
  if (!ts) return ''
  return new Date(ts).toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    month: 'short', day: 'numeric', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }) + ' PST'
}

// Haversine distance in miles
function distanceMiles(lat1, lng1, lat2, lng2) {
  const R = 3958.8
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
}

// Pin icon uses the LATEST photo image at that location
function photoIcon(imageUrl, serviceType) {
  const color = serviceType === 'rush' ? '#ef4444' : '#0ea5e9'
  const glow  = serviceType === 'rush' ? 'rgba(239,68,68,0.35)' : 'rgba(14,165,233,0.35)'
  const html = `
    <div style="position:relative;display:flex;flex-direction:column;align-items:center;">
      <div style="width:48px;height:48px;border-radius:50%;border:2.5px solid ${color};overflow:hidden;
        box-shadow:0 0 0 4px ${glow},0 4px 16px rgba(0,0,0,0.25);background:#e2e8f0;cursor:pointer;">
        <img src="${imageUrl}" style="width:100%;height:100%;object-fit:cover;"
          onerror="this.src='https://via.placeholder.com/48x48/e2e8f0/64748b?text=📷'" />
      </div>
      <div style="width:2px;height:8px;background:${color};margin-top:-1px;"></div>
      <div style="width:6px;height:6px;border-radius:50%;background:${color};margin-top:-1px;box-shadow:0 0 6px ${color};"></div>
    </div>`
  return L.divIcon({ html, className: '', iconSize: [48, 68], iconAnchor: [24, 68], popupAnchor: [0, -72] })
}

// Soft map tile — CartoDB Positron (whites, greys, blues)
const MAP_TILE = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png'
const MAP_ATTR = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'

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
  const geo = useContext(GeoContext)
  const location = useLocation()

  const load = useCallback(async (silent = false) => {
    if (!silent && photos.length === 0 && profiles.length === 0) setLoading(true)
    setBusy(true)
    await Promise.all([
      getPhotosLive(data => { setPhotos(data); setLoading(false) }),
      getProfilesLive(data => { setProfiles(data) }),
    ])
    setBusy(false)
  }, [])

  // Initial load
  useEffect(() => { load() }, [load])

  // Re-fetch every time the user navigates back to the dashboard
  // This ensures a newly uploaded photo always appears immediately
  useEffect(() => {
    if (location.pathname === '/') {
      load(true)
    }
  }, [location.pathname])

  const rush     = profiles.filter(p => p.service_type === 'rush').length
  const standard = profiles.filter(p => p.service_type === 'standard').length

  // Sort profiles by proximity to user's current location
  const sortedProfiles = geo.location
    ? [...profiles].sort((a, b) => {
        const aPhoto = photos.find(ph => ph.profile_id === a.id && ph.latitude)
        const bPhoto = photos.find(ph => ph.profile_id === b.id && ph.latitude)
        if (!aPhoto && !bPhoto) return 0
        if (!aPhoto) return 1
        if (!bPhoto) return -1
        const dA = distanceMiles(geo.location.lat, geo.location.lng, aPhoto.latitude, aPhoto.longitude)
        const dB = distanceMiles(geo.location.lat, geo.location.lng, bPhoto.latitude, bPhoto.longitude)
        return dA - dB
      })
    : profiles

  // Center map on user's location when it first arrives
  const mapCenter = geo.location
    ? [geo.location.lat, geo.location.lng]
    : [32.7157, -117.1611]

  const mapPhotos = filterProfile === 'all'
    ? photos
    : photos.filter(p => String(p.profile_id) === String(filterProfile))

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
        {/* Decorative background circles */}
        <div className="dk-header-circle dk-header-circle-1" />
        <div className="dk-header-circle dk-header-circle-2" />
        <div className="dk-header-circle dk-header-circle-3" />

        {/* Top row: logo + settings */}
        <div className="dk-header-top">
          <div className="dk-header-brand">
            <div className="dk-header-logo">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
                <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/>
              </svg>
            </div>
            <span className="dk-header-brand-name">GeoTag</span>
          </div>
          <div className="dk-header-top-right">
            {/* View switcher */}
            <div className="dk-view-switch">
              {VIEWS.map(v => (
                <button key={v.key} className={`dk-view-btn ${view === v.key ? 'dk-view-active' : ''}`}
                  onClick={() => setView(v.key)} title={v.label}>
                  {v.icon}
                </button>
              ))}
            </div>
            <div className="dk-header-user" onClick={() => setSettings(true)} title="Settings" style={{cursor:'pointer'}}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><path d="M12 12c2.7 0 4.8-2.1 4.8-4.8S14.7 2.4 12 2.4 7.2 4.5 7.2 7.2 9.3 12 12 12zm0 2.4c-3.2 0-9.6 1.6-9.6 4.8v2.4h19.2v-2.4c0-3.2-6.4-4.8-9.6-4.8z" fill="currentColor"/></svg>
            </div>
          </div>
        </div>

        {/* Bottom row: greeting */}
        <div className="dk-header-greeting">
          <div className="dk-header-title">
            Good morning, Admin 👋
          </div>
          <div className="dk-header-sub">
            {new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })}
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
          profiles={sortedProfiles}
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
                <MapContainer center={mapCenter} zoom={13} style={{height:'100%',width:'100%'}} zoomControl={true}>
                  <TileLayer
                    url={MAP_TILE}
                    attribution={MAP_ATTR}
                  />
                  <FlyToFilter photos={mapPhotos}/>
                  <MapClickHandler onMapClick={(lat, lng) => setMapUpload({ lat, lng })}/>
                  {/* Group photos by lat/lng, then sub-group by profile */}
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
                    // Sort all photos newest first
                    const sorted = [...group].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
                    const latest = sorted[0]
                    const svcType = sorted.some(p => p.service_type === 'rush') ? 'rush' : 'standard'

                    // Sub-group by profile_id → { profileId: { profile info, photos[] } }
                    const byProfile = {}
                    sorted.forEach(ph => {
                      const pid = ph.profile_id || 'unknown'
                      if (!byProfile[pid]) {
                        byProfile[pid] = {
                          profileId:   pid,
                          profileName: ph.profile_name || 'Unknown',
                          serviceType: ph.service_type || 'standard',
                          photos:      [],
                        }
                      }
                      byProfile[pid].photos.push(ph)
                    })
                    const profileGroups = Object.values(byProfile)

                    return (
                      <Marker
                        key={`${latest.latitude}_${latest.longitude}`}
                        position={[latest.latitude, latest.longitude]}
                        icon={photoIcon(latest.image_url, svcType)}
                      >
                        <Popup className="dk-popup">
                          <GroupedPinPopup
                            profileGroups={profileGroups}
                            lat={latest.latitude}
                            lng={latest.longitude}
                            onUpdated={() => load(true)}
                          />
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

/* ── Grouped Pin Popup — profile tabs + per-profile photo carousel ── */
function GroupedPinPopup({ profileGroups, lat, lng, onUpdated }) {
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
function PinAddPhotoForm({ lat, lng, profileId, onDone }) {
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
    const fd = new FormData()
    fd.append('file',       file)
    fd.append('profile_id', selProfile)
    fd.append('latitude',   lat)
    fd.append('longitude',  lng)
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
              flex: 1, padding: '8px', background: 'rgba(99,102,241,0.2)',
              border: '1px solid rgba(99,102,241,0.4)', borderRadius: 6,
              color: '#a5b4fc', fontSize: 12, fontWeight: 700, cursor: 'pointer',
            }}
            onClick={() => {
              const input = document.createElement('input')
              input.type = 'file'; input.accept = 'image/*'; input.capture = 'environment'
              input.onchange = e => { const f = e.target.files[0]; if(f) pickFile(f) }
              input.click()
            }}
          >📷 Camera</button>
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
function PinPopup({ ph, onNoteUpdated }) {
  const [note,    setNote]    = useState(ph.note || '')
  const [editing, setEditing] = useState(false)
  const [saving,  setSaving]  = useState(false)
  const [address, setAddress] = useState('')
  const navigate = useNavigate()

  // Reverse geocode on mount
  useEffect(() => {
    if (!ph.latitude || !ph.longitude) return
    fetch(
      `https://nominatim.openstreetmap.org/reverse?format=json&lat=${ph.latitude}&lon=${ph.longitude}&zoom=16`,
      { headers: { 'Accept-Language': 'en' } }
    )
      .then(r => r.json())
      .then(data => {
        if (data?.address) {
          const a = data.address
          const parts = [
            a.road || a.pedestrian,
            a.suburb || a.city_district,
            a.city || a.town || a.village,
            a.state,
          ].filter(Boolean)
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
