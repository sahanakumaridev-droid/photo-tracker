import React, { useEffect, useState, useCallback, useRef } from 'react'
import { getLog } from '../api'

// PST formatter
function toPST(ts) {
  if (!ts) return '—'
  return new Date(ts).toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    month: 'short', day: 'numeric', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }) + ' PST'
}

// Build CSV string from rows
function buildCSV(rows) {
  const headers = ['ID', 'Timestamp (PST)', 'Profile(s)', 'Status', 'Zip Code', 'Latitude', 'Longitude', 'Note']
  const escape = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`
  const lines = [
    headers.join(','),
    ...rows.map(r => [
      r.id,
      escape(toPST(r.timestamp)),
      escape((r.profiles?.length > 0 ? r.profiles : [{ name: r.profile_name }]).map(p => p.name).join(' | ')),
      escape(r.service_type),
      escape(r.zip_code || ''),
      r.latitude?.toFixed(6) ?? '',
      r.longitude?.toFixed(6) ?? '',
      escape(r.note || ''),
    ].join(','))
  ]
  return lines.join('\n')
}

// Download a string as a file
function downloadFile(content, filename, mime) {
  const blob = new Blob([content], { type: mime })
  const url  = URL.createObjectURL(blob)
  const a    = document.createElement('a')
  a.href = url; a.download = filename; a.click()
  URL.revokeObjectURL(url)
}

// Build plain-text email body for mailto
function buildEmailBody(rows) {
  if (rows.length === 0) return 'No records found for the selected filters.'
  return rows.map((r, i) => {
    const profiles = (r.profiles?.length > 0 ? r.profiles : [{ name: r.profile_name }]).map(p => p.name).join(', ')
    return [
      `--- Record ${i + 1} ---`,
      `Time:     ${toPST(r.timestamp)}`,
      `Profile:  ${profiles}`,
      `Status:   ${r.service_type}`,
      `Location: ${r.latitude?.toFixed(5)}, ${r.longitude?.toFixed(5)}`,
      `Zip:      ${r.zip_code || '—'}`,
      `Note:     ${r.note || '—'}`,
    ].join('\n')
  }).join('\n\n')
}

export default function Log() {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' }) // YYYY-MM-DD in PST

  const [rows,      setRows]      = useState([])
  const [loading,   setLoading]   = useState(true)
  const [date,      setDate]      = useState(today)
  const [dateTo,    setDateTo]    = useState('')
  const [zip,       setZip]       = useState('')
  const [status,    setStatus]    = useState('')
  const [search,    setSearch]    = useState('')
  const [timeFrom,  setTimeFrom]  = useState('')
  const [timeTo,    setTimeTo]    = useState('')
  const [exporting, setExporting] = useState(false)
  const [exportEmail, setExportEmail] = useState('')
  const [showExport,  setShowExport]  = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    const params = {}
    if (date)   params.date     = date
    if (zip)    params.zip_code = zip
    if (status) params.status   = status
    if (search) params.search   = search
    let data = await getLog(params)

    // Client-side date range filter (dateTo)
    if (dateTo && date) {
      const from = new Date(date + 'T00:00:00-08:00').getTime()
      const to   = new Date(dateTo + 'T23:59:59-08:00').getTime()
      data = data.filter(r => {
        const t = new Date(r.timestamp).getTime()
        return t >= from && t <= to
      })
    }

    // Client-side time-of-day filter
    if (timeFrom || timeTo) {
      data = data.filter(r => {
        const pst = new Date(r.timestamp).toLocaleString('en-US', { timeZone: 'America/Los_Angeles', hour12: false, hour: '2-digit', minute: '2-digit' })
        const [h, m] = pst.split(':').map(Number)
        const mins = h * 60 + m
        const fromMins = timeFrom ? (() => { const [fh, fm] = timeFrom.split(':').map(Number); return fh*60+fm })() : 0
        const toMins   = timeTo   ? (() => { const [th, tm] = timeTo.split(':').map(Number);   return th*60+tm })() : 1440
        return mins >= fromMins && mins <= toMins
      })
    }

    setRows(data)
    setLoading(false)
  }, [date, dateTo, zip, status, search, timeFrom, timeTo])

  useEffect(() => { load() }, [load])

  const rush     = rows.filter(r => r.service_type === 'rush').length
  const standard = rows.filter(r => r.service_type === 'standard').length

  const [shareToast, setShareToast] = useState('')
  const toastTimer = useRef(null)

  const showToast = (msg) => {
    setShareToast(msg)
    clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setShareToast(''), 2800)
  }

  const resetFilters = () => {
    setDate(today); setDateTo(''); setZip(''); setStatus(''); setSearch(''); setTimeFrom(''); setTimeTo('')
  }

  // ── Export handlers ──────────────────────────────────────────────────────

  // 1. Download as CSV (opens in Excel, Numbers, Google Sheets)
  const handleDownloadCSV = () => {
    if (rows.length === 0) { showToast('⚠️ No records to export — adjust your filters first.'); return }
    const ts = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' })
    downloadFile(buildCSV(rows), `geotag-log-${ts}.csv`, 'text/csv;charset=utf-8;')
    showToast(`✅ Downloaded ${rows.length} record${rows.length !== 1 ? 's' : ''} as CSV`)
  }

  // 2. Share via Web Share API (mobile/desktop native share sheet) with clipboard fallback
  const handleShare = async () => {
    if (rows.length === 0) { showToast('⚠️ No records to share — adjust your filters first.'); return }

    const ts  = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' })
    const title = `GeoTag Log — ${rows.length} records — ${ts}`
    const text  = buildEmailBody(rows)

    // Try native share sheet first (works great on mobile + macOS Sonoma+)
    if (navigator.share) {
      try {
        // Try sharing as a file (CSV) if supported
        const csvBlob = new Blob([buildCSV(rows)], { type: 'text/csv' })
        const file    = new File([csvBlob], `geotag-log-${ts}.csv`, { type: 'text/csv' })
        if (navigator.canShare && navigator.canShare({ files: [file] })) {
          await navigator.share({ title, files: [file] })
        } else {
          await navigator.share({ title, text })
        }
        showToast('✅ Shared successfully')
        return
      } catch (err) {
        if (err.name === 'AbortError') return // user cancelled — no toast
        // fall through to clipboard
      }
    }

    // Fallback: copy CSV text to clipboard
    try {
      await navigator.clipboard.writeText(buildCSV(rows))
      showToast(`📋 ${rows.length} records copied to clipboard as CSV`)
    } catch {
      // Last resort: trigger download
      handleDownloadCSV()
    }
  }

  // 3. Open mailto: link — opens user's email app with log in body
  const handleEmailClient = () => {
    if (rows.length === 0) { showToast('⚠️ No records to export — adjust your filters first.'); return }
    const subject = encodeURIComponent(`GeoTagging Log — ${rows.length} records — ${new Date().toLocaleDateString()}`)
    const body    = encodeURIComponent(buildEmailBody(rows))
    const mailto  = `mailto:${exportEmail}?subject=${subject}&body=${body}`
    if (mailto.length > 8000) {
      showToast(`Log too large for email body — downloading CSV instead.`)
      handleDownloadCSV()
      return
    }
    window.location.href = mailto
  }

  // 4. Copy plain text to clipboard
  const handleCopyClipboard = async () => {
    if (rows.length === 0) { showToast('⚠️ No records to export.'); return }
    try {
      await navigator.clipboard.writeText(buildEmailBody(rows))
      showToast(`📋 ${rows.length} records copied to clipboard`)
    } catch {
      showToast('Clipboard not available — use CSV download instead.')
    }
  }

  return (
    <div className="log-shell">
      {/* Toast notification */}
      {shareToast && (
        <div style={{
          position: 'fixed', top: 20, left: '50%', transform: 'translateX(-50%)',
          background: '#0f172a', color: '#f1f5f9', padding: '10px 20px',
          borderRadius: 10, fontSize: 13, fontWeight: 600, zIndex: 9999,
          boxShadow: '0 8px 32px rgba(0,0,0,0.25)', pointerEvents: 'none',
          animation: 'fadeInDown 0.2s ease',
        }}>
          {shareToast}
        </div>
      )}

      {/* Header */}
      <div className="page-header">
        <div>
          <div className="page-title">Activity Log</div>
          <div className="page-sub">Filter uploads by date, time, zip, status, or note · All times in PST</div>
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
          <span className="log-stat-pill log-stat-rush">{rush} Rush</span>
          <span className="log-stat-pill log-stat-std">{standard} Standard</span>
          <span className="log-stat-pill">{rows.length} Total</span>

          {/* ── Share button (always visible) ── */}
          <button
            className="btn btn-outline"
            style={{ fontSize: 12, padding: '7px 14px', display: 'flex', alignItems: 'center', gap: 6 }}
            onClick={handleShare}
            title="Share log via native share sheet or copy to clipboard"
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/>
              <line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/>
            </svg>
            Share
          </button>

          {/* ── Download CSV button (always visible) ── */}
          <button
            className="btn btn-green"
            style={{ fontSize: 12, padding: '7px 14px', display: 'flex', alignItems: 'center', gap: 6 }}
            onClick={handleDownloadCSV}
            title="Download filtered records as CSV (Excel / Numbers / Google Sheets)"
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
              <polyline points="7 10 12 15 17 10"/>
              <line x1="12" y1="15" x2="12" y2="3"/>
            </svg>
            CSV
          </button>

          {/* ── More export options toggle ── */}
          <button
            className="btn btn-outline"
            style={{ fontSize: 12, padding: '7px 12px' }}
            onClick={() => setShowExport(v => !v)}
            title="More export options (email, clipboard)"
          >
            {showExport ? '✕' : '···'}
          </button>
        </div>
      </div>

      {/* Export panel */}
      {showExport && (
        <div style={{
          padding: '14px 24px',
          background: 'var(--bg-surface, #fff)',
          borderBottom: '1px solid var(--border-c, #e2e8f0)',
          display: 'flex', flexDirection: 'column', gap: 10,
        }}>
          <div style={{ fontSize: 13, fontWeight: 700 }}>
            Export {rows.length} record{rows.length !== 1 ? 's' : ''}
            {rows.length === 0 && <span style={{ color: '#ef4444', fontWeight: 400, marginLeft: 8 }}>— no records match current filters</span>}
          </div>

          {/* Row 1: CSV + Clipboard */}
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button
              className="btn btn-green"
              style={{ fontSize: 12, padding: '8px 16px' }}
              onClick={handleDownloadCSV}
              disabled={rows.length === 0}
            >
              ⬇ Download CSV
            </button>
            <button
              className="btn btn-outline"
              style={{ fontSize: 12, padding: '8px 16px' }}
              onClick={handleCopyClipboard}
              disabled={rows.length === 0}
            >
              📋 Copy to Clipboard
            </button>
          </div>

          {/* Row 2: Email via mailto */}
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <input
              type="email"
              placeholder="recipient@example.com"
              value={exportEmail}
              onChange={e => setExportEmail(e.target.value)}
              style={{ marginBottom: 0, width: 220, fontSize: 12 }}
            />
            <button
              className="btn btn-dark"
              style={{ fontSize: 12, padding: '8px 16px' }}
              onClick={handleEmailClient}
              disabled={rows.length === 0 || !exportEmail.trim()}
            >
              📧 Open in Email App
            </button>
            <span style={{ fontSize: 11, opacity: 0.5 }}>Opens your mail app with log pre-filled</span>
          </div>

          <button
            className="btn btn-outline"
            style={{ fontSize: 11, padding: '5px 10px', alignSelf: 'flex-start' }}
            onClick={() => setShowExport(false)}
          >✕ Close</button>
        </div>
      )}

      {/* Filter bar */}
      <div className="log-filters">
        {/* Date range */}
        <div className="log-filter-group">
          <label>Date From</label>
          <input
            type="date"
            value={date}
            onChange={e => setDate(e.target.value)}
            style={{ marginBottom: 0, width: 150 }}
          />
        </div>

        <div className="log-filter-group">
          <label>Date To</label>
          <input
            type="date"
            value={dateTo}
            onChange={e => setDateTo(e.target.value)}
            style={{ marginBottom: 0, width: 150 }}
          />
        </div>

        {/* Time range */}
        <div className="log-filter-group">
          <label>Time From (PST)</label>
          <input
            type="time"
            value={timeFrom}
            onChange={e => setTimeFrom(e.target.value)}
            style={{ marginBottom: 0, width: 120 }}
          />
        </div>

        <div className="log-filter-group">
          <label>Time To (PST)</label>
          <input
            type="time"
            value={timeTo}
            onChange={e => setTimeTo(e.target.value)}
            style={{ marginBottom: 0, width: 120 }}
          />
        </div>

        <div className="log-filter-group">
          <label>Zip Code</label>
          <input
            type="text"
            placeholder="e.g. 92101"
            value={zip}
            onChange={e => setZip(e.target.value)}
            style={{ marginBottom: 0, width: 110 }}
          />
        </div>

        <div className="log-filter-group">
          <label>Status</label>
          <select
            value={status}
            onChange={e => setStatus(e.target.value)}
            style={{ marginBottom: 0, width: 130 }}
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
          onClick={resetFilters}
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
                <th>Date &amp; Time (PST)</th>
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
                      onError={e => { e.target.src = 'https://via.placeholder.com/48x48/e2e8f0/64748b?text=P' }}
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
                  <td className="log-mono">{toPST(r.timestamp)}</td>
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
