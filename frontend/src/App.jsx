import React, { useState } from 'react'
import { Routes, Route } from 'react-router-dom'
import Sidebar from './components/Sidebar'
import Dashboard from './pages/Dashboard'
import Profiles from './pages/Profiles'
import Upload from './pages/Upload'
import ProfileDetail from './pages/ProfileDetail'
import Login from './pages/Login'
import Log from './pages/Log'
import { ThemeProvider } from './context/ThemeContext'

export default function App() {
  const [user,  setUser]  = useState(null)
  const [toast, setToast] = useState(null)

  const showToast = (msg, type = 'success') => {
    setToast({ msg, type })
    setTimeout(() => setToast(null), 3500)
  }

  if (!user) return (
    <ThemeProvider>
      <Login onLogin={setUser} />
    </ThemeProvider>
  )

  return (
    <ThemeProvider>
      <div className="app-shell">
        <Sidebar user={user} onLogout={() => setUser(null)} />
        <main className="app-main">
          <Routes>
            <Route path="/"             element={<Dashboard />} />
            <Route path="/profiles"     element={<Profiles showToast={showToast} />} />
            <Route path="/profiles/:id" element={<ProfileDetail />} />
            <Route path="/upload"       element={<Upload showToast={showToast} />} />
            <Route path="/log"          element={<Log />} />
          </Routes>
        </main>

        {toast && (
          <div className={`toast ${toast.type}`}>
            {toast.type === 'success' ? '✓' : '✕'} {toast.msg}
          </div>
        )}
      </div>
    </ThemeProvider>
  )
}
