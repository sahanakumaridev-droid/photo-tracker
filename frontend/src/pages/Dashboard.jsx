import React, { useEffect, useState, useCallback } from 'react'
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet'
import L from 'leaflet'
import { getPhotos, getProfiles, deletePhoto } from '../api'
import EditLocationModal from '../components/EditLocationModal'

delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl:       'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl:     'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
})

const youIcon = new L.Icon({
  iconUrl:   'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-gold.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25,41], iconAnchor: [12,41], popupAnchor: [1,-34],
})

// Photo thumbnail as map pin — rounded square
function photoIcon(imageUrl, serviceType) {
  const border = serviceType === 'rush' ? '#ef4444' : '#10b981'
  const html = `
    <div style="position:relative;">
      <div style="width:54px;height:54px;border-radius:10px;border:3px solid ${border};overflow:hidden;box-shadow:0 4px 12px rgba(0,0,0,0.25);background:#f5f5f4;cursor:pointer;">
        <img src="${imageUrl}" style="width:100%;height:100%;object-fit:cover;" onerror="this.src='https://via.placeholder.com/54x54/f5f5f4/a8a29e?text=📷'" />
      </div>
      <div style="width:0;height:0;border-left:7px solid transparent;border-right:7px solid transparent;border-top:9px solid ${border};margin:0 auto;"></div>
    </div>
  `
  return L.divIcon({ html, className: '', iconSize: [54,68], iconAnchor: [27,68], popupAnchor: [0,-70] })
}

function UserLocation() {
  const [pos, setPos] = useState(null)
  const map = useMap()
  useEffect(() => {
    navigator.geolocation?.getCurrentPosition(p => {
      const ll = [p.coords.latitude, p.coords.longitude]
      setPos(ll)
      map.flyTo(ll, 13)
    })
  }, [map])
  if (!pos) return null
  return (
    <Marker position={pos} icon={youIcon}>
      <Popup>
        <div className="popup-body">
          <div className="popup-name">You are here</div>
          <div className="popup-row">📍 Current location</div>
        </div>
      </Popup>
    </Marker>
  )
}

function FlyToFilter({ photos }) {
  const map = useMap()
  useEffect(() => {
    const valid = photos.filter(p => p.latitude && p.longitude)
    if (valid.length > 0) {
      map.flyTo([valid[0].latitude, valid[0].longitude], 13, { duration: 1 })
    }
  }, [photos, map])
  return null
}

const TABS = [
  { key: 'map',      label: 'Map',           icon: '🗺' },
  { key: 'recent',   label: 'Recent Photos', icon: '📷' },
  { key: 'rush',     label: 'Rush',          icon: '⚡' },
  { key: 'standard', label: 'Standard',      icon: '◈' },
]

export default function Dashboard() {
  const [photos,        setPhotos]        = useState([])
  const [profiles,      setProfiles]      = useState([])
  const [loading,       setLoading]       = useState(true)
  const [busy,          setBusy]          = useState(false)
  const [tab,           setTab]           = useState('map')
  const [filterProfile, setFilterProfile] = useState('all')

  const load = useCallback(async (silent = false) => {
    silent ? setBusy(true) : setLoading(true)
    const [ph, pr] = await Promise.all([getPhotos(), getProfiles()])
    setPhotos(ph); setProfiles(pr)
    setLoading(false); setBusy(false)
  }, [])

  useEffect(() => { load() }, [load])

  const rush     = profiles.filter(p => p.service_type === 'rush').length
  const standard = profiles.filter(p => p.service_type === 'standard').length

  const rushPhotos     = photos.filter(p => p.service_type === 'rush')
  const standardPhotos = photos.filter(p => p.service_type === 'standard')
  const recentPhotos   = photos.slice().reverse()

  const mapPhotos = filterProfile === 'all'
    ? photos
    : photos.filter(p => String(p.profile_id) === String(filterProfile))

  const selectedProfile = profiles.find(p => String(p.id) === String(filterProfile))

  const tabCounts = {
    map:      photos.length,
    recent:   photos.length,
    rush:     rushPhotos.length,
    standard: standardPhotos.length,
  }

  return (
    <div className="page">
      <div className="page-header">
        <div>
          <div className="page-title">Dashboard</div>
          <div className="page-sub">Live photo tracking overview</div>
        </div>
        <button className="btn btn-outline" onClick={() => load(true)} disabled={busy}>
          {busy ? <><div className="spinner" style={{width:13,height:13}}/>Refreshing</> : '↻ Refresh'}
        </button>
      </div>

      <div className="stats">
        <div className="stat"><div className="stat-val">{photos.length}</div><div className="stat-key">Total photos</div></div>
        <div className="stat"><div className="stat-val">{profiles.length}</div><div className="stat-key">Profiles</div></div>
        <div className="stat"><div className="stat-val red">{rush}</div><div className="stat-key">Rush</div></div>
        <div className="stat"><div className="stat-val green">{standard}</div><div className="stat-key">Standard</div></div>
      </div>

      <div className="tab-bar">
        {TABS.map(t => (
          <button key={t.key} className={`tab-btn ${tab === t.key ? 'tab-active' : ''}`} onClick={() => setTab(t.key)}>
            <span className="tab-icon">{t.icon}</span>
            {t.label}
            <span className="tab-count">{tabCounts[t.key]}</span>
          </button>
        ))}
      </div>

      <div className="tab-panel">
        {loading ? (
          <div className="loading"><div className="spinner"/>Loading…</div>
        ) : (
          <>
            {/* ── MAP ── */}
            {tab === 'map' && (
              <div className="card" style={{marginBottom:0}}>
                <div className="sec-header" style={{flexWrap:'wrap', gap:12}}>
                  <span className="sec-title">Photo Map</span>
                  <div className="profile-filter">
                    <button
                      className={`filter-pill ${filterProfile === 'all' ? 'filter-active' : ''}`}
                      onClick={() => setFilterProfile('all')}
                    >
                      All users <span className="filter-count">{photos.length}</span>
                    </button>
                    {profiles.map(p => {
                      const count = photos.filter(ph => ph.profile_id === p.id).length
                      return (
                        <button
                          key={p.id}
                          className={`filter-pill ${filterProfile === String(p.id) ? 'filter-active' : ''} filter-${p.service_type}`}
                          onClick={() => setFilterProfile(String(p.id))}
                        >
                          <span className="filter-avatar">{p.name.charAt(0)}</span>
                          {p.name.split(' ')[0]}
                          <span className="filter-count">{count}</span>
                        </button>
                      )
                    })}
                  </div>
                  <div className="map-legend">
                    <div className="legend-item"><div className="legend-dot" style={{background:'#ef4444'}}/>Rush</div>
                    <div className="legend-item"><div className="legend-dot" style={{background:'#10b981'}}/>Standard</div>
                    <div className="legend-item"><div className="legend-dot" style={{background:'#f59e0b'}}/>You</div>
                  </div>
                </div>

                {filterProfile !== 'all' && selectedProfile && (
                  <div className="filter-banner">
                    <div className={`filter-banner-avatar av-${selectedProfile.service_type}`}>
                      {selectedProfile.name.charAt(0)}
                    </div>
                    <span>Showing <strong>{selectedProfile.name}</strong>'s photos — <strong>{mapPhotos.length}</strong> pin{mapPhotos.length !== 1 ? 's' : ''}</span>
                    <span className={`badge badge-${selectedProfile.service_type}`}>{selectedProfile.service_type}</span>
                    <button className="filter-clear" onClick={() => setFilterProfile('all')}>✕ Clear</button>
                  </div>
                )}

                <div className="map-wrap">
                  <MapContainer center={[37.7749,-122.4194]} zoom={12} style={{height:'100%',width:'100%'}}>
                    <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="© OpenStreetMap contributors" />
                    <UserLocation />
                    <FlyToFilter photos={mapPhotos} />
                    {mapPhotos.map(ph => ph.latitude && ph.longitude && (
                      <Marker key={ph.id} position={[ph.latitude, ph.longitude]} icon={photoIcon(ph.image_url, ph.service_type)}>
                        <Popup>
                          <img src={ph.image_url} className="popup-img" alt="" onError={e => { e.target.style.display='none' }} />
                          <div className="popup-body">
                            <div className="popup-name">{ph.profile_name}</div>
                            <div style={{marginBottom:6}}><span className={`badge badge-${ph.service_type}`}>{ph.service_type}</span></div>
                            <div className="popup-row">🕐 {new Date(ph.timestamp).toLocaleString()}</div>
                            <div className="popup-row">📍 {ph.latitude?.toFixed(4)}, {ph.longitude?.toFixed(4)}</div>
                          </div>
                        </Popup>
                      </Marker>
                    ))}
                  </MapContainer>
                </div>

                {mapPhotos.length === 0 && filterProfile !== 'all' && (
                  <div className="empty" style={{padding:'24px 0 8px'}}>
                    <div className="empty-icon">📍</div>
                    <div className="empty-text">No photos from this user yet</div>
                  </div>
                )}
              </div>
            )}

            {tab === 'recent'   && <PhotoGrid photos={recentPhotos}   empty="No photos yet"          onDelete={id => { deletePhoto(id).then(() => load(true)) }} onEditLocation={load} />}
            {tab === 'rush'     && <PhotoGrid photos={rushPhotos}     empty="No rush photos yet"     onDelete={id => { deletePhoto(id).then(() => load(true)) }} onEditLocation={load} />}
            {tab === 'standard' && <PhotoGrid photos={standardPhotos} empty="No standard photos yet" onDelete={id => { deletePhoto(id).then(() => load(true)) }} onEditLocation={load} />}
          </>
        )}
      </div>
    </div>
  )
}

function PhotoGrid({ photos, empty, onDelete, onEditLocation }) {
  const [confirming, setConfirming] = useState(null)
  const [editing,    setEditing]    = useState(null)   // photo being location-edited

  if (photos.length === 0) return (
    <div className="empty"><div className="empty-icon">📷</div><div className="empty-text">{empty}</div></div>
  )
  return (
    <>
      {editing && (
        <EditLocationModal
          photo={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); onEditLocation(true) }}
        />
      )}
      <div className="photo-grid">
        {photos.map(p => (
          <div className="photo-card" key={p.id}>
            <div style={{position:'relative'}}>
              <img src={p.image_url} alt="" onError={e => { e.target.src='https://via.placeholder.com/400x300/f5f5f4/a8a29e?text=Photo' }} />
              <div className="photo-card-actions">
                {/* Edit location */}
                <button className="photo-action-btn" onClick={() => setEditing(p)} title="Edit location">📍</button>
                {/* Delete */}
                {confirming === p.id ? (
                  <div className="delete-confirm">
                    <span>Delete?</span>
                    <button className="del-yes" onClick={() => { onDelete(p.id); setConfirming(null) }}>Yes</button>
                    <button className="del-no"  onClick={() => setConfirming(null)}>No</button>
                  </div>
                ) : (
                  <button className="photo-action-btn photo-action-del" onClick={() => setConfirming(p.id)} title="Delete">✕</button>
                )}
              </div>
            </div>
            <div className="photo-meta-wrap">
              <div className="photo-name">{p.profile_name}</div>
              <div style={{marginBottom:5}}><span className={`badge badge-${p.service_type}`}>{p.service_type}</span></div>
              <div className="photo-meta">🕐 {new Date(p.timestamp).toLocaleString()}</div>
              <div className="photo-meta">📍 {p.latitude?.toFixed(4)}, {p.longitude?.toFixed(4)}</div>
            </div>
          </div>
        ))}
      </div>
    </>
  )
}
