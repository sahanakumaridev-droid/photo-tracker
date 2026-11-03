import React, { useEffect, useState, useCallback, useContext } from 'react'
import { MapContainer, TileLayer, Marker, Popup, Circle, useMap, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { useNavigate, useLocation } from 'react-router-dom'
import { getPhotos, getProfiles, getPhotosLive, getProfilesLive, deletePhoto, updatePhotoNote, replacePhotoImage, uploadPhoto } from '../api'
import EditLocationModal from '../components/EditLocationModal'
import MapUploadModal from '../components/MapUploadModal'
import MapFilterModal from '../components/MapFilterModal'
import { ProfilePills, GroupedPinPopup, PinPopup, PhotoGrid, PhotoList } from '../components/DashboardWidgets'
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

// OpenStreetMap — Carto's public light_all tiles now watermark "API KEY REQUIRED"
const MAP_TILE = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
const MAP_ATTR = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'

function MapClickHandler({ onMapClick }) {
  useMapEvents({ click: e => onMapClick(e.latlng.lat, e.latlng.lng) })
  return null
}

// Fits/flies the map to whatever the active filter implies:
//  - distance mode: the full radius circle around the user's location
//  - zip mode (or no filter): the bounding box of the matching pins
// Debounced slightly so dragging the distance slider doesn't fire a flight
// on every intermediate tick.
function MapAutoFit({ photos, geo, distanceMode, distanceMi }) {
  const map = useMap()
  useEffect(() => {
    const timer = setTimeout(() => {
      if (distanceMode === 'distance' && geo.location) {
        const center = L.latLng(geo.location.lat, geo.location.lng)
        const radiusMeters = Math.max(distanceMi, 0.5) * 1609.34
        map.flyToBounds(center.toBounds(radiusMeters * 2), { duration: 0.8, padding: [40, 40] })
        return
      }
      const valid = photos.filter(p => p.latitude && p.longitude)
      if (valid.length === 0) return
      if (valid.length === 1) {
        map.flyTo([valid[0].latitude, valid[0].longitude], 13, { duration: 0.8 })
        return
      }
      const bounds = L.latLngBounds(valid.map(p => [p.latitude, p.longitude]))
      map.flyToBounds(bounds, { duration: 0.8, padding: [40, 40] })
    }, 250)
    return () => clearTimeout(timer)
  }, [photos, geo.location, distanceMode, distanceMi, map])
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
  const [svcLevels,     setSvcLevels]     = useState(() => new Set())  // F2/F3 service-level filter (empty = all)
  // Map filter popup — distance (slider) OR zip; only one applies at a time,
  // whichever was touched most recently (distanceMode).
  const [showFilters,   setShowFilters]   = useState(false)
  const [distanceMi,    setDistanceMi]    = useState(100)          // 0–100 mi radius
  const [zipFilter,     setZipFilter]     = useState('')
  const [distanceMode,  setDistanceMode]  = useState(null)         // 'distance' | 'zip' | null

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

  // F2/F3 — service-level filter (empty set = show all); toggled from the
  // filter popup. Empty = show all levels.
  const matchLevel = (p) => svcLevels.size === 0 || svcLevels.has(p.category || 'standard')

  // Distance filter — radius from current location OR a ZIP match. Only the
  // most recently touched control (distanceMode) applies; the other is ignored.
  const matchDistance = (p) => {
    if (distanceMode === 'distance') {
      if (!geo.location || p.latitude == null || p.longitude == null) return true
      return distanceMiles(geo.location.lat, geo.location.lng, p.latitude, p.longitude) <= distanceMi
    }
    if (distanceMode === 'zip') {
      const z = String(zipFilter).trim()
      if (!z) return true
      const pz = (p.zip_code || '').trim()
      return pz ? pz === z : (p.address || '').includes(z)
    }
    return true
  }

  // Count of active filters (for the toolbar button badge).
  const activeFilterCount = svcLevels.size + (distanceMode ? 1 : 0)

  const mapPhotos = (filterProfile === 'all'
    ? photos
    : photos.filter(p => String(p.profile_id) === String(filterProfile))
  ).filter(matchLevel).filter(matchDistance)

  const filteredPhotos = photos.filter(p =>
    (!search || p.profile_name?.toLowerCase().includes(search.toLowerCase())) && matchLevel(p) && matchDistance(p)
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

        {/* Filter pins — opens the distance + service-level popup */}
        <button type="button" onClick={() => setShowFilters(true)} title="Filter pins"
          style={{
            display:'inline-flex', alignItems:'center', gap:7, cursor:'pointer',
            fontSize:12.5, fontWeight:700, padding:'7px 14px', borderRadius:99,
            border:'1px solid ' + (activeFilterCount > 0 ? '#7C3AED' : 'rgba(0,0,0,0.14)'),
            background: activeFilterCount > 0 ? 'rgba(124,58,237,0.08)' : 'transparent',
            color: activeFilterCount > 0 ? '#7C3AED' : '#64748b',
            transition:'all .15s ease',
          }}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
            <path d="M4 5h16M7 12h10M10 19h4" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
          </svg>
          Filters
          {activeFilterCount > 0 && (
            <span style={{ fontSize:10, fontWeight:800, minWidth:16, textAlign:'center', padding:'1px 5px',
              borderRadius:99, background:'#7C3AED', color:'#fff' }}>{activeFilterCount}</span>
          )}
        </button>
      </div>

      {/* ── Main content ── */}
      <div className="dk-content">
        {mapUpload && (
          <MapUploadModal lat={mapUpload.lat} lng={mapUpload.lng}
            onClose={() => setMapUpload(null)}
            onUploaded={() => { setMapUpload(null); load(true) }}/>
        )}

        {showFilters && (
          <MapFilterModal
            onClose={() => setShowFilters(false)}
            geo={geo}
            photos={photos}
            svcLevels={svcLevels}       setSvcLevels={setSvcLevels}
            distanceMi={distanceMi}     setDistanceMi={setDistanceMi}
            zipFilter={zipFilter}       setZipFilter={setZipFilter}
            distanceMode={distanceMode} setDistanceMode={setDistanceMode}
            distanceMiles={distanceMiles}
          />
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
                  <MapAutoFit photos={mapPhotos} geo={geo} distanceMode={distanceMode} distanceMi={distanceMi}/>
                  <MapClickHandler onMapClick={(lat, lng) => setMapUpload({ lat, lng })}/>
                  {/* Visualize the active radius filter */}
                  {distanceMode === 'distance' && geo.location && (
                    <Circle
                      center={[geo.location.lat, geo.location.lng]}
                      radius={distanceMi * 1609.34}
                      pathOptions={{ color: '#7C3AED', weight: 2, fillColor: '#7C3AED', fillOpacity: 0.07 }}
                    />
                  )}
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

