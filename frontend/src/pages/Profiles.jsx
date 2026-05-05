import React, { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getProfilesLive, createProfile, deleteProfile } from '../api'

export default function Profiles({ showToast }) {
  const [profiles, setProfiles] = useState([])
  const [loading,  setLoading]  = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [name,     setName]     = useState('')
  const [svcType,  setSvcType]  = useState('standard')
  const [saving,   setSaving]   = useState(false)
  const [search,   setSearch]   = useState('')
  const navigate = useNavigate()

  const load = async () => {
    await getProfilesLive(data => {
      setProfiles(data)
      setLoading(false)
    })
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

  const rush     = profiles.filter(p => p.service_type === 'rush')
  const standard = profiles.filter(p => p.service_type === 'standard')

  const filtered = profiles.filter(p =>
    !search || p.name.toLowerCase().includes(search.toLowerCase())
  )
  const filteredRush     = filtered.filter(p => p.service_type === 'rush')
  const filteredStandard = filtered.filter(p => p.service_type === 'standard')

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
              {profiles.length} total ·{' '}
              <span className="pr-sub-rush">{rush.length} rush</span> ·{' '}
              <span className="pr-sub-std">{standard.length} standard</span>
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
        <div className="pr-stat-pill pr-stat-pill-rush">
          <div>
            <div className="pr-stat-pill-val">{rush.length}</div>
            <div className="pr-stat-pill-key">Rush Priority</div>
          </div>
        </div>
        <div className="pr-stat-pill pr-stat-pill-std">
          <div>
            <div className="pr-stat-pill-val">{standard.length}</div>
            <div className="pr-stat-pill-key">Standard</div>
          </div>
        </div>
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
              <label>Service type</label>
              <div className="pr-type-toggle">
                <button
                  type="button"
                  className={`pr-type-btn ${svcType === 'standard' ? 'pr-type-std' : ''}`}
                  onClick={() => setSvcType('standard')}
                >
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" fill="currentColor"/></svg>
                  Standard
                </button>
                <button
                  type="button"
                  className={`pr-type-btn ${svcType === 'rush' ? 'pr-type-rush' : ''}`}
                  onClick={() => setSvcType('rush')}
                >
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M7 2v11h3v9l7-12h-4l4-8z" fill="currentColor"/></svg>
                  Rush
                </button>
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
        ) : (
          <div className="pr-list-wrap">
            {/* Rush section */}
            {filteredRush.length > 0 && (
              <div className="pr-section">
                <div className="pr-section-header">
                  <span className="pr-section-dot" style={{background:'#f43f5e', boxShadow:'0 0 8px rgba(244,63,94,0.6)'}}/>
                  <span className="pr-section-label">Rush Priority</span>
                  <span className="pr-section-count">{filteredRush.length}</span>
                  <div className="pr-section-line"/>
                </div>
                <div className="pr-list">
                  {filteredRush.map(p => (
                    <ProfileRow key={p.id} p={p}
                      onClick={() => navigate(`/profiles/${p.id}`)}
                      onDelete={handleDelete}/>
                  ))}
                </div>
              </div>
            )}

            {/* Standard section */}
            {filteredStandard.length > 0 && (
              <div className="pr-section">
                <div className="pr-section-header">
                  <span className="pr-section-dot" style={{background:'#10b981', boxShadow:'0 0 8px rgba(16,185,129,0.6)'}}/>
                  <span className="pr-section-label">Standard</span>
                  <span className="pr-section-count">{filteredStandard.length}</span>
                  <div className="pr-section-line"/>
                </div>
                <div className="pr-list">
                  {filteredStandard.map(p => (
                    <ProfileRow key={p.id} p={p}
                      onClick={() => navigate(`/profiles/${p.id}`)}
                      onDelete={handleDelete}/>
                  ))}
                </div>
              </div>
            )}

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

function ProfileRow({ p, onClick, onDelete }) {
  const [confirming, setConfirming] = useState(false)
  const isRush   = p.service_type === 'rush'
  const color    = isRush ? '#f43f5e' : '#10b981'
  const initials = p.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()

  return (
    <div
      className="pr-row"
      onClick={!confirming ? onClick : undefined}
      style={{cursor: confirming ? 'default' : 'pointer'}}
    >
      {/* Left accent */}
      <div className="pr-row-accent" style={{background: color}}/>

      {/* Avatar */}
      <div className="pr-row-avatar" style={{
        background: `linear-gradient(135deg, ${color}dd, ${color}77)`,
        boxShadow: `0 4px 12px ${color}44`,
      }}>
        {initials}
      </div>

      {/* Name + meta */}
      <div className="pr-row-info">
        <div className="pr-row-name">{p.name}</div>
        <div className="pr-row-meta">
          <span>ID #{p.id}</span>
          {p.photo_count > 0 && (
            <>
              <span className="pr-row-dot"/>
              <span>{p.photo_count} photo{p.photo_count !== 1 ? 's' : ''}</span>
            </>
          )}
        </div>
      </div>

      {/* Badge */}
      <div className="pr-row-badge" style={{
        background: `${color}18`,
        border: `1px solid ${color}44`,
        color: isRush ? '#fda4af' : '#6ee7b7',
      }}>
        {isRush
          ? <svg width="10" height="10" viewBox="0 0 24 24" fill="none"><path d="M7 2v11h3v9l7-12h-4l4-8z" fill="currentColor"/></svg>
          : <svg width="10" height="10" viewBox="0 0 24 24" fill="none"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" fill="currentColor"/></svg>
        }
        {isRush ? 'ASAP' : 'Standard'}
      </div>

      {/* Arrow */}
      {!confirming && (
        <div className="pr-row-arrow">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
            <path d="M9 18l6-6-6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </div>
      )}

      {/* Delete */}
      {confirming ? (
        <div className="pr-row-confirm" onClick={e => e.stopPropagation()}>
          <span>Delete?</span>
          <button className="dk-confirm-yes" onClick={() => { onDelete(p.id); setConfirming(false) }}>Yes</button>
          <button className="dk-confirm-no"  onClick={() => setConfirming(false)}>No</button>
        </div>
      ) : (
        <button
          className="pr-row-del"
          onClick={e => { e.stopPropagation(); setConfirming(true) }}
          title="Delete"
        >
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
            <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z" fill="currentColor"/>
          </svg>
        </button>
      )}
    </div>
  )
}
