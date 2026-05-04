import React, { useState, useEffect, useCallback } from 'react'

const USERS = [
  { email: 'admin@geotagging.com', password: 'admin123', name: 'Admin User' },
  { email: 'demo@geotagging.com',  password: 'demo123',  name: 'Demo User'  },
]

const MapSVG = () => (
  <svg className="lm-map-svg" viewBox="0 0 1440 900" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg">
    <rect width="1440" height="900" fill="#e8f0e9"/>
    <rect x="60"   y="80"  width="220" height="160" rx="18" fill="#c8e6c9" opacity="0.9"/>
    <rect x="1160" y="600" width="200" height="180" rx="18" fill="#c8e6c9" opacity="0.9"/>
    <rect x="900"  y="60"  width="160" height="120" rx="14" fill="#c8e6c9" opacity="0.8"/>
    <ellipse cx="200" cy="700" rx="130" ry="90" fill="#c8e6c9" opacity="0.7"/>
    <ellipse cx="1300" cy="200" rx="110" ry="70" fill="#b3d9f7" opacity="0.85"/>
    <ellipse cx="80"   cy="500" rx="70"  ry="50" fill="#b3d9f7" opacity="0.7"/>
    {[
      [320,80,90,70],[430,80,60,70],[500,80,80,70],[590,80,70,70],
      [320,170,90,60],[430,170,60,60],[500,170,80,60],[590,170,70,60],
      [320,250,90,70],[430,250,140,70],[590,250,70,70],
      [680,80,80,70],[780,80,100,70],[900,80,80,70],
      [680,170,80,60],[780,170,100,60],[900,170,80,60],
      [680,250,80,70],[780,250,100,70],[900,250,80,70],
      [320,360,90,70],[430,360,60,70],[500,360,80,70],[590,360,70,70],
      [680,360,80,70],[780,360,100,70],[900,360,80,70],
      [1020,80,90,70],[1130,80,80,70],[1240,80,90,70],
      [1020,170,90,60],[1130,170,80,60],[1240,170,90,60],
      [1020,250,90,70],[1130,250,80,70],[1240,250,90,70],
      [1020,360,90,70],[1130,360,80,70],[1240,360,90,70],
      [60,260,180,80],[60,360,180,80],
      [320,460,90,70],[430,460,140,70],[590,460,70,70],
      [680,460,80,70],[780,460,100,70],[900,460,80,70],
      [1020,460,90,70],[1130,460,80,70],[1240,460,90,70],
      [320,560,90,70],[430,560,60,70],[500,560,80,70],[590,560,70,70],
      [680,560,80,70],[780,560,100,70],[900,560,80,70],
      [1020,560,90,70],[1130,560,80,70],[1240,560,90,70],
      [320,660,90,70],[430,660,140,70],[590,660,70,70],
      [680,660,80,70],[780,660,100,70],[900,660,80,70],
      [1020,660,90,70],[1130,660,80,70],[1240,660,90,70],
      [320,760,90,70],[430,760,60,70],[500,760,80,70],[590,760,70,70],
      [680,760,80,70],[780,760,100,70],[900,760,80,70],
    ].map(([x,y,w,h], i) => (
      <rect key={i} x={x} y={y} width={w} height={h} rx="4" fill="#dce8dc" stroke="#c5d8c5" strokeWidth="0.5"/>
    ))}
    <rect x="0"    y="155" width="1440" height="10" fill="#fff" opacity="0.95"/>
    <rect x="0"    y="340" width="1440" height="10" fill="#fff" opacity="0.95"/>
    <rect x="0"    y="445" width="1440" height="14" fill="#fdd835" opacity="0.7"/>
    <rect x="0"    y="545" width="1440" height="10" fill="#fff" opacity="0.95"/>
    <rect x="0"    y="645" width="1440" height="10" fill="#fff" opacity="0.95"/>
    <rect x="0"    y="745" width="1440" height="10" fill="#fff" opacity="0.95"/>
    <rect x="305"  y="0" width="10" height="900" fill="#fff" opacity="0.95"/>
    <rect x="665"  y="0" width="10" height="900" fill="#fff" opacity="0.95"/>
    <rect x="875"  y="0" width="14" height="900" fill="#fdd835" opacity="0.7"/>
    <rect x="1005" y="0" width="10" height="900" fill="#fff" opacity="0.95"/>
    <rect x="1220" y="0" width="10" height="900" fill="#fff" opacity="0.95"/>
    <rect x="245"  y="0" width="10" height="900" fill="#fff" opacity="0.95"/>
    {[80,170,250,360,460,560,660,760,860].map((y,i) => (
      <rect key={`hr${i}`} x="0" y={y} width="1440" height="5" fill="#fff" opacity="0.6"/>
    ))}
    {[60,420,490,580,760,1020,1130,1240,1340].map((x,i) => (
      <rect key={`vr${i}`} x={x} y="0" width="5" height="900" fill="#fff" opacity="0.6"/>
    ))}
    {[
      [200,160,'#ea4335'],[520,300,'#4285f4'],[750,200,'#34a853'],
      [1100,300,'#ea4335'],[1300,450,'#4285f4'],[400,500,'#fbbc04'],
      [850,480,'#ea4335'],[1050,600,'#34a853'],[650,700,'#4285f4'],
      [300,750,'#fbbc04'],[1200,700,'#ea4335'],[950,750,'#34a853'],
    ].map(([cx,cy,color],i) => (
      <g key={`pin${i}`}>
        <ellipse cx={cx} cy={cy+18} rx="5" ry="3" fill="rgba(0,0,0,0.15)"/>
        <path d={`M${cx} ${cy-20} C${cx-10} ${cy-20} ${cx-10} ${cy-8} ${cx} ${cy} C${cx+10} ${cy-8} ${cx+10} ${cy-20} ${cx} ${cy-20}Z`} fill={color}/>
        <circle cx={cx} cy={cy-13} r="4" fill="white" opacity="0.9"/>
      </g>
    ))}
  </svg>
)

export default function Login({ onLogin }) {
  const [open,     setOpen]    = useState(false)
  const [email,    setEmail]   = useState('')
  const [password, setPassword]= useState('')
  const [error,    setError]   = useState('')
  const [loading,  setLoading] = useState(false)
  const [showPass, setShowPass]= useState(false)

  const closeModal = useCallback(() => {
    setOpen(false)
    setError('')
  }, [])

  // Close on Escape
  useEffect(() => {
    if (!open) return
    const handler = (e) => { if (e.key === 'Escape') closeModal() }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [open, closeModal])

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    await new Promise(r => setTimeout(r, 700))
    const user = USERS.find(u => u.email === email && u.password === password)
    if (user) { onLogin(user) } else { setError('Invalid email or password.') }
    setLoading(false)
  }

  const quickLogin = (em, pw) => {
    const user = USERS.find(u => u.email === em && u.password === pw)
    if (user) onLogin(user)
  }

  return (
    <div className="lm-shell">

      {/* ── Full-screen map ── */}
      <div className="lm-map-bg" aria-hidden="true">
        <MapSVG />
        <div className="lm-map-overlay"/>
      </div>

      {/* ── Top bar ── */}
      <div className="lm-topbar">
        <div className="lm-topbar-brand">
          <div className="lm-topbar-icon">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
              <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/>
            </svg>
          </div>
          <span>GeoTagging</span>
        </div>

        <div className="lm-topbar-pills">
          <div className="lm-topbar-pill lm-pill-green">
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none"><path d="M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z" fill="currentColor"/></svg>
            Interactive Map
          </div>
          <div className="lm-topbar-pill lm-pill-blue">
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/></svg>
            Auto Geotagging
          </div>
          <div className="lm-topbar-pill lm-pill-yellow">
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none"><path d="M7 2v11h3v9l7-12h-4l4-8z" fill="currentColor"/></svg>
            Rush Priority
          </div>
        </div>

        {/* Sign in button */}
        <button className="lm-topbar-signin" onClick={() => setOpen(true)}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
            <path d="M12 12c2.7 0 4.8-2.1 4.8-4.8S14.7 2.4 12 2.4 7.2 4.5 7.2 7.2 9.3 12 12 12zm0 2.4c-3.2 0-9.6 1.6-9.6 4.8v2.4h19.2v-2.4c0-3.2-6.4-4.8-9.6-4.8z" fill="currentColor"/>
          </svg>
          Sign in
        </button>
      </div>

      {/* ── Hero text on map ── */}
      <div className="lm-hero">
        <div className="lm-hero-tag">Location Intelligence</div>
        <h1 className="lm-hero-h1">Track every photo,<br/>every location.</h1>
        <p className="lm-hero-p">Upload, geotag and visualise photos on a live interactive map.</p>
        <button className="lm-hero-btn" onClick={() => setOpen(true)}>
          Get started
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M12 4l-1.41 1.41L16.17 11H4v2h12.17l-5.58 5.59L12 20l8-8z" fill="currentColor"/></svg>
        </button>
      </div>

      {/* ── Bottom attribution ── */}
      <div className="lm-attribution">Map data © GeoTagging · Location Intelligence Platform</div>

      {/* ── Modal overlay ── */}
      {open && (
        <div className="lm-modal-overlay" onClick={closeModal}>
          <div className="lm-card" onClick={e => e.stopPropagation()}>

            {/* close button */}
            <button className="lm-card-close" onClick={closeModal} aria-label="Close">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z" fill="currentColor"/></svg>
            </button>

            <div className="lm-card-brand">
              <div className="lm-card-icon">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
                  <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" fill="currentColor"/>
                </svg>
              </div>
              <div>
                <div className="lm-card-title">GeoTagging</div>
                <div className="lm-card-sub">Location Intelligence CRM</div>
              </div>
            </div>

            <div className="lm-card-divider"/>
            <h2 className="lm-card-h2">Sign in</h2>

            <form onSubmit={handleSubmit} className="lm-form">
              <div className="lm-field">
                <label>Email</label>
                <div className="lm-input-wrap">
                  <svg className="lm-input-icon" width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z" fill="currentColor"/></svg>
                  <input type="email" placeholder="you@example.com" value={email}
                    onChange={e => { setEmail(e.target.value); setError('') }} required autoFocus/>
                </div>
              </div>

              <div className="lm-field">
                <label>Password</label>
                <div className="lm-input-wrap lm-pass-wrap">
                  <svg className="lm-input-icon" width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z" fill="currentColor"/></svg>
                  <input type={showPass ? 'text' : 'password'} placeholder="Password" value={password}
                    onChange={e => { setPassword(e.target.value); setError('') }} required
                    style={{paddingLeft:36, paddingRight:42, marginBottom:0}}/>
                  <button type="button" className="lm-pass-toggle" onClick={() => setShowPass(v=>!v)} tabIndex={-1}>
                    {showPass ? '🙈' : '👁'}
                  </button>
                </div>
              </div>

              {error && (
                <div className="lm-error">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" style={{flexShrink:0}}><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z" fill="currentColor"/></svg>
                  {error}
                </div>
              )}

              <button type="submit" className="lm-btn" disabled={loading}>
                {loading
                  ? <><div className="spinner" style={{width:14,height:14,borderTopColor:'#fff'}}/>Signing in…</>
                  : <>Sign in <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M12 4l-1.41 1.41L16.17 11H4v2h12.17l-5.58 5.59L12 20l8-8z" fill="currentColor"/></svg></>
                }
              </button>
            </form>

            <div className="lm-divider"><span>quick access</span></div>

            <div className="lm-creds">
              {[
                { em:'admin@geotagging.com', pw:'admin123', label:'Admin', color:'#4285f4' },
                { em:'demo@geotagging.com',  pw:'demo123',  label:'Demo',  color:'#34a853' },
              ].map(({ em, pw, label, color }) => (
                <button key={em} className="lm-cred-btn" onClick={() => quickLogin(em, pw)}>
                  <div className="lm-cred-dot" style={{background: color}}>{label[0]}</div>
                  <div className="lm-cred-info">
                    <div className="lm-cred-email">{em}</div>
                    <div className="lm-cred-pw">{pw}</div>
                  </div>
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" className="lm-cred-arrow"><path d="M12 4l-1.41 1.41L16.17 11H4v2h12.17l-5.58 5.59L12 20l8-8z" fill="currentColor"/></svg>
                </button>
              ))}
            </div>

            <div className="lm-card-footer">© 2026 GeoTagging CRM</div>
          </div>
        </div>
      )}
    </div>
  )
}
