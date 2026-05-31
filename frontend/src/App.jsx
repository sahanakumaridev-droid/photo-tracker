import React, { useState, useEffect } from 'react'
import { Routes, Route, NavLink, useLocation } from 'react-router-dom'
import Sidebar from './components/Sidebar'
import Dashboard from './pages/Dashboard'
import Analytics from './pages/Analytics'
import Profiles from './pages/Profiles'
import Upload from './pages/Upload'
import ProfileDetail from './pages/ProfileDetail'
import Login from './pages/Login'
import Log from './pages/Log'
import { ThemeProvider } from './context/ThemeContext'
import { GeoContext } from './context/GeoContext'

function MobileNav() {
  const location = useLocation()
  const links = [
    { to: '/', label: 'Map', icon: <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z" fill="currentColor"/></svg> },
    { to: '/profiles', label: 'Profiles', icon: <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><circle cx="9" cy="7" r="4" fill="currentColor"/><path d="M2 21v-1a7 7 0 0 1 14 0v1" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><circle cx="19" cy="8" r="3" fill="currentColor" opacity="0.6"/></svg> },
    { to: '/upload', label: 'Upload', icon: <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><polyline points="17 8 12 3 7 8" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><line x1="12" y1="3" x2="12" y2="15" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg> },
    { to: '/log', label: 'Log', icon: <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6z" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><line x1="16" y1="13" x2="8" y2="13" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/><line x1="16" y1="17" x2="8" y2="17" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg> },
  ]
  return (
    <nav className="mobile-nav">
      <div className="mobile-nav-inner">
        {links.map(({ to, label, icon }) => {
          const active = to === '/' ? location.pathname === '/' : location.pathname.startsWith(to)
          return (
            <NavLink key={to} to={to} className={`mobile-nav-btn ${active ? 'active' : ''}`}>
              {icon}
              {label}
            </NavLink>
          )
        })}
      </div>
    </nav>
  )
}

// ── Geo context shared across the app ──────────────────────────────────────
// (exported from context/GeoContext.js — re-exported here for backward compat)
export { GeoContext }

export default function App() {
  // ── Persist login across refresh using localStorage ──
  const [user, setUser] = useState(() => {
    try { return JSON.parse(localStorage.getItem('geo_user')) } catch { return null }
  })
  const [toast, setToast] = useState(null)

  // ── Global geolocation — watch position so it stays fresh ──
  const [geoLocation,  setGeoLocation]  = useState(null)
  const [geoTimestamp, setGeoTimestamp] = useState(null)
  const [geoError,     setGeoError]     = useState(null)

  useEffect(() => {
    if (!user) return
    if (!navigator.geolocation) {
      setGeoError('Geolocation is not available. Use a modern browser with HTTPS.')
      return
    }

    // Grab immediately with retry
    let attempts = 0
    const maxAttempts = 3

    const tryGetPosition = () => {
      navigator.geolocation.getCurrentPosition(
        pos => {
          setGeoLocation({ lat: pos.coords.latitude, lng: pos.coords.longitude })
          setGeoTimestamp(new Date().toISOString())
          setGeoError(null)
        },
        err => {
          attempts++
          if (err.code === 1) {
            setGeoError('Location permission denied. Please enable GPS in your browser settings and reload.')
          } else if (attempts < maxAttempts) {
            setTimeout(tryGetPosition, 2000)
          } else {
            setGeoError('Unable to get GPS signal. Try moving to an open area or set location manually.')
          }
        },
        { timeout: 12000, enableHighAccuracy: true, maximumAge: 0 }
      )
    }

    tryGetPosition()

    // Then watch for updates (keeps location fresh as user moves)
    const watchId = navigator.geolocation.watchPosition(
      pos => {
        setGeoLocation({ lat: pos.coords.latitude, lng: pos.coords.longitude })
        setGeoTimestamp(new Date().toISOString())
        setGeoError(null)
      },
      err => {
        if (err.code === 1) {
          setGeoError('Location permission denied. Please enable GPS in browser settings.')
        }
      },
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 15000 }
    )

    return () => navigator.geolocation.clearWatch(watchId)
  }, [user])

  const handleLogin = (u) => {
    localStorage.setItem('geo_user', JSON.stringify(u))
    setUser(u)
  }

  const handleLogout = () => {
    localStorage.removeItem('geo_user')
    setUser(null)
  }

  const showToast = (msg, type = 'success') => {
    setToast({ msg, type })
    setTimeout(() => setToast(null), 3500)
  }

  if (!user) return (
    <ThemeProvider>
      <Login onLogin={handleLogin} />
    </ThemeProvider>
  )

  return (
    <ThemeProvider>
      <GeoContext.Provider value={{ location: geoLocation, timestamp: geoTimestamp }}>
        {geoError && (
          <div className="geo-banner">
            ⚠️ {geoError}
          </div>
        )}
        <div className="app-shell">
          <Sidebar user={user} onLogout={handleLogout} />
          <main className="app-main">
            <Routes>
              <Route path="/"             element={<Dashboard />} />
              <Route path="/analytics"    element={<Analytics />} />
              <Route path="/profiles"     element={<Profiles showToast={showToast} />} />
              <Route path="/profiles/:id" element={<ProfileDetail />} />
              <Route path="/upload"       element={<Upload showToast={showToast} />} />
              <Route path="/log"          element={<Log />} />
            </Routes>
          </main>
          <MobileNav />

          {toast && (
            <div className={`toast ${toast.type}`}>
              {toast.type === 'success' ? '✓' : '✕'} {toast.msg}
            </div>
          )}
        </div>
      </GeoContext.Provider>
    </ThemeProvider>
  )
}
