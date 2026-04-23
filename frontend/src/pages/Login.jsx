import React, { useState } from 'react'

// Demo credentials
const USERS = [
  { email: 'admin@phototracker.com', password: 'admin123', name: 'Admin User' },
  { email: 'demo@phototracker.com',  password: 'demo123',  name: 'Demo User'  },
]

export default function Login({ onLogin }) {
  const [email,    setEmail]    = useState('')
  const [password, setPassword] = useState('')
  const [error,    setError]    = useState('')
  const [loading,  setLoading]  = useState(false)
  const [showPass, setShowPass] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    await new Promise(r => setTimeout(r, 700)) // simulate auth
    const user = USERS.find(u => u.email === email && u.password === password)
    if (user) {
      onLogin(user)
    } else {
      setError('Invalid email or password.')
    }
    setLoading(false)
  }

  const fillDemo = () => {
    setEmail('demo@phototracker.com')
    setPassword('demo123')
    setError('')
  }

  const quickLogin = (email, password) => {
    setEmail(email)
    setPassword(password)
    setError('')
    const user = USERS.find(u => u.email === email && u.password === password)
    if (user) onLogin(user)
  }

  return (
    <div className="login-shell">
      {/* LEFT — branding */}
      <div className="login-left">
        <div className="login-left-inner">
          <div className="login-brand">
            <div className="login-brand-mark">📍</div>
            <span className="login-brand-name">PhotoTracker</span>
          </div>

          <div className="login-hero-text">
            <h1>Track every photo,<br />every location.</h1>
            <p>A powerful location-based photo management system. Upload, tag, and visualise photos on an interactive map in real time.</p>
          </div>

          <div className="login-features">
            <div className="login-feat">
              <span className="login-feat-icon">🗺</span>
              <div>
                <div className="login-feat-title">Interactive Map</div>
                <div className="login-feat-sub">See all photos pinned live on the map</div>
              </div>
            </div>
            <div className="login-feat">
              <span className="login-feat-icon">📷</span>
              <div>
                <div className="login-feat-title">Auto Geotagging</div>
                <div className="login-feat-sub">GPS + timestamp captured automatically</div>
              </div>
            </div>
            <div className="login-feat">
              <span className="login-feat-icon">⚡</span>
              <div>
                <div className="login-feat-title">Rush & Standard</div>
                <div className="login-feat-sub">Visual priority flagging per profile</div>
              </div>
            </div>
          </div>

          <div className="login-left-footer">© 2026 PhotoTracker CRM</div>
        </div>
      </div>

      {/* RIGHT — form */}
      <div className="login-right">
        <div className="login-form-wrap">
          <div className="login-form-header">
            <h2>Welcome back</h2>
            <p>Sign in to your account to continue</p>
          </div>

          <form onSubmit={handleSubmit} className="login-form">
            <div className="login-field">
              <label>Email address</label>
              <input
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={e => { setEmail(e.target.value); setError('') }}
                required
                autoFocus
              />
            </div>

            <div className="login-field">
              <div style={{display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom:5}}>
                <label style={{margin:0}}>Password</label>
              </div>
              <div className="pass-wrap">
                <input
                  type={showPass ? 'text' : 'password'}
                  placeholder="Enter your password"
                  value={password}
                  onChange={e => { setPassword(e.target.value); setError('') }}
                  required
                  style={{marginBottom:0, paddingRight:44}}
                />
                <button
                  type="button"
                  className="pass-toggle"
                  onClick={() => setShowPass(v => !v)}
                  tabIndex={-1}
                >
                  {showPass ? '🙈' : '👁'}
                </button>
              </div>
            </div>

            {error && (
              <div className="login-error">
                ✕ {error}
              </div>
            )}

            <button
              type="submit"
              className="login-btn"
              disabled={loading}
            >
              {loading
                ? <><div className="spinner" style={{width:15,height:15,borderTopColor:'#fff'}}/>Signing in…</>
                : 'Sign in →'
              }
            </button>
          </form>

          <div className="login-divider"><span>quick access</span></div>

          <div className="login-creds">
            <div className="login-creds-title">Quick login — click to enter</div>
            <div className="login-cred-row cred-clickable" onClick={() => quickLogin('admin@phototracker.com', 'admin123')}>
              <span>admin@phototracker.com</span><span className="cred-sep">/</span><span>admin123</span>
              <span className="cred-arrow">→</span>
            </div>
            <div className="login-cred-row cred-clickable" onClick={() => quickLogin('demo@phototracker.com', 'demo123')}>
              <span>demo@phototracker.com</span><span className="cred-sep">/</span><span>demo123</span>
              <span className="cred-arrow">→</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
