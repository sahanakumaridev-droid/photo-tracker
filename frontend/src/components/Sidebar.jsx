import React, { useState, useEffect } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { getPhotos, getProfiles } from '../api'

const NAV = [
  { to: '/',         icon: '▦',  label: 'Dashboard' },
  { to: '/profiles', icon: '◉',  label: 'Profiles'  },
  { to: '/upload',   icon: '↑',  label: 'Upload'    },
]

export default function Sidebar({ user, onLogout }) {
  const [open,     setOpen]     = useState(true)
  const [stats,    setStats]    = useState(null)
  const location = useLocation()

  useEffect(() => {
    const load = async () => {
      try {
        const [photos, profiles] = await Promise.all([getPhotos(), getProfiles()])
        setStats({
          photos:   photos.length,
          profiles: profiles.length,
          rush:     profiles.filter(p => p.service_type === 'rush').length,
          standard: profiles.filter(p => p.service_type === 'standard').length,
        })
      } catch {}
    }
    load()
    // refresh every 30s
    const interval = setInterval(load, 30000)
    return () => clearInterval(interval)
  }, [location]) // re-fetch on every page change so numbers stay fresh

  return (
    <aside className={`sidebar ${open ? 'sidebar-open' : 'sidebar-closed'}`}>

      {/* Brand */}
      <div className="sb-brand">
        {open && (
          <div className="sb-brand-inner">
            <div className="sb-brand-mark">📍</div>
            <span className="sb-brand-name">PhotoTracker</span>
          </div>
        )}
        <button className="sb-toggle" onClick={() => setOpen(v => !v)} title={open ? 'Collapse' : 'Expand'}>
          {open ? '‹' : '›'}
        </button>
      </div>

      {/* Tagline — only when open */}
      {open && (
        <div className="sb-tagline">
          Track every photo,<br />every location.
        </div>
      )}

      {/* Nav */}
      <nav className="sb-nav">
        {open && <div className="sb-nav-label">Navigation</div>}
        {NAV.map(({ to, icon, label }) => {
          const active = to === '/' ? location.pathname === '/' : location.pathname.startsWith(to)
          return (
            <NavLink
              key={to}
              to={to}
              className={`sb-link ${active ? 'sb-active' : ''}`}
              title={!open ? label : undefined}
            >
              <span className="sb-icon">{icon}</span>
              {open && <span className="sb-label">{label}</span>}
              {open && active && <span className="sb-pip" />}
            </NavLink>
          )
        })}
      </nav>

      {/* Live stats — only when open */}
      {open && (
        <div className="sb-features">
          <div className="sb-stat-row">
            <span className="sb-stat-icon">📷</span>
            <div className="sb-stat-info">
              <div className="sb-stat-label">Total Photos</div>
              <div className="sb-stat-val">{stats ? stats.photos : '—'}</div>
            </div>
          </div>
          <div className="sb-stat-row">
            <span className="sb-stat-icon">👤</span>
            <div className="sb-stat-info">
              <div className="sb-stat-label">Profiles</div>
              <div className="sb-stat-val">{stats ? stats.profiles : '—'}</div>
            </div>
          </div>
          <div className="sb-stat-row">
            <span className="sb-stat-icon" style={{background:'rgba(239,68,68,0.15)'}}>⚡</span>
            <div className="sb-stat-info">
              <div className="sb-stat-label">Rush</div>
              <div className="sb-stat-val" style={{color:'#ef4444'}}>{stats ? stats.rush : '—'}</div>
            </div>
          </div>
          <div className="sb-stat-row">
            <span className="sb-stat-icon" style={{background:'rgba(16,185,129,0.15)'}}>◈</span>
            <div className="sb-stat-info">
              <div className="sb-stat-label">Standard</div>
              <div className="sb-stat-val" style={{color:'#10b981'}}>{stats ? stats.standard : '—'}</div>
            </div>
          </div>
        </div>
      )}

      <div style={{ flex: 1 }} />

      {/* User + logout */}
      <div className="sb-footer">
        {open ? (
          <>
            <div className="sb-user">
              <div className="sb-user-avatar">{user?.name?.charAt(0) || 'U'}</div>
              <div className="sb-user-info">
                <div className="sb-user-name">{user?.name || 'User'}</div>
                <div className="sb-user-email">{user?.email || ''}</div>
              </div>
            </div>
            <button className="sb-logout" onClick={onLogout} title="Sign out">⎋</button>
          </>
        ) : (
          <button className="sb-logout" onClick={onLogout} title="Sign out" style={{margin:'0 auto'}}>⎋</button>
        )}
      </div>

    </aside>
  )
}
