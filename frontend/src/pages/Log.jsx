import React, { useEffect, useState, useCallback, useRef } from 'react'
import { getLog, exportLogEmail } from '../api'

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
  const headers = ['ID', 'Timestamp (PST)', 'Profile(s)', 'Status', 'Address', 'Latitude', 'Longitude', 'Note']
  const escape = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`
  const lines = [
    headers.join(','),
    ...rows.map(r => [
      r.id,
      escape(toPST(r.timestamp)),
      escape((r.profiles?.length > 0 ? r.profiles : [{ name: r.profile_name }]).map(p => p.name).join(' | ')),
      escape(r.service_type),
      escape(r.address || ''),
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
      `Location: ${r.address || `${r.latitude?.toFixed(5)}, ${r.longitude?.toFixed(5)}`}`,
      `Note:     ${r.note || '—'}`,
    ].join('\n')
  }).join('\n\n')
}

export default function Log() {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' }) // YYYY-MM-DD in PST

  const [rows,      setRows]      = useState([])
  const [loading,   setLoading]   = useState(true)
  const [date,      setDate]      = useState('')
  const [dateTo,    setDateTo]    = useState('')
  const [status,    setStatus]    = useState('')
  const [search,    setSearch]    = useState('')
  const [timeFrom,  setTimeFrom]  = useState('')
  const [timeTo,    setTimeTo]    = useState('')
  const [exporting, setExporting] = useState(false)
  const [exportEmail, setExportEmail] = useState('')
  const [showExport,  setShowExport]  = useState(false)
  const [sendingEmail, setSendingEmail] = useState(false)
  const [detailItem,  setDetailItem]  = useState(null)

  const load = useCallback(async () => {
    setLoading(true)
    const params = {}
    if (date)   params.date     = date
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

    // Deduplicate: keep only latest entry per profile name
    const seen = new Set()
    data = data.filter(r => {
      const key = r.profile_name || r.id
      if (seen.has(key)) return false
      seen.add(key)
      return true
    })

    setRows(data)
    setLoading(false)
  }, [date, dateTo, status, search, timeFrom, timeTo])

  useEffect(() => { load() }, [load])

  const rush     = rows.filter(r => r.service_type === 'rush').length
  const standard = rows.filter(r => r.service_type === 'standard').length

  // ── Row selection (for sharing/exporting a chosen subset) ────────────────
  const [selectedIds, setSelectedIds] = useState(() => new Set())
  // Rows used for any export: the selected subset, or all filtered rows.
  const exportRows = selectedIds.size > 0
    ? rows.filter(r => selectedIds.has(r.id))
    : rows
  const allSelected = rows.length > 0 && selectedIds.size === rows.length

  const toggleRow = (id) => {
    setSelectedIds(prev => {
      const next = new Set(prev)
      if (next.has(id)) { next.delete(id) } else { next.add(id) }
      return next
    })
  }
  const toggleSelectAll = () => {
    setSelectedIds(prev =>
      prev.size === rows.length ? new Set() : new Set(rows.map(r => r.id)))
  }
  const clearSelection = () => setSelectedIds(new Set())

  const [shareToast, setShareToast] = useState('')
  const toastTimer = useRef(null)

  const showToast = (msg) => {
    setShareToast(msg)
    clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setShareToast(''), 2800)
  }

  const showDetail = (r) => {
    setDetailItem(r)
  }

  const resetFilters = () => {
    setDate(''); setDateTo(''); setStatus(''); setSearch(''); setTimeFrom(''); setTimeTo('')
  }

  // ── Export handlers ──────────────────────────────────────────────────────

  // 1. Download as CSV (opens in Excel, Numbers, Google Sheets)
  const handleDownloadCSV = () => {
    if (exportRows.length === 0) { showToast('⚠️ No records to export — adjust your filters first.'); return }
    const ts = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' })
    downloadFile(buildCSV(exportRows), `geotag-log-${ts}.csv`, 'text/csv;charset=utf-8;')
    showToast(`✅ Downloaded ${exportRows.length} record${exportRows.length !== 1 ? 's' : ''} as CSV`)
  }

  // 2. Share — tries native share sheet, then clipboard, then CSV download
  const handleShare = async () => {
    if (exportRows.length === 0) { showToast('⚠️ No records to share — adjust your filters first.'); return }

    const ts    = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' })
    const title = `GeoTag Log — ${exportRows.length} records — ${ts}`
    const text  = buildEmailBody(exportRows)
    const csv   = buildCSV(exportRows)

    // Try native share sheet (works on mobile + macOS Safari/Sonoma+)
    if (navigator.share) {
      try {
        const csvBlob = new Blob([csv], { type: 'text/csv' })
        const file    = new File([csvBlob], `geotag-log-${ts}.csv`, { type: 'text/csv' })
        if (navigator.canShare && navigator.canShare({ files: [file] })) {
          await navigator.share({ title, files: [file] })
        } else {
          await navigator.share({ title, text })
        }
        showToast('✅ Shared successfully')
        return
      } catch (err) {
        if (err.name === 'AbortError') return // user cancelled
        // fall through to clipboard
      }
    }

    // Fallback 1: modern clipboard API (requires HTTPS / secure context)
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(csv)
        showToast(`📋 ${exportRows.length} records copied to clipboard as CSV`)
        return
      } catch {
        // fall through
      }
    }

    // Fallback 2: textarea trick — works on http/localhost without permissions
    try {
      const ta = document.createElement('textarea')
      ta.value = csv
      ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0'
      document.body.appendChild(ta)
      ta.focus()
      ta.select()
      const ok = document.execCommand('copy')
      document.body.removeChild(ta)
      if (ok) {
        showToast(`📋 ${exportRows.length} records copied to clipboard`)
        return
      }
    } catch { /* fall through */ }

    // Fallback 3: just download the CSV
    handleDownloadCSV()
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

  // 4. Copy plain text to clipboard (with all fallbacks)
  const handleCopyClipboard = async () => {
    if (exportRows.length === 0) { showToast('⚠️ No records to export.'); return }

    const text = buildEmailBody(exportRows)

    // Modern clipboard API
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text)
        showToast(`📋 ${exportRows.length} records copied to clipboard`)
        return
      } catch { /* fall through */ }
    }

    // textarea fallback — works on http/localhost
    try {
      const ta = document.createElement('textarea')
      ta.value = text
      ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0'
      document.body.appendChild(ta)
      ta.focus()
      ta.select()
      const ok = document.execCommand('copy')
      document.body.removeChild(ta)
      if (ok) {
        showToast(`📋 ${exportRows.length} records copied to clipboard`)
        return
      }
    } catch { /* fall through */ }

    showToast('⚠️ Clipboard not available — use CSV download instead.')
  }

  // 5. Prompts for email then sends via backend
  const handleEmailPrompt = () => {
    if (exportRows.length === 0) {
      showToast('⚠️ No records to export — adjust your filters first.')
      return
    }
    const email = prompt(`Send ${exportRows.length} record${exportRows.length !== 1 ? 's' : ''} by email.\nEnter recipient email:`, exportEmail)
    if (!email || !email.includes('@')) return
    setExportEmail(email)
    handleSendEmailDirect(email)
  }

  const handleSendEmailDirect = async (toEmail) => {
    setSendingEmail(true)
    try {
      const records = exportRows.map(r => ({
        id: r.id,
        timestamp: r.timestamp,
        profile_name: r.profile_name,
        profiles: (r.profiles || []).map(p => ({ id: p.id, name: p.name })),
        service_type: r.service_type,
        address: r.address || '',
        zip_code: r.zip_code || '',
        latitude: r.latitude,
        longitude: r.longitude,
        note: r.note || '',
      }))

      const result = await exportLogEmail(toEmail, records)
      if (result.message && result.message.includes('SMTP not configured')) {
        showToast('📧 SMTP not configured — downloading CSV instead')
        handleDownloadCSV()
      } else {
        showToast(`✅ Email sent to ${toEmail} — ${exportRows.length} records`)
      }
    } catch (err) {
      showToast(`❌ Failed to send: ${err.response?.data?.detail || err.message || 'Network error'}`)
    } finally {
      setSendingEmail(false)
    }
  }

  // 6. Send email via backend SMTP/SendGrid (from export panel)
  const handleSendEmail = () => {
    if (exportRows.length === 0) { showToast('⚠️ No records to export — adjust your filters first.'); return }
    if (!exportEmail || !exportEmail.includes('@')) { showToast('⚠️ Please enter a valid recipient email address.'); return }
    handleSendEmailDirect(exportEmail)
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

      {/* Detail modal */}
      {detailItem && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', zIndex: 9998,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          animation: 'fadeIn 0.15s ease',
        }} onClick={() => setDetailItem(null)}>
          <div style={{
            background: '#fff', borderRadius: 16, maxWidth: 520, width: '100%',
            maxHeight: '85vh', overflow: 'auto', margin: 16, boxShadow: '0 20px 60px rgba(0,0,0,0.2)',
          }} onClick={e => e.stopPropagation()}>
            <div style={{ position: 'relative' }}>
              <img src={detailItem.image_url} alt="" style={{ width: '100%', height: 250, objectFit: 'cover', borderRadius: '16px 16px 0 0' }}
                onError={e => { e.target.src = 'https://via.placeholder.com/520x250/1e293b/6366f1?text=Photo' }} />
              <button onClick={() => setDetailItem(null)}
                style={{ position: 'absolute', top: 12, right: 12, background: 'rgba(0,0,0,0.6)', border: 'none', color: '#fff', borderRadius: '50%', width: 32, height: 32, cursor: 'pointer', fontSize: 16 }}
              >✕</button>
              <div style={{ position: 'absolute', top: 12, left: 12, background: detailItem.service_type === 'rush' ? '#ef4444' : '#10b981', color: '#fff', borderRadius: 8, padding: '4px 10px', fontSize: 12, fontWeight: 700 }}>
                {detailItem.service_type === 'rush' ? '🔴 ASAP' : '🟢 Standard'}
              </div>
            </div>
            <div style={{ padding: 20 }}>
              <div style={{ fontSize: 19, fontWeight: 800, marginBottom: 4 }}>
                {(detailItem.profiles?.length > 0 ? detailItem.profiles : [{ name: detailItem.profile_name }]).map((p, i) => (
                  <span key={i} style={{ marginRight: 8 }}>{p.name}{i < (detailItem.profiles?.length || 1) - 1 ? ',' : ''}</span>
                ))}
              </div>
              <div style={{ fontSize: 13, color: '#64748b', marginBottom: 16 }}>🕐 {toPST(detailItem.timestamp)}</div>
              {detailItem.address && (
                <div style={{ fontSize: 14, marginBottom: 8, display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                  <span style={{ color: '#10b981' }}>📍</span>
                  <span>{detailItem.address}</span>
                </div>
              )}
              <div style={{ fontSize: 12, color: '#94a3b8', fontFamily: 'monospace', marginBottom: 12 }}>
                {detailItem.latitude?.toFixed(6)}, {detailItem.longitude?.toFixed(6)}
              </div>
              {detailItem.note && (
                <div style={{ background: '#f8fafc', borderRadius: 10, padding: '12px 14px', fontSize: 14, color: '#334155' }}>
                  <div style={{ fontWeight: 700, fontSize: 11, color: '#94a3b8', marginBottom: 4 }}>NOTE</div>
                  {detailItem.note}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Header */}
      <div className="page-header">
        <div>
          <div className="page-title">Activity Log</div>
          <div className="page-sub">Filter uploads by date, time, zip, status, or note · All times in PST</div>
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
          <span className="log-stat-pill log-stat-rush">{rush} ASAP</span>
          <span className="log-stat-pill log-stat-std">{standard} Standard</span>
          <span className="log-stat-pill">{rows.length} Total</span>
          {selectedIds.size > 0 && (
            <span
              className="log-stat-pill"
              onClick={clearSelection}
              title="Clear selection"
              style={{ background: '#7C3AED', color: '#fff', borderColor: '#7C3AED', cursor: 'pointer', fontWeight: 700 }}
            >
              {selectedIds.size} selected ✕
            </span>
          )}

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

          {/* ── Email button (always visible) ── */}
          <button
            className="btn btn-green"
            style={{ fontSize: 12, padding: '7px 14px', display: 'flex', alignItems: 'center', gap: 6, background: '#059669' }}
            onClick={handleEmailPrompt}
            title="Email filtered records as CSV"
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <rect x="2" y="4" width="20" height="16" rx="2"/>
              <path d="m22 4-10 8L2 4"/>
            </svg>
            Email
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

          {/* Row 2: Email via backend SendGrid/SMTP */}
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
              onClick={handleSendEmail}
              disabled={rows.length === 0 || !exportEmail.trim() || sendingEmail}
            >
              {sendingEmail ? 'Sending…' : '📧 Send Email'}
            </button>
            <span style={{ fontSize: 11, opacity: 0.5 }}>Sends CSV via server email</span>
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
          <label>Status</label>
          <select
            value={status}
            onChange={e => setStatus(e.target.value)}
            style={{ marginBottom: 0, width: 130 }}
          >
            <option value="">All</option>
            <option value="rush">ASAP</option>
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

      {/* ── Contextual selection action bar ── */}
      {selectedIds.size > 0 && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
          margin: '0 24px 12px', padding: '12px 16px',
          background: 'linear-gradient(90deg, #7C3AED 0%, #6D28D9 100%)',
          borderRadius: 14, color: '#fff',
          boxShadow: '0 8px 24px rgba(124,58,237,0.35)',
          animation: 'fadeInDown 0.2s ease',
        }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            width: 28, height: 28, borderRadius: 8, background: 'rgba(255,255,255,0.2)',
            fontWeight: 800, fontSize: 14,
          }}>{selectedIds.size}</span>
          <span style={{ fontWeight: 700, fontSize: 14 }}>
            {selectedIds.size} record{selectedIds.size !== 1 ? 's' : ''} selected
          </span>
          <div style={{ flex: 1 }} />
          <button onClick={handleShare}
            style={{ background: 'rgba(255,255,255,0.18)', color: '#fff', border: '1px solid rgba(255,255,255,0.3)', borderRadius: 10, padding: '8px 14px', fontSize: 13, fontWeight: 700, cursor: 'pointer' }}>
            ⤴ Share
          </button>
          <button onClick={handleDownloadCSV}
            style={{ background: '#fff', color: '#6D28D9', border: 'none', borderRadius: 10, padding: '8px 14px', fontSize: 13, fontWeight: 700, cursor: 'pointer' }}>
            ⬇ Export CSV
          </button>
          <button onClick={handleEmailPrompt}
            style={{ background: 'rgba(255,255,255,0.18)', color: '#fff', border: '1px solid rgba(255,255,255,0.3)', borderRadius: 10, padding: '8px 14px', fontSize: 13, fontWeight: 700, cursor: 'pointer' }}>
            ✉ Email
          </button>
          <button onClick={clearSelection}
            style={{ background: 'transparent', color: 'rgba(255,255,255,0.85)', border: 'none', borderRadius: 10, padding: '8px 10px', fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>
            ✕ Clear
          </button>
        </div>
      )}

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
                <th style={{ width: 44, textAlign: 'center' }}>
                  <span
                    role="checkbox"
                    aria-checked={allSelected}
                    aria-label="Select all"
                    onClick={toggleSelectAll}
                    style={{
                      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                      width: 22, height: 22, borderRadius: '50%', cursor: 'pointer',
                      background: selectedIds.size > 0 ? '#7C3AED' : '#fff',
                      border: `2px solid ${selectedIds.size > 0 ? '#7C3AED' : '#cbd5e1'}`,
                      color: '#fff', fontSize: 13, fontWeight: 800, lineHeight: 1,
                      transition: 'all .15s ease',
                    }}
                  >{allSelected ? '✓' : selectedIds.size > 0 ? '–' : ''}</span>
                </th>
                <th>Photo</th>
                <th>Profile(s)</th>
                <th>Status</th>
                <th>Date &amp; Time (PST)</th>
                <th>Address</th>
                <th>Note</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => {
                const isSel = selectedIds.has(r.id)
                const sc = r.service_type === 'rush' ? '#ef4444' : '#10b981'
                return (
                <tr key={r.id} className="log-row-clickable" onClick={() => showDetail(r)}
                    style={{ cursor: 'pointer', background: isSel ? 'rgba(124,58,237,0.06)' : undefined }}>
                  <td style={{ textAlign: 'center', borderLeft: `4px solid ${sc}` }} onClick={e => { e.stopPropagation(); toggleRow(r.id) }}>
                    <span
                      role="checkbox"
                      aria-checked={isSel}
                      aria-label="Select row"
                      style={{
                        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                        width: 22, height: 22, borderRadius: '50%', cursor: 'pointer',
                        background: isSel ? '#7C3AED' : '#fff',
                        border: `2px solid ${isSel ? '#7C3AED' : '#cbd5e1'}`,
                        color: '#fff', fontSize: 13, fontWeight: 800, lineHeight: 1,
                        boxShadow: isSel ? '0 2px 6px rgba(124,58,237,0.45)' : 'none',
                        transition: 'all .15s ease',
                      }}
                    >{isSel ? '✓' : ''}</span>
                  </td>
                  <td>
                    <img
                      src={r.image_url}
                      alt=""
                      className="log-thumb"
                      style={{ border: `2px solid ${sc}`, padding: 1, borderRadius: 10 }}
                      onError={e => { e.target.src = 'https://via.placeholder.com/48x48/e2e8f0/64748b?text=P' }}
                    />
                  </td>
                  <td>
                    <div className="log-profiles">
                      {(r.profiles && r.profiles.length > 0 ? r.profiles : [{ name: r.profile_name, service_type: r.service_type }]).map((p, i) => (
                        <span key={i} className="log-profile-chip"
                          style={{ background: '#EDE9FE', color: '#6D28D9', border: '1px solid #DDD6FE', borderRadius: 8, padding: '3px 10px', fontWeight: 600, fontSize: 12 }}>{p.name}</span>
                      ))}
                    </div>
                  </td>
                  <td>
                    <span className={`badge badge-${r.service_type}`}>
                      {r.service_type === 'rush' ? '🔴 ASAP' : '🟢 Standard'}
                    </span>
                  </td>
                  <td className="log-mono">{toPST(r.timestamp)}</td>
                  <td style={{ fontSize: 13 }}>
                    {r.address || <span style={{ opacity: 0.3 }}>—</span>}
                  </td>
                  <td className="log-note">{r.note || <span style={{ opacity: 0.3 }}>—</span>}</td>
                </tr>
              )})}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
