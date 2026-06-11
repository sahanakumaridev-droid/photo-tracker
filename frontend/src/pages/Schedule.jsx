import React, { useState, useEffect } from 'react'
import { getSchedule } from '../api'
import { useTheme } from '../context/ThemeContext'

const QUEUES = [
  { key: 'asap',     label: 'ASAP',     color: '#ef4444', icon: '⚡', hint: 'Highest priority' },
  { key: 'special',  label: 'Special',  color: '#f59e0b', icon: '★',  hint: 'Special / S.O.' },
  { key: 'next_day', label: 'Next Day', color: '#eab308', icon: '⏭', hint: 'Scheduled next day' },
  { key: 'standard', label: 'Standard', color: '#10b981', icon: '✓',  hint: 'Standard queue' },
]

export default function Schedule() {
  const [queues, setQueues] = useState({})
  const [loading, setLoading] = useState(true)
  const { mode } = useTheme()
  const isDark = mode === 'dark'

  const th = {
    pageBg:      isDark ? '#0f0e1a'                : '#f6f5fb',
    card:        { background: isDark ? '#1a1830' : '#fff', border: `1px solid ${isDark ? 'rgba(255,255,255,0.08)' : '#ececf3'}`, borderRadius: 16, boxShadow: isDark ? '0 4px 18px rgba(0,0,0,0.4)' : '0 4px 18px rgba(15,23,42,0.05)' },
    text1:       isDark ? '#f1f5f9'                : '#0f172a',
    text2:       isDark ? 'rgba(255,255,255,0.6)'  : '#64748b',
    text3:       isDark ? 'rgba(255,255,255,0.35)' : '#94a3b8',
    pillBg:      isDark ? 'rgba(255,255,255,0.08)' : '#fff',
    pillBorder:  isDark ? 'rgba(255,255,255,0.12)' : '#ececf3',
    jobCardBg:   isDark ? 'rgba(255,255,255,0.04)' : '#fafafe',
    jobCardBorder: isDark ? 'rgba(255,255,255,0.07)' : '#f1f0f7',
    emptyColor:  isDark ? 'rgba(255,255,255,0.2)'  : '#cbd5e1',
  }

  useEffect(() => {
    getSchedule()
      .then(d => setQueues(d.queues || {}))
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  const total = QUEUES.reduce((n, q) => n + (queues[q.key]?.length || 0), 0)

  return (
    <div style={{ padding: '20px 28px', height: '100vh', overflowY: 'auto', background: th.pageBg }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 20, flexWrap: 'wrap' }}>
        <div>
          <div style={{ fontSize: 26, fontWeight: 800, color: th.text1, letterSpacing: '-0.6px' }}>Schedule</div>
          <div style={{ fontSize: 13.5, color: th.text2, marginTop: 2 }}>Jobs grouped into queues by service level</div>
        </div>
        <div style={{ marginLeft: 'auto', fontSize: 12, color: th.text2, fontWeight: 700, background: th.pillBg, border: `1px solid ${th.pillBorder}`, padding: '8px 14px', borderRadius: 10 }}>
          {total} active job{total !== 1 ? 's' : ''}
        </div>
      </div>

      {/* KPI strip — count per queue */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 16, marginBottom: 18 }}>
        {QUEUES.map(q => {
          const n = queues[q.key]?.length || 0
          return (
            <div key={q.key} style={{ ...th.card, padding: 18, borderTop: `3px solid ${q.color}` }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <div style={{ fontSize: 12.5, color: th.text2, fontWeight: 700 }}>{q.label}</div>
                <div style={{ width: 34, height: 34, borderRadius: 10, background: `${q.color}1a`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, color: q.color }}>{q.icon}</div>
              </div>
              <div style={{ fontSize: 30, fontWeight: 800, color: th.text1, letterSpacing: '-1px', marginTop: 8 }}>{n}</div>
              <div style={{ fontSize: 12, color: th.text3, fontWeight: 600, marginTop: 2 }}>{q.hint}</div>
            </div>
          )
        })}
      </div>

      {/* Queue columns */}
      {loading ? (
        <div style={{ padding: 60, textAlign: 'center', color: th.text3 }}>Loading schedule…</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 16 }}>
          {QUEUES.map(q => {
            const items = queues[q.key] || []
            return (
              <div key={q.key} style={{ ...th.card, overflow: 'hidden' }}>
                {/* Column header */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '14px 16px', background: `${q.color}0f`, borderBottom: `1px solid ${q.color}22` }}>
                  <span style={{ width: 10, height: 10, borderRadius: '50%', background: q.color }} />
                  <span style={{ fontWeight: 800, color: th.text1, fontSize: 14 }}>{q.label} Queue</span>
                  <span style={{ marginLeft: 'auto', background: q.color, color: '#fff', borderRadius: 999, padding: '2px 10px', fontWeight: 800, fontSize: 12 }}>{items.length}</span>
                </div>

                {/* Jobs */}
                <div style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 10, minHeight: 80 }}>
                  {items.length === 0 ? (
                    <div style={{ color: th.emptyColor, fontSize: 13, padding: '18px 0', textAlign: 'center' }}>No jobs</div>
                  ) : items.map(it => (
                    <div key={it.location_group_id} style={{ background: th.jobCardBg, border: `1px solid ${th.jobCardBorder}`, borderRadius: 12, padding: 12, borderLeft: `3px solid ${q.color}` }}>
                      <div style={{ display: 'flex', alignItems: 'center' }}>
                        <span style={{ fontWeight: 700, fontSize: 13.5, color: th.text1 }}>
                          {it.attempts?.[0]?.profile_name || `Pin #${it.location_group_id}`}
                        </span>
                        {it.pay_rate != null && (
                          <span style={{ marginLeft: 'auto', fontWeight: 800, fontSize: 13, color: '#10b981', background: '#10b98114', border: '1px solid #10b98133', borderRadius: 999, padding: '2px 9px' }}>${it.pay_rate}</span>
                        )}
                      </div>
                      <div style={{ fontSize: 12, color: th.text2, marginTop: 5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        📍 {it.address || `${it.latitude?.toFixed(4)}, ${it.longitude?.toFixed(4)}`}
                      </div>
                      <div style={{ fontSize: 11.5, color: th.text3, marginTop: 5, fontWeight: 600 }}>
                        {it.attempt_count} attempt{it.attempt_count !== 1 ? 's' : ''}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
