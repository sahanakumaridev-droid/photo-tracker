import React, { useState, useEffect } from 'react'
import { getArchive } from '../api'

const ACCENT = '#7C3AED'
const card = { background: '#fff', border: '1px solid #ececf3', borderRadius: 16, boxShadow: '0 4px 18px rgba(15,23,42,0.05)' }

// Service-level palette (matched to Analytics categories)
const CAT = {
  asap:     { label: 'ASAP',     color: '#ef4444' },
  special:  { label: 'Special',  color: '#f59e0b' },
  next_day: { label: 'Next Day', color: '#eab308' },
  standard: { label: 'Standard', color: '#10b981' },
}
const catOf = (v) => CAT[(v || 'standard').toLowerCase()] || CAT.standard

const SERVICE = [
  { key: '',         label: 'All' },
  { key: 'asap',     label: 'ASAP' },
  { key: 'next_day', label: 'Next Day' },
  { key: 'standard', label: 'Standard' },
  { key: 'special',  label: 'Special' },
]

const fmtDate = (t) => {
  if (!t) return '—'
  const d = new Date(t)
  return isNaN(d) ? '—' : d.toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

// F10 — Job Archive (search / review / filter archived jobs)
export default function Archive() {
  const [rows, setRows]       = useState([])
  const [search, setSearch]   = useState('')
  const [service, setService] = useState('')
  const [loading, setLoading] = useState(true)

  const load = () => {
    setLoading(true)
    getArchive({ ...(search ? { search } : {}), ...(service ? { service_level: service } : {}) })
      .then(setRows).catch(() => {}).finally(() => setLoading(false))
  }
  useEffect(() => { load() }, [service])
  useEffect(() => { const t = setTimeout(load, 300); return () => clearTimeout(t) }, [search])

  const totalPay = rows.reduce((s, r) => s + (Number(r.pay_rate) || 0), 0)

  return (
    <div style={{ padding: '20px 28px', height: '100vh', overflowY: 'auto', background: '#f6f5fb' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 20, flexWrap: 'wrap' }}>
        <div>
          <div style={{ fontSize: 26, fontWeight: 800, color: '#0f172a', letterSpacing: '-0.6px' }}>Archive</div>
          <div style={{ fontSize: 13.5, color: '#64748b', marginTop: 2 }}>Completed jobs are retained here — search and review anytime</div>
        </div>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 10 }}>
          <div style={{ ...card, padding: '10px 16px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <div style={{ fontSize: 20, fontWeight: 800, color: '#0f172a' }}>{rows.length}</div>
            <div style={{ fontSize: 11, color: '#94a3b8', fontWeight: 600 }}>archived</div>
          </div>
          <div style={{ ...card, padding: '10px 16px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <div style={{ fontSize: 20, fontWeight: 800, color: '#10b981' }}>${totalPay.toLocaleString()}</div>
            <div style={{ fontSize: 11, color: '#94a3b8', fontWeight: 600 }}>total pay</div>
          </div>
        </div>
      </div>

      {/* Search + filter bar */}
      <div style={{ ...card, padding: 14, marginBottom: 18, display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 220 }}>
          <span style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: '#94a3b8' }}>🔍</span>
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search archived jobs…"
            style={{ width: '100%', padding: '10px 12px 10px 34px', borderRadius: 10, border: '1px solid #ececf3', background: '#f8fafc', fontSize: 13.5, outline: 'none' }} />
        </div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {SERVICE.map(s => {
            const sel = service === s.key
            const c = s.key ? catOf(s.key).color : ACCENT
            return (
              <button key={s.key} onClick={() => setService(s.key)}
                style={{
                  padding: '8px 14px', borderRadius: 999, fontWeight: 700, fontSize: 12.5, cursor: 'pointer',
                  border: '1px solid ' + (sel ? c : '#e2e8f0'),
                  background: sel ? c : '#fff',
                  color: sel ? '#fff' : '#64748b',
                  transition: 'all .15s ease',
                }}>{s.label}</button>
            )
          })}
        </div>
      </div>

      {loading ? (
        <div style={{ padding: 60, textAlign: 'center', color: '#94a3b8' }}>Loading archive…</div>
      ) : rows.length === 0 ? (
        <div style={{ ...card, padding: 60, textAlign: 'center' }}>
          <div style={{ fontSize: 40, marginBottom: 10 }}>🗄️</div>
          <div style={{ fontSize: 15, fontWeight: 700, color: '#0f172a' }}>No archived jobs found</div>
          <div style={{ fontSize: 13, color: '#94a3b8', marginTop: 4 }}>Completed jobs you archive will appear here.</div>
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 16 }}>
          {rows.map(r => {
            const c = catOf(r.category)
            return (
              <div key={r.id} style={{ ...card, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
                <div style={{ position: 'relative', height: 150, background: '#f1f5f9' }}>
                  {r.image_url && (
                    <img src={r.image_url} alt="" loading="lazy"
                      onError={e => { e.target.src = 'https://via.placeholder.com/260x150/e2e8f0/64748b?text=Photo' }}
                      style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  )}
                  {/* category pill */}
                  <span style={{ position: 'absolute', top: 10, left: 10, display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11, fontWeight: 800, color: '#fff', background: c.color, borderRadius: 999, padding: '3px 10px', boxShadow: '0 2px 8px rgba(0,0,0,0.2)' }}>
                    <span style={{ width: 5, height: 5, borderRadius: '50%', background: '#fff' }} />{c.label}
                  </span>
                  {/* archived badge */}
                  <span style={{ position: 'absolute', top: 10, right: 10, fontSize: 10, fontWeight: 700, color: '#fff', background: 'rgba(15,23,42,0.7)', borderRadius: 6, padding: '3px 8px' }}>ARCHIVED</span>
                </div>
                <div style={{ padding: 14, flex: 1, display: 'flex', flexDirection: 'column' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ fontWeight: 800, fontSize: 14.5, color: '#0f172a', flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.profile_name || 'Pin'}</span>
                    {r.pay_rate != null && (
                      <span style={{ fontSize: 12.5, fontWeight: 800, color: '#10b981', background: '#10b98114', border: '1px solid #10b98133', borderRadius: 999, padding: '2px 9px' }}>${r.pay_rate}</span>
                    )}
                  </div>
                  <div style={{ fontSize: 12.5, color: '#475569', marginTop: 6, display: 'flex', gap: 6, alignItems: 'flex-start' }}>
                    <span style={{ color: '#10b981' }}>📍</span>
                    <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{r.address || '—'}</span>
                  </div>
                  <div style={{ marginTop: 'auto', paddingTop: 10, fontSize: 11.5, color: '#94a3b8', fontWeight: 600 }}>🕐 {fmtDate(r.completed_at || r.timestamp)}</div>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
