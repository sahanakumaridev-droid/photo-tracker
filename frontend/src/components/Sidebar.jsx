import React, { useState, useEffect } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { getProfiles } from '../api'
import SettingsPanel from './SettingsPanel'
import { useTheme } from '../context/ThemeContext'

const NAV = [
  {
    to: '/', label: 'Dashboard',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z" fill="currentColor"/></svg>,
  },
  {
    to: '/analytics', label: 'Analytics',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="11" width="4" height="9" rx="1" fill="currentColor"/><rect x="10" y="6" width="4" height="14" rx="1" fill="currentColor"/><rect x="17" y="3" width="4" height="17" rx="1" fill="currentColor" opacity="0.7"/></svg>,
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
  {
    to: '/schedule', label: 'Schedule',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="4" width="18" height="18" rx="2" stroke="currentColor" strokeWidth="2"/><line x1="3" y1="9" x2="21" y2="9" stroke="currentColor" strokeWidth="2"/><line x1="8" y1="2" x2="8" y2="6" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><line x1="16" y1="2" x2="16" y2="6" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg>,
  },
  {
    to: '/earnings', label: 'Earnings',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="2"/><path d="M12 7v10M9.5 9.5a2.5 2 0 0 1 5 0c0 1.5-5 1-5 2.5a2.5 2 0 0 0 5 0" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/></svg>,
  },
  {
    to: '/archive', label: 'Archive',
    icon: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="4" width="18" height="4" rx="1" stroke="currentColor" strokeWidth="2"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8" stroke="currentColor" strokeWidth="2"/><line x1="10" y1="12" x2="14" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg>,
  },
]

export default function Sidebar({ user, onLogout }) {
  const [rush, setRush]           = useState(null)
  const location                  = useLocation()
  const { accentPreset, settingsOpen, setSettings } = useTheme()

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
    <>
      <aside className="sidebar sidebar-open">
        {/* Logo */}
        <div className="sb-brand">
          <div className="sb-brand-mark">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
              <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/>
            </svg>
          </div>
          <span className="sb-brand-name">GeoTagging</span>
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

        {/* User footer — settings trigger */}
        <div className="sb-footer" style={{ position: 'relative' }}>

          {/* Settings popover — sits above the footer */}
          <SettingsPanel
            open={settingsOpen}
            onClose={() => setSettings(false)}
            user={user}
            onLogout={onLogout}
          />

          <button
            className="sb-settings-trigger"
            onClick={() => setSettings(v => !v)}
            title="Settings"
          >
            <div
              className="sb-user-avatar"
              style={{ background: `linear-gradient(135deg, ${accentPreset.primary}, ${accentPreset.secondary})` }}
            >
              {user?.name?.charAt(0)?.toUpperCase() || 'U'}
            </div>
            <div className="sb-user-info">
              <div className="sb-user-name">{user?.name || 'User'}</div>
              <div className="sb-user-email">{user?.email || ''}</div>
            </div>
            <div className="sb-settings-icon">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="2"/>
                <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" stroke="currentColor" strokeWidth="2"/>
              </svg>
            </div>
          </button>
        </div>
      </aside>
    </>
  )
}
