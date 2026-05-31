import React, { useEffect, useState, useContext } from 'react'
import { useNavigate } from 'react-router-dom'
import { getProfilesLive, getPhotosLive, createProfile, deleteProfile } from '../api'
import { GeoContext } from '../context/GeoContext'

// Haversine distance in miles
function distanceMiles(lat1, lng1, lat2, lng2) {
  const R = 3958.8
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
}

// Priority categories — most urgent first: Red ASAP · Orange Special · Yellow Next Day · Green Standard
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
function catOf(v) {
  const n = normalizeCat(v)
  return CATEGORIES.find(c => c.value === n) || CATEGORIES[0]
}

export default function Profiles({ showToast }) {
  const [profiles, setProfiles] = useState([])
  const [photos,   setPhotos]   = useState([])
  const [loading,  setLoading]  = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [name,     setName]     = useState('')
  const [svcType,  setSvcType]  = useState('standard')
  const [saving,   setSaving]   = useState(false)
  const [search,   setSearch]   = useState('')
  const [sortBy,   setSortBy]   = useState('proximity') // 'proximity' | 'status'
  const [viewMode, setViewMode] = useState('cards')      // 'cards' | 'table'
  const [expandedCats, setExpandedCats] = useState({})  // { [category]: bool }
  const navigate = useNavigate()
  const geo = useContext(GeoContext)

  const SECTION_LIMIT = 12  // cards shown before "Show all"
  const toggleExpand = (cat) =>
    setExpandedCats(prev => ({ ...prev, [cat]: !prev[cat] }))

  const load = async () => {
    await Promise.all([
      getProfilesLive(data => { setProfiles(data); setLoading(false) }),
      getPhotosLive(data => setPhotos(data)),
    ])
  }

  useEffect(() => { load() }, [])

  const handleCreate = async (e) => {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    const fd = new FormData()
    fd.append('name', name)
    fd.append('service_type', svcType)
    try {
      await createProfile(fd)
      showToast('Profile created')
      setName(''); setSvcType('standard'); setShowForm(false)
      load()
    } catch { showToast('Failed to create profile', 'error') }
    setSaving(false)
  }

  const handleDelete = async (id) => {
    try {
      await deleteProfile(id)
      showToast('Profile deleted')
      load()
    } catch { showToast('Failed to delete profile', 'error') }
  }

  const countFor = (cat) =>
    profiles.filter(p => normalizeCat(p.service_type) === cat).length

  // Sort by proximity or status
  const sortProfiles = (list) => {
    if (sortBy === 'proximity' && geo.location) {
      return [...list].sort((a, b) => {
        const aPhoto = photos.find(ph => ph.profile_id === a.id && ph.latitude)
        const bPhoto = photos.find(ph => ph.profile_id === b.id && ph.latitude)
        if (!aPhoto && !bPhoto) return 0
        if (!aPhoto) return 1
        if (!bPhoto) return -1
        const dA = distanceMiles(geo.location.lat, geo.location.lng, aPhoto.latitude, aPhoto.longitude)
        const dB = distanceMiles(geo.location.lat, geo.location.lng, bPhoto.latitude, bPhoto.longitude)
        return dA - dB
      })
    }
    return list
  }

  const filtered = profiles.filter(p =>
    !search || p.name.toLowerCase().includes(search.toLowerCase())
  )
  const groupFor = (cat) =>
    sortProfiles(filtered.filter(p => normalizeCat(p.service_type) === cat))

  return (
    <div className="pr-shell">

      {/* ── Header ── */}
      <div className="pr-header">
        <div className="pr-header-left">
          <div className="pr-header-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
              <circle cx="9" cy="7" r="4" fill="currentColor"/>
              <path d="M2 21v-1a7 7 0 0 1 14 0v1" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <circle cx="19" cy="8" r="3" fill="currentColor" opacity="0.5"/>
              <path d="M22 21v-1a5 5 0 0 0-5-5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" opacity="0.5"/>
            </svg>
          </div>
          <div>
            <h1 className="pr-header-title">Profiles</h1>
            <p className="pr-header-sub">
              {profiles.length} total
              {CATEGORIES.map(c => countFor(c.value) > 0 && (
                <span key={c.value}> · <span style={{ color: c.color, fontWeight: 700 }}>{countFor(c.value)} {c.label}</span></span>
              ))}
            </p>
          </div>
        </div>

        <div className="pr-header-right">
          {/* Search */}
          <div className="pr-search">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
              <circle cx="11" cy="11" r="8" stroke="currentColor" strokeWidth="2"/>
              <path d="m21 21-4.35-4.35" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
            </svg>
            <input placeholder="Search profiles…" value={search} onChange={e => setSearch(e.target.value)}/>
          </div>

          {/* Sort toggle */}
          <button
            className="btn btn-outline"
            style={{ fontSize: 11, padding: '5px 10px' }}
            onClick={() => setSortBy(v => v === 'proximity' ? 'status' : 'proximity')}
            title={sortBy === 'proximity' ? 'Sorted by proximity' : 'Sorted by status'}
          >
            {sortBy === 'proximity' ? '📍 Proximity' : '⚡ Status'}
          </button>

          {/* Cards / Table view toggle */}
          <div style={{ display: 'inline-flex', background: '#f1f5f9', borderRadius: 9, padding: 3, gap: 2 }}>
            {[['cards', '▦ Cards'], ['table', '☰ Table']].map(([v, lbl]) => (
              <button
                key={v}
                onClick={() => setViewMode(v)}
                style={{
                  border: 'none', cursor: 'pointer', fontSize: 11.5, fontWeight: 700,
                  padding: '5px 12px', borderRadius: 7,
                  background: viewMode === v ? '#fff' : 'transparent',
                  color: viewMode === v ? '#0f172a' : '#64748b',
                  boxShadow: viewMode === v ? '0 1px 4px rgba(15,23,42,0.12)' : 'none',
                }}
              >{lbl}</button>
            ))}
          </div>

          <button
            className={`pr-new-btn ${showForm ? 'pr-new-btn-cancel' : ''}`}
            onClick={() => setShowForm(v => !v)}
          >
            {showForm ? (
              <>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z" fill="currentColor"/></svg>
                Cancel
              </>
            ) : (
              <>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z" fill="currentColor"/></svg>
                New Profile
              </>
            )}
          </button>
        </div>
      </div>

      {/* ── Stats bar ── */}
      <div className="pr-stat-row">
        <div className="pr-stat-pill">
          <div>
            <div className="pr-stat-pill-val">{profiles.length}</div>
            <div className="pr-stat-pill-key">Total Profiles</div>
          </div>
        </div>
        {CATEGORIES.map(c => (
          <div key={c.value} className="pr-stat-pill" style={{ borderColor: `${c.color}55` }}>
            <div>
              <div className="pr-stat-pill-val" style={{ color: c.color }}>{countFor(c.value)}</div>
              <div className="pr-stat-pill-key">{c.emoji} {c.label}</div>
            </div>
          </div>
        ))}
        <div className="pr-stat-pill">
          <div>
            <div className="pr-stat-pill-val">{profiles.reduce((a,p) => a + (p.photo_count || 0), 0)}</div>
            <div className="pr-stat-pill-key">Total Photos</div>
          </div>
        </div>
      </div>

      {/* ── Create form ── */}
      {showForm && (
        <div className="pr-form-wrap">
          <form onSubmit={handleCreate} className="pr-form-inner">
            <div className="pr-form-field">
              <label>Full name</label>
              <input
                value={name}
                onChange={e => setName(e.target.value)}
                placeholder="e.g. Alice Johnson"
                required autoFocus
              />
            </div>
            <div className="pr-form-field">
              <label>Priority category</label>
              <div className="pr-type-toggle" style={{ flexWrap: 'wrap', gap: 8 }}>
                {CATEGORIES.map(c => {
                  const active = svcType === c.value
                  return (
                    <button
                      key={c.value}
                      type="button"
                      onClick={() => setSvcType(c.value)}
                      style={{
                        display: 'flex', alignItems: 'center', gap: 6,
                        padding: '8px 14px', borderRadius: 10, fontSize: 13, fontWeight: 700,
                        cursor: 'pointer', transition: 'all .12s ease', flex: '1 1 calc(50% - 8px)',
                        justifyContent: 'center',
                        background: active ? c.color : '#fff',
                        color: active ? '#fff' : c.color,
                        border: `1.5px solid ${active ? c.color : c.color + '55'}`,
                        boxShadow: active ? `0 4px 12px ${c.color}55` : 'none',
                      }}
                    >
                      <span>{c.emoji}</span> {c.label}
                    </button>
                  )
                })}
              </div>
            </div>
            <button className="pr-submit-btn" type="submit" disabled={saving}>
              {saving
                ? <><div className="dk-spinner" style={{width:14,height:14}}/>Creating…</>
                : <>
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z" fill="currentColor"/></svg>
                    Create Profile
                  </>
              }
            </button>
          </form>
        </div>
      )}

      {/* ── Content ── */}
      <div className="pr-content">
        {loading ? (
          <div className="dk-loading"><div className="dk-spinner"/>Loading profiles…</div>
        ) : profiles.length === 0 ? (
          <div className="pr-empty">
            <div className="pr-empty-icon">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" opacity="0.2">
                <circle cx="9" cy="7" r="4" fill="currentColor"/>
                <path d="M2 21v-1a7 7 0 0 1 14 0v1" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
                <circle cx="19" cy="8" r="3" fill="currentColor"/>
                <path d="M22 21v-1a5 5 0 0 0-5-5" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              </svg>
            </div>
            <div className="pr-empty-text">No profiles yet</div>
            <div className="pr-empty-sub">Create your first profile to start tracking photos</div>
            <button className="pr-new-btn" onClick={() => setShowForm(true)} style={{marginTop:20}}>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z" fill="currentColor"/></svg>
              New Profile
            </button>
          </div>
        ) : viewMode === 'table' ? (
          <ProfilesTable
            profiles={sortProfiles(filtered).sort((a, b) =>
              CATEGORIES.findIndex(c => c.value === normalizeCat(a.service_type)) -
              CATEGORIES.findIndex(c => c.value === normalizeCat(b.service_type)))}
            onOpen={(id) => navigate(`/profiles/${id}`)}
            onDelete={handleDelete}
          />
        ) : (
          <div className="pr-list-wrap">
            {CATEGORIES.map(c => {
              const list = groupFor(c.value)
              if (list.length === 0) return null
              const isExpanded = !!expandedCats[c.value]
              const overflowing = list.length > SECTION_LIMIT
              const visible = isExpanded ? list : list.slice(0, SECTION_LIMIT)
              return (
                <div className="pr-section" key={c.value}>
                  <div className="pr-section-header">
                    <span className="pr-section-dot" style={{ background: c.color, boxShadow: `0 0 8px ${c.color}99` }}/>
                    <span className="pr-section-label">{c.emoji} {c.label}</span>
                    <span className="pr-section-count">{list.length}</span>
                    <div className="pr-section-line"/>
                    {overflowing && (
                      <button
                        onClick={() => toggleExpand(c.value)}
                        style={{
                          background: 'transparent', border: 'none', cursor: 'pointer',
                          color: c.color, fontWeight: 700, fontSize: 12.5, whiteSpace: 'nowrap',
                          padding: '4px 6px',
                        }}
                      >
                        {isExpanded ? 'Show less' : `Show all ${list.length} →`}
                      </button>
                    )}
                  </div>
                  {/* Uniform responsive card grid (User-Management style) */}
                  <div style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))',
                    gap: 14, paddingBottom: 4,
                  }}>
                    {visible.map(p => (
                      <ProfileCard key={p.id} p={p} onClick={() => navigate(`/profiles/${p.id}`)} onDelete={handleDelete} />
                    ))}
                  </div>
                </div>
              )
            })}

            {filtered.length === 0 && search && (
              <div className="pr-empty" style={{padding:'40px 0'}}>
                <div className="pr-empty-text">No results for "{search}"</div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

function ProfileCard({ p, onClick, onDelete }) {
  const [confirming, setConfirming] = useState(false)
  const cat       = catOf(p.service_type)
  const color     = cat.color
  const initials  = p.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()

  const handle = '@' + p.name.trim().split(/\s+/)[0].toLowerCase()

  return (
    <div
      style={{
        background: '#fff',
        border: `1px solid #ececf3`,
        borderRadius: 14,
        padding: 14,
        cursor: 'pointer',
        boxShadow: '0 2px 10px rgba(15,23,42,0.05)',
        transition: 'all 0.15s',
        display: 'flex',
        alignItems: 'flex-start',
        gap: 12,
        position: 'relative',
      }}
      onMouseEnter={e => { e.currentTarget.style.boxShadow = '0 10px 28px rgba(15,23,42,0.10)'; e.currentTarget.style.transform = 'translateY(-2px)' }}
      onMouseLeave={e => { e.currentTarget.style.boxShadow = '0 2px 10px rgba(15,23,42,0.05)'; e.currentTarget.style.transform = 'none' }}
      onClick={() => onClick()}
    >
      {/* Avatar */}
      <div style={{
        width: 46, height: 46, borderRadius: '50%', flexShrink: 0,
        background: color, color: '#fff',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 16, fontWeight: 800,
        border: `2px solid ${color}33`,
      }}>
        {initials}
      </div>

      {/* Identity */}
      <div style={{ flex: 1, minWidth: 0, paddingRight: 18 }}>
        <div style={{ fontWeight: 700, fontSize: 14, color: '#0f172a', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
        <div style={{ fontSize: 12, color: '#94a3b8', marginTop: 1 }}>{handle}</div>
        <div style={{ marginTop: 8, display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 11, fontWeight: 800, color, display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <span style={{ width: 7, height: 7, borderRadius: '50%', background: color, display: 'inline-block' }} />
            {cat.label}
          </span>
          {p.photo_count > 0 && (
            <span style={{ fontSize: 11, color: '#94a3b8' }}>· {p.photo_count} photo{p.photo_count !== 1 ? 's' : ''}</span>
          )}
        </div>
      </div>

      {/* ⋮ menu */}
      <button
        onClick={e => { e.stopPropagation(); setConfirming(v => !v) }}
        title="Options"
        style={{
          position: 'absolute', top: 10, right: 8,
          background: 'transparent', border: 'none', cursor: 'pointer',
          color: '#94a3b8', fontSize: 18, lineHeight: 1, padding: '2px 6px', borderRadius: 6,
        }}
      >⋮</button>

      {confirming && (
        <div
          onClick={e => e.stopPropagation()}
          style={{
            position: 'absolute', top: 34, right: 8, zIndex: 5,
            background: '#fff', border: '1px solid #ececf3', borderRadius: 12,
            boxShadow: '0 12px 30px rgba(15,23,42,0.16)', padding: 6, minWidth: 150,
          }}
        >
          <button
            onClick={() => { onClick(); }}
            style={{ width: '100%', textAlign: 'left', padding: '8px 10px', border: 'none', background: 'transparent', borderRadius: 8, cursor: 'pointer', fontSize: 13, fontWeight: 600, color: '#0f172a' }}
          >View profile</button>
          <button
            onClick={() => { setConfirming(false); onDelete(p.id) }}
            style={{ width: '100%', textAlign: 'left', padding: '8px 10px', border: 'none', background: 'transparent', borderRadius: 8, cursor: 'pointer', fontSize: 13, fontWeight: 600, color: '#ef4444' }}
          >Delete</button>
        </div>
      )}
    </div>
  )
}

/* ── HR-style table view (Employees-table look) ── */
function ProfilesTable({ profiles, onOpen, onDelete }) {
  const th = { textAlign: 'left', padding: '13px 18px', fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: '#94a3b8', background: '#fafbfc', borderBottom: '1px solid #eef2f7', whiteSpace: 'nowrap' }
  const td = { padding: '12px 18px', fontSize: 13.5, color: '#0f172a', borderBottom: '1px solid #f5f7fa', verticalAlign: 'middle' }
  if (profiles.length === 0) {
    return <div className="pr-empty" style={{ padding: '40px 0' }}><div className="pr-empty-text">No profiles</div></div>
  }
  return (
    <div style={{ background: '#fff', border: '1px solid #ececf3', borderRadius: 16, overflow: 'hidden', boxShadow: '0 4px 18px rgba(15,23,42,0.05)' }}>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={th}>Profile</th>
              <th style={th}>Username</th>
              <th style={th}>Category</th>
              <th style={th}>Photos</th>
              <th style={{ ...th, textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {profiles.map(p => {
              const cat = catOf(p.service_type)
              const initials = p.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()
              const handle = '@' + p.name.trim().split(/\s+/)[0].toLowerCase()
              return (
                <tr key={p.id}
                  onClick={() => onOpen(p.id)}
                  style={{ cursor: 'pointer' }}
                  onMouseEnter={e => e.currentTarget.style.background = '#faf5ff'}
                  onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                  <td style={td}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
                      <div style={{ width: 38, height: 38, borderRadius: '50%', background: cat.color, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 14, flexShrink: 0 }}>{initials}</div>
                      <span style={{ fontWeight: 700 }}>{p.name}</span>
                    </div>
                  </td>
                  <td style={{ ...td, color: '#94a3b8' }}>{handle}</td>
                  <td style={td}>
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 700, color: cat.color, background: `${cat.color}14`, border: `1px solid ${cat.color}33`, padding: '3px 10px', borderRadius: 999 }}>
                      <span style={{ width: 6, height: 6, borderRadius: '50%', background: cat.color }} /> {cat.label}
                    </span>
                  </td>
                  <td style={{ ...td, color: '#64748b', fontWeight: 600 }}>{p.photo_count || 0}</td>
                  <td style={{ ...td, textAlign: 'right' }} onClick={e => e.stopPropagation()}>
                    <button
                      onClick={() => onDelete(p.id)}
                      title="Delete profile"
                      style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: '#ef4444', fontSize: 12.5, fontWeight: 700, padding: '6px 10px', borderRadius: 8 }}
                    >Delete</button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
