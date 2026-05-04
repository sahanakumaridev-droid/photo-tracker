import React, { useEffect, useState, useCallback } from 'react'
import { getLog } from '../api'

export default function Log() {
  const today = new Date().toISOString().split('T')[0]

  const [rows,    setRows]    = useState([])
  const [loading, setLoading] = useState(true)
  const [date,    setDate]    = useState(today)
  const [zip,     setZip]     = useState('')
  const [status,  setStatus]  = useState('')
  const [search,  setSearch]  = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    const params = {}
    if (date)   params.date     = date
    if (zip)    params.zip_code = zip
    if (status) params.status   = status
    if (search) params.search   = search
    const data = await getLog(params)
    setRows(data)
    setLoading(false)
  }, [date, zip, status, search])

  useEffect(() => { load() }, [load])

  const rush     = rows.filter(r => r.service_type === 'rush').length
  const standard = rows.filter(r => r.service_type === 'standard').length

  return (
    <div className="log-shell">
      {/* Header */}
      <div className="page-header">
        <div>
          <div className="page-title">Activity Log</div>
          <div className="page-sub">Filter uploads by date, zip, status, or note</div>
        </div>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <span className="log-stat-pill log-stat-rush">{rush} Rush</span>
          <span className="log-stat-pill log-stat-std">{standard} Standard</span>
          <span className="log-stat-pill">{rows.length} Total</span>
        </div>
      </div>

      {/* Filter bar */}
      <div className="log-filters">
        <div className="log-filter-group">
          <label>Date</label>
          <input
            type="date"
            value={date}
            onChange={e => setDate(e.target.value)}
            style={{ marginBottom: 0, width: 160 }}
          />
        </div>

        <div className="log-filter-group">
          <label>Zip Code</label>
          <input
            type="text"
            placeholder="e.g. 92101"
            value={zip}
            onChange={e => setZip(e.target.value)}
            style={{ marginBottom: 0, width: 120 }}
          />
        </div>

        <div className="log-filter-group">
          <label>Status</label>
          <select
            value={status}
            onChange={e => setStatus(e.target.value)}
            style={{ marginBottom: 0, width: 140 }}
          >
            <option value="">All</option>
            <option value="rush">Rush (ASAP)</option>
            <option value="standard">Standard</option>
          </select>
        </div>

        <div className="log-filter-group" style={{ flex: 1 }}>
          <label>Search Notes</label>
          <input
            type="text"
            placeholder="Search note text…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            style={{ marginBottom: 0 }}
          />
        </div>

        <button
          className="btn btn-outline"
          style={{ alignSelf: 'flex-end', fontSize: 12, padding: '9px 14px' }}
          onClick={() => { setDate(today); setZip(''); setStatus(''); setSearch('') }}
        >
          Reset
        </button>
      </div>

      {/* Table */}
      <div className="log-table-wrap">
        {loading ? (
          <div className="dk-loading"><div className="dk-spinner" />Loading…</div>
        ) : rows.length === 0 ? (
          <div className="dk-empty">
            <svg width="36" height="36" viewBox="0 0 24 24" fill="none" opacity="0.3">
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6z" fill="currentColor"/>
            </svg>
            <div>No records match your filters</div>
          </div>
        ) : (
          <table className="log-table">
            <thead>
              <tr>
                <th>Photo</th>
                <th>Profile(s)</th>
                <th>Status</th>
                <th>Date &amp; Time</th>
                <th>Zip Code</th>
                <th>Location</th>
                <th>Note</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.id}>
                  <td>
                    <img
                      src={r.image_url}
                      alt=""
                      className="log-thumb"
                      onError={e => { e.target.src = 'https://via.placeholder.com/48x48/1e1b4b/6366f1?text=P' }}
                    />
                  </td>
                  <td>
                    <div className="log-profiles">
                      {(r.profiles && r.profiles.length > 0 ? r.profiles : [{ name: r.profile_name, service_type: r.service_type }]).map((p, i) => (
                        <span key={i} className="log-profile-chip">{p.name}</span>
                      ))}
                    </div>
                  </td>
                  <td>
                    <span className={`badge badge-${r.service_type}`}>
                      {r.service_type === 'rush' ? '🔴 ASAP' : '🟢 Standard'}
                    </span>
                  </td>
                  <td className="log-mono">{new Date(r.timestamp).toLocaleString()}</td>
                  <td className="log-mono">{r.zip_code || '—'}</td>
                  <td className="log-mono" style={{ fontSize: 11 }}>
                    {r.latitude?.toFixed(4)}, {r.longitude?.toFixed(4)}
                  </td>
                  <td className="log-note">{r.note || <span style={{ opacity: 0.3 }}>—</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
