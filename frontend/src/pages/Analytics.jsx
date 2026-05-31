import React, { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getPhotos, getProfiles } from '../api'

// Priority categories (most urgent first)
const CATEGORIES = [
  { value: 'asap',     label: 'ASAP',     color: '#ef4444' },
  { value: 'special',  label: 'Special',  color: '#f59e0b' },
  { value: 'next_day', label: 'Next Day', color: '#eab308' },
  { value: 'standard', label: 'Standard', color: '#10b981' },
]
const normalizeCat = (v) => {
  const x = (v || 'standard').toLowerCase()
  if (x === 'rush') return 'asap'
  if (x === 'airport') return 'special'
  return CATEGORIES.some(c => c.value === x) ? x : 'standard'
}
const catOf = (v) => CATEGORIES.find(c => c.value === normalizeCat(v)) || CATEGORIES[3]
const photoCat = (p) => catOf(p.category || p.service_type)

const ACCENT = '#7C3AED'
const fmtDate = (t) => {
  if (!t) return '—'
  const d = new Date(t)
  return isNaN(d) ? '—' : d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

export default function Analytics() {
  const [photos, setPhotos] = useState([])
  const [profiles, setProfiles] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const navigate = useNavigate()

  useEffect(() => {
    Promise.all([getPhotos(), getProfiles()])
      .then(([ph, pr]) => { setPhotos(ph || []); setProfiles(pr || []) })
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  // ── Metrics ────────────────────────────────────────────────────────────
  const parseTs = (t) => { const d = new Date(t); return isNaN(d) ? null : d }
  const daysAgo = (t) => { const d = parseTs(t); return d ? (Date.now() - d.getTime()) / 86400000 : Infinity }
  const total = photos.length
  const thisWeek = photos.filter(p => daysAgo(p.timestamp) <= 7).length
  const prevWeek = photos.filter(p => { const d = daysAgo(p.timestamp); return d > 7 && d <= 14 }).length
  const weekDelta = prevWeek === 0 ? (thisWeek > 0 ? 100 : 0) : Math.round(((thisWeek - prevWeek) / prevWeek) * 100)
  const geotagged = photos.filter(p => p.latitude && p.longitude).length
  const geoPct = total ? Math.round((geotagged / total) * 100) : 0
  const now = new Date()
  const thisMonth = photos.filter(p => { const d = parseTs(p.timestamp); return d && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear() }).length
  const asap = photos.filter(p => photoCat(p).value === 'asap').length
  const asapPct = total ? Math.round((asap / total) * 100) : 0

  // Weekly bars — last 7 days
  const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
  const weekly = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - (6 - i))
    const next = new Date(d); next.setDate(d.getDate() + 1)
    const count = photos.filter(p => { const t = parseTs(p.timestamp); return t && t >= d && t < next }).length
    return { label: WD[d.getDay()], count }
  })
  const weeklyMax = Math.max(1, ...weekly.map(w => w.count))

  // Category breakdown for the "at a glance" donut
  const catCounts = CATEGORIES.map(c => ({ ...c, n: photos.filter(p => photoCat(p).value === c.value).length }))

  // Recent uploads
  const recent = [...photos]
    .sort((a, b) => String(b.timestamp || '').localeCompare(String(a.timestamp || '')))
    .filter(p => !search || (p.profile_name || '').toLowerCase().includes(search.toLowerCase()) || (p.address || '').toLowerCase().includes(search.toLowerCase()))
    .slice(0, 8)

  const card = { background: '#fff', border: '1px solid #ececf3', borderRadius: 16, boxShadow: '0 4px 18px rgba(15,23,42,0.05)' }

  const KPIS = [
    { label: 'Total Photos',  val: total,      icon: '🖼', tint: ACCENT,    sub: `+${thisWeek} this week`, subColor: '#10b981', up: weekDelta >= 0 },
    { label: 'Active Profiles', val: profiles.length, icon: '👥', tint: '#10b981', sub: 'profiles tracked', subColor: '#94a3b8' },
    { label: 'Geotagged',     val: geotagged,  icon: '📍', tint: '#2563eb',  sub: `${geoPct}% of photos`,  subColor: '#2563eb' },
    { label: 'ASAP',          val: asap,       icon: '⚡', tint: '#ef4444',  sub: `${asapPct}% priority`,  subColor: '#ef4444' },
  ]

  // donut for geotagged %
  const R = 42, C = 2 * Math.PI * R

  return (
    <div style={{ padding: '20px 28px', height: '100vh', overflowY: 'auto', background: '#f6f5fb' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 20 }}>
        <div>
          <div style={{ fontSize: 26, fontWeight: 800, color: '#0f172a', letterSpacing: '-0.6px' }}>Analytics</div>
          <div style={{ fontSize: 13.5, color: '#64748b', marginTop: 2 }}>A detailed look at your GeoTag activity</div>
        </div>
        <div style={{ marginLeft: 'auto', position: 'relative', minWidth: 240 }}>
          <span style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: '#94a3b8' }}>🔍</span>
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search uploads…"
            style={{ width: '100%', padding: '10px 12px 10px 34px', borderRadius: 12, border: '1px solid #ececf3', background: '#fff', fontSize: 13.5, outline: 'none' }} />
        </div>
      </div>

      {loading ? (
        <div style={{ padding: 60, textAlign: 'center', color: '#94a3b8' }}>Loading analytics…</div>
      ) : (
        <>
          {/* KPI cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: 16, marginBottom: 16 }}>
            {KPIS.map((k, i) => (
              <div key={i} style={{ ...card, padding: 18 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div style={{ fontSize: 12.5, color: '#64748b', fontWeight: 600 }}>{k.label}</div>
                  <div style={{ width: 34, height: 34, borderRadius: 10, background: `${k.tint}1a`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16 }}>{k.icon}</div>
                </div>
                <div style={{ fontSize: 30, fontWeight: 800, color: '#0f172a', letterSpacing: '-1px', marginTop: 8 }}>{k.val.toLocaleString()}</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 8, fontSize: 12, fontWeight: 700, color: k.subColor }}>
                  {k.up !== undefined && <span>{k.up ? '↗' : '↘'}</span>}
                  {k.sub}
                </div>
              </div>
            ))}
          </div>

          {/* Middle row: Year-at-a-glance (dark) + Uploads chart */}
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(280px, 1fr) 1.6fr', gap: 16, marginBottom: 16 }}>
            {/* At a glance — dark card with donut */}
            <div style={{ background: '#1f2030', borderRadius: 16, padding: 20, color: '#fff', display: 'flex', gap: 16, alignItems: 'center', boxShadow: '0 8px 26px rgba(15,23,42,0.18)' }}>
              <div>
                <div style={{ fontSize: 16, fontWeight: 800 }}>At A Glance</div>
                <div style={{ fontSize: 12.5, color: '#a9adc4', marginTop: 6, lineHeight: 1.5 }}>
                  {geotagged} of {total} photos are GPS-verified.
                </div>
                <div style={{ marginTop: 14, background: 'rgba(255,255,255,0.08)', borderRadius: 12, padding: '10px 12px' }}>
                  <div style={{ fontSize: 22, fontWeight: 800 }}>{thisMonth}</div>
                  <div style={{ fontSize: 11.5, color: '#a9adc4' }}>captured this month</div>
                </div>
              </div>
              <div style={{ position: 'relative', width: 110, height: 110, marginLeft: 'auto' }}>
                <svg viewBox="0 0 100 100" style={{ width: 110, height: 110 }}>
                  <circle cx="50" cy="50" r={R} fill="none" stroke="rgba(255,255,255,0.14)" strokeWidth="10" />
                  <circle cx="50" cy="50" r={R} fill="none" stroke="#fbbf24" strokeWidth="10" strokeLinecap="round"
                    strokeDasharray={`${(C * geoPct) / 100} ${C}`} transform="rotate(-90 50 50)" />
                </svg>
                <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
                  <div style={{ fontSize: 20, fontWeight: 800 }}>{geoPct}%</div>
                  <div style={{ fontSize: 10, color: '#a9adc4' }}>Geotagged</div>
                </div>
              </div>
            </div>

            {/* Photos by category — colored bar chart */}
            <div style={{ ...card, padding: 18 }}>
              <div style={{ display: 'flex', alignItems: 'center' }}>
                <div>
                  <div style={{ fontSize: 16, fontWeight: 800, color: '#0f172a' }}>Photos by Category</div>
                  <div style={{ fontSize: 12, color: '#94a3b8' }}>Distribution across priorities</div>
                </div>
                <div style={{ marginLeft: 'auto', fontSize: 12, color: '#64748b', fontWeight: 700, background: '#f1f5f9', padding: '5px 12px', borderRadius: 9 }}>
                  {total} total
                </div>
              </div>
              {(() => {
                const catMax = Math.max(1, ...catCounts.map(c => c.n))
                return (
                  <div style={{ display: 'flex', alignItems: 'flex-end', gap: 18, height: 160, marginTop: 18, padding: '0 8px' }}>
                    {catCounts.map(c => {
                      const pct = total ? Math.round((c.n / total) * 100) : 0
                      return (
                        <div key={c.value} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, height: '100%' }}>
                          <div style={{ fontSize: 13, fontWeight: 800, color: c.color }}>{c.n}</div>
                          <div style={{ flex: 1, width: '100%', maxWidth: 54, margin: '0 auto', display: 'flex', alignItems: 'flex-end' }}>
                            <div title={`${c.label}: ${c.n} (${pct}%)`} style={{
                              width: '100%', borderRadius: '10px 10px 0 0',
                              height: `${(c.n / catMax) * 100}%`, minHeight: c.n > 0 ? 10 : 4,
                              background: c.n > 0
                                ? `linear-gradient(180deg, ${c.color}, ${c.color}cc)`
                                : '#eef2f7',
                              boxShadow: c.n > 0 ? `0 6px 16px ${c.color}44` : 'none',
                              transition: 'height .35s ease',
                            }} />
                          </div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                            <span style={{ width: 8, height: 8, borderRadius: '50%', background: c.color }} />
                            <span style={{ fontSize: 11.5, color: '#475569', fontWeight: 600 }}>{c.label}</span>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )
              })()}
            </div>
          </div>

          {/* Bottom row: category breakdown + recent uploads table */}
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(260px, 1fr) 2fr', gap: 16 }}>
            {/* Category breakdown */}
            <div style={{ ...card, padding: 18 }}>
              <div style={{ fontSize: 16, fontWeight: 800, color: '#0f172a', marginBottom: 14 }}>By Category</div>
              {catCounts.map(c => {
                const pct = total ? Math.round((c.n / total) * 100) : 0
                return (
                  <div key={c.value} style={{ marginBottom: 14 }}>
                    <div style={{ display: 'flex', alignItems: 'center', fontSize: 13, marginBottom: 5 }}>
                      <span style={{ width: 8, height: 8, borderRadius: '50%', background: c.color, marginRight: 8 }} />
                      <span style={{ fontWeight: 700, color: '#0f172a' }}>{c.label}</span>
                      <span style={{ marginLeft: 'auto', color: '#64748b', fontWeight: 600 }}>{c.n} · {pct}%</span>
                    </div>
                    <div style={{ height: 8, borderRadius: 999, background: '#f1f5f9', overflow: 'hidden' }}>
                      <div style={{ height: '100%', width: `${pct}%`, background: c.color, borderRadius: 999, transition: 'width .3s ease' }} />
                    </div>
                  </div>
                )
              })}
            </div>

            {/* Recent uploads table */}
            <div style={{ ...card, overflow: 'hidden' }}>
              <div style={{ display: 'flex', alignItems: 'center', padding: '16px 18px', borderBottom: '1px solid #f1f5f9' }}>
                <div style={{ fontSize: 16, fontWeight: 800, color: '#0f172a' }}>Recent Uploads</div>
                <button onClick={() => navigate('/log')} style={{ marginLeft: 'auto', background: 'transparent', border: 'none', color: ACCENT, fontWeight: 700, fontSize: 13, cursor: 'pointer' }}>View All</button>
              </div>
              {recent.length === 0 ? (
                <div style={{ padding: 36, textAlign: 'center', color: '#94a3b8', fontSize: 13 }}>No uploads yet</div>
              ) : (
                <div style={{ overflowX: 'auto' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                    <thead>
                      <tr>
                        {['Name', 'Date', 'Location', 'Category'].map(h => (
                          <th key={h} style={{ textAlign: 'left', padding: '10px 18px', fontSize: 11, fontWeight: 700, letterSpacing: '0.05em', textTransform: 'uppercase', color: '#94a3b8' }}>{h}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {recent.map(p => {
                        const c = photoCat(p)
                        return (
                          <tr key={p.id} onClick={() => navigate(`/profiles/${p.profile_id}`)}
                            style={{ cursor: 'pointer', borderTop: '1px solid #f5f7fa' }}
                            onMouseEnter={e => e.currentTarget.style.background = '#faf5ff'}
                            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                            <td style={{ padding: '11px 18px' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                                <img src={p.image_url} alt="" loading="lazy"
                                  onError={e => { e.target.src = 'https://via.placeholder.com/36/e2e8f0/64748b?text=P' }}
                                  style={{ width: 34, height: 34, borderRadius: 8, objectFit: 'cover', border: `2px solid ${c.color}` }} />
                                <span style={{ fontWeight: 700, fontSize: 13.5, color: '#0f172a' }}>{p.profile_name || 'Unknown'}</span>
                              </div>
                            </td>
                            <td style={{ padding: '11px 18px', fontSize: 12.5, color: '#64748b', whiteSpace: 'nowrap' }}>{fmtDate(p.timestamp)}</td>
                            <td style={{ padding: '11px 18px', fontSize: 13, color: '#0f172a', maxWidth: 240, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p.address || (p.zip_code ? `ZIP ${p.zip_code}` : '—')}</td>
                            <td style={{ padding: '11px 18px' }}>
                              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 700, color: c.color, background: `${c.color}14`, border: `1px solid ${c.color}33`, padding: '3px 10px', borderRadius: 999 }}>
                                <span style={{ width: 6, height: 6, borderRadius: '50%', background: c.color }} /> {c.label}
                              </span>
                            </td>
                          </tr>
                        )
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
