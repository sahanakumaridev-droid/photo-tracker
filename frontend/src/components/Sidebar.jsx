import React, { useState, useEffect } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { getPhotos, getProfiles } from '../api'

const NAV = [
  {
    to: '/', label: 'Dashboard',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="7" height="7" rx="1.5" fill="currentColor"/><rect x="14" y="3" width="7" height="7" rx="1.5" fill="currentColor"/><rect x="3" y="14" width="7" height="7" rx="1.5" fill="currentColor"/><rect x="14" y="14" width="7" height="7" rx="1.5" fill="currentColor"/></svg>,
  },
  {
    to: '/profiles', label: 'Profiles',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="9" cy="7" r="4" fill="currentColor"/><path d="M2 21v-1a7 7 0 0 1 14 0v1" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><circle cx="19" cy="8" r="3" fill="currentColor" opacity="0.6"/><path d="M22 21v-1a5 5 0 0 0-5-5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" opacity="0.6"/></svg>,
  },
  {
    to: '/upload', label: 'Upload',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/><polyline points="17 8 12 3 7 8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/><line x1="12" y1="3" x2="12" y2="15" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg>,
  },
  {
    to: '/log', label: 'Log',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/><polyline points="14 2 14 8 20 8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/><line x1="16" y1="13" x2="8" y2="13" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><line x1="16" y1="17" x2="8" y2="17" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><polyline points="10 9 9 9 8 9" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg>,
  },
]

export default function Sidebar({ user, onLogout }) {
  const [rush, setRush] = useState(null)
  const location = useLocation()

  useEffect(() => {
    const load = async () => {
      try {
        const profiles = await getProfiles()
        setRush(profiles.filter(p => p.service_type === 'rush').length)
      } catch {}
    }
    load()
  }, [location])

  return (
    <aside className="sidebar sidebar-open">
      {/* Logo */}
      <div className="sb-brand">
        <div className="sb-brand-mark">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
            <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/>
          </svg>
        </div>
        <span style={{fontSize:14, fontWeight:800, color:'rgba(255,255,255,0.9)', letterSpacing:'-0.3px'}}>GeoTagging</span>
      </div>

      {/* Nav */}
      <nav className="sb-nav">
        <div className="sb-nav-label">Navigation</div>
        {NAV.map(({ to, icon, label }) => {
          const active = to === '/' ? location.pathname === '/' : location.pathname.startsWith(to)
          return (
            <NavLink key={to} to={to} className={`sb-link ${active ? 'sb-active' : ''}`} title={label}>
              <span className="sb-icon">{icon}</span>
              <span className="sb-label">{label}</span>
              {active && label === 'Dashboard' && rush > 0 && (
                <span className="sb-badge">{rush}</span>
              )}
              {active && <span className="sb-active-bar"/>}
            </NavLink>
          )
        })}
      </nav>

      <div style={{ flex: 1 }} />

      {/* User footer */}
      <div className="sb-footer">
        <div className="sb-user-avatar">{user?.name?.charAt(0) || 'U'}</div>
        <div className="sb-user-info">
          <div className="sb-user-name">{user?.name || 'User'}</div>
          <div className="sb-user-email">{user?.email || ''}</div>
        </div>
        <button className="sb-logout" onClick={onLogout} title="Sign out">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
            <polyline points="16 17 21 12 16 7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
            <line x1="21" y1="12" x2="9" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
          </svg>
        </button>
      </div>
    </aside>
  )
}
