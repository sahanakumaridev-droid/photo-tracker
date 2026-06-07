import React, { useState, useEffect } from 'react'
import { getEarnings, getPayouts } from '../api'

const ACCENT = '#7C3AED'
const PERIODS = [
  { key: 'today',    label: 'Today' },
  { key: 'week',     label: 'This Week' },
  { key: 'biweekly', label: 'Bi-Weekly' },
  { key: 'month',    label: 'Monthly' },
]

const money = (n) => `$${(Number(n) || 0).toLocaleString()}`
const card = { background: '#fff', border: '1px solid #ececf3', borderRadius: 16, boxShadow: '0 4px 18px rgba(15,23,42,0.05)' }

// F8 / F9 — Earnings dashboard (Uber-driver style) + Payouts / Timesheets
export default function Earnings() {
  const [period, setPeriod]   = useState('today')
  const [summary, setSummary] = useState(null)
  const [payouts, setPayouts] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let alive = true
    setLoading(true)
    Promise.all([getEarnings(period), getPayouts()])
      .then(([s, p]) => { if (alive) { setSummary(s); setPayouts(p) } })
      .catch(() => {})
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [period])

  const periodLabel = PERIODS.find(p => p.key === period)?.label ?? ''
  const daily = summary?.daily_totals || []
  const maxDay = Math.max(1, ...daily.map(d => d.amount))
  const payoutDays = payouts?.daily || []

  const KPIS = [
    { label: 'Total Earnings',  val: money(summary?.total_earnings),  icon: '💰', tint: '#10b981', sub: periodLabel },
    { label: 'Jobs Completed',  val: (summary?.jobs_completed ?? 0).toLocaleString(), icon: '✅', tint: ACCENT, sub: 'closed jobs' },
    { label: 'Average / Job',   val: money(summary?.average_per_job), icon: '📊', tint: '#2563eb', sub: 'per completed job' },
  ]

  return (
    <div style={{ padding: '20px 28px', height: '100vh', overflowY: 'auto', background: '#f6f5fb' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 20, flexWrap: 'wrap' }}>
        <div>
          <div style={{ fontSize: 26, fontWeight: 800, color: '#0f172a', letterSpacing: '-0.6px' }}>Earnings</div>
          <div style={{ fontSize: 13.5, color: '#64748b', marginTop: 2 }}>Track completed jobs and payouts · Uber-style</div>
        </div>
        {/* Period segmented control */}
        <div style={{ marginLeft: 'auto', display: 'inline-flex', background: '#fff', border: '1px solid #ececf3', borderRadius: 12, padding: 4, gap: 2 }}>
          {PERIODS.map(p => {
            const sel = period === p.key
            return (
              <button key={p.key} onClick={() => setPeriod(p.key)}
                style={{
                  padding: '8px 16px', borderRadius: 9, fontWeight: 700, fontSize: 13, cursor: 'pointer', border: 'none',
                  background: sel ? ACCENT : 'transparent',
                  color: sel ? '#fff' : '#64748b',
                  boxShadow: sel ? '0 4px 12px rgba(124,58,237,0.3)' : 'none',
                  transition: 'all .15s ease',
                }}>{p.label}</button>
            )
          })}
        </div>
      </div>

      {loading ? (
        <div style={{ padding: 60, textAlign: 'center', color: '#94a3b8' }}>Loading earnings…</div>
      ) : (
        <>
          {/* Hero + KPIs row */}
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(280px, 1fr) 1.7fr', gap: 16, marginBottom: 16 }}>
            {/* Dark hero card */}
            <div style={{ background: 'linear-gradient(145deg,#2a1b4d 0%,#1f2030 70%)', borderRadius: 16, padding: 22, color: '#fff', boxShadow: '0 8px 26px rgba(124,58,237,0.25)' }}>
              <div style={{ fontSize: 13, color: '#c4b5fd', fontWeight: 600 }}>{periodLabel} earnings</div>
              <div style={{ fontSize: 42, fontWeight: 800, letterSpacing: '-1.5px', marginTop: 6 }}>{money(summary?.total_earnings)}</div>
              <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
                <div style={{ flex: 1, background: 'rgba(255,255,255,0.08)', borderRadius: 12, padding: '10px 12px' }}>
                  <div style={{ fontSize: 20, fontWeight: 800 }}>{summary?.jobs_completed ?? 0}</div>
                  <div style={{ fontSize: 11, color: '#a9adc4' }}>jobs done</div>
                </div>
                <div style={{ flex: 1, background: 'rgba(255,255,255,0.08)', borderRadius: 12, padding: '10px 12px' }}>
                  <div style={{ fontSize: 20, fontWeight: 800 }}>{money(summary?.average_per_job)}</div>
                  <div style={{ fontSize: 11, color: '#a9adc4' }}>avg / job</div>
                </div>
              </div>
            </div>

            {/* KPI cards */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(170px, 1fr))', gap: 16 }}>
              {KPIS.map((k, i) => (
                <div key={i} style={{ ...card, padding: 18, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <div style={{ fontSize: 12.5, color: '#64748b', fontWeight: 600 }}>{k.label}</div>
                    <div style={{ width: 34, height: 34, borderRadius: 10, background: `${k.tint}1a`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16 }}>{k.icon}</div>
                  </div>
                  <div style={{ fontSize: 28, fontWeight: 800, color: '#0f172a', letterSpacing: '-1px', marginTop: 8 }}>{k.val}</div>
                  <div style={{ fontSize: 12, fontWeight: 600, color: '#94a3b8', marginTop: 4 }}>{k.sub}</div>
                </div>
              ))}
            </div>
          </div>

          {/* Earnings trend */}
          <div style={{ ...card, padding: 18, marginBottom: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: 4 }}>
              <div>
                <div style={{ fontSize: 16, fontWeight: 800, color: '#0f172a' }}>Earnings Trend</div>
                <div style={{ fontSize: 12, color: '#94a3b8' }}>Daily totals for {periodLabel.toLowerCase()}</div>
              </div>
              <div style={{ marginLeft: 'auto', fontSize: 12, color: '#64748b', fontWeight: 700, background: '#f1f5f9', padding: '5px 12px', borderRadius: 9 }}>{money(summary?.total_earnings)}</div>
            </div>
            {daily.length === 0 ? (
              <div style={{ padding: 40, textAlign: 'center', color: '#94a3b8', fontSize: 13 }}>No completed jobs in this period yet.</div>
            ) : (
              <div style={{ display: 'flex', alignItems: 'flex-end', gap: 14, height: 170, marginTop: 18, padding: '0 8px' }}>
                {daily.map(d => (
                  <div key={d.date} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, height: '100%' }}>
                    <div style={{ fontSize: 12.5, fontWeight: 800, color: ACCENT }}>{money(d.amount)}</div>
                    <div style={{ flex: 1, width: '100%', maxWidth: 46, margin: '0 auto', display: 'flex', alignItems: 'flex-end' }}>
                      <div title={`${d.date}: ${money(d.amount)}`} style={{
                        width: '100%', borderRadius: '10px 10px 0 0',
                        height: `${(d.amount / maxDay) * 100}%`, minHeight: d.amount > 0 ? 10 : 4,
                        background: d.amount > 0 ? `linear-gradient(180deg, ${ACCENT}, #a78bfa)` : '#eef2f7',
                        boxShadow: d.amount > 0 ? '0 6px 16px rgba(124,58,237,0.28)' : 'none',
                        transition: 'height .35s ease',
                      }} />
                    </div>
                    <div style={{ fontSize: 11, color: '#475569', fontWeight: 600 }}>{d.date.slice(5)}</div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Payouts / Timesheets table */}
          <div style={{ ...card, overflow: 'hidden' }}>
            <div style={{ display: 'flex', alignItems: 'center', padding: '16px 18px', borderBottom: '1px solid #f1f5f9' }}>
              <div style={{ fontSize: 16, fontWeight: 800, color: '#0f172a' }}>Payouts / Timesheets</div>
              <div style={{ marginLeft: 'auto', fontSize: 13, fontWeight: 800, color: '#10b981' }}>
                {money(payouts?.total_earnings)} · {payouts?.total_jobs ?? 0} jobs
              </div>
            </div>
            {payoutDays.length === 0 ? (
              <div style={{ padding: 36, textAlign: 'center', color: '#94a3b8', fontSize: 13 }}>No closed jobs yet. Mark jobs complete to see payouts.</div>
            ) : (
              <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                <thead>
                  <tr>
                    {['Date', 'Jobs', 'Daily Total'].map(h => (
                      <th key={h} style={{ textAlign: h === 'Daily Total' ? 'right' : 'left', padding: '10px 18px', fontSize: 11, fontWeight: 700, letterSpacing: '0.05em', textTransform: 'uppercase', color: '#94a3b8' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {payoutDays.map(d => (
                    <tr key={d.date} style={{ borderTop: '1px solid #f5f7fa' }}>
                      <td style={{ padding: '12px 18px', fontSize: 13.5, fontWeight: 600, color: '#0f172a' }}>{d.date}</td>
                      <td style={{ padding: '12px 18px', fontSize: 13, color: '#64748b' }}>{d.jobs}</td>
                      <td style={{ padding: '12px 18px', textAlign: 'right', fontSize: 14, fontWeight: 800, color: '#10b981' }}>{money(d.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}
    </div>
  )
}
