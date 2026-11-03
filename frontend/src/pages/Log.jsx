import React, { useEffect, useState, useCallback, useRef } from 'react'
import { getLog, exportLogEmail, exportExcel, exportJobExcel, getProfilePhotos, getRecipients, addRecipient, deleteRecipient, updatePayRate, updateStatus, editTimestamp } from '../api'

import LogDetailModal from '../components/LogDetailModal'
import { toLocalInput, SERVICE_META, toPST, exportSvcLabel, exportDateTime, exportIdCtrl, exportStreetZip, STATUS_LABEL, jobRecord, currentAgentName, buildCSV, downloadFile, buildEmailBody } from '../components/logExportUtils'

export default function Log() {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' }) // YYYY-MM-DD in PST

  const [rows,      setRows]      = useState([])
  const [loading,   setLoading]   = useState(true)
  const [date,      setDate]      = useState('')
  const [dateTo,    setDateTo]    = useState('')
  const [status,    setStatus]    = useState('')
  const [serviceLevel, setServiceLevel] = useState('')   // F2/F3 category filter
  const [search,    setSearch]    = useState('')
  // F11 — saved recipients
  const [recipients,         setRecipients]         = useState([])
  const [selectedRecipients, setSelectedRecipients] = useState(() => new Set())
  const [newRecipient,       setNewRecipient]       = useState('')
  const [exportingExcel,     setExportingExcel]     = useState(false)
  const [timeFrom,  setTimeFrom]  = useState('')
  const [timeTo,    setTimeTo]    = useState('')
  const [exporting, setExporting] = useState(false)
  const [exportEmail, setExportEmail] = useState('')
  const [showExport,  setShowExport]  = useState(false)
  const [sendingEmail, setSendingEmail] = useState(false)
  const [detailItem,  setDetailItem]  = useState(null)
  // F7/F10 — pay-rate edit + job-status workflow (feeds payouts/earnings)
  const [payInput,     setPayInput]     = useState('')
  const [savingPay,    setSavingPay]    = useState(false)
  const [savingStatus, setSavingStatus] = useState(false)
  // F6 — timestamp edit (within 10-min window of original capture)
  const [editingTs,    setEditingTs]    = useState(false)
  const [tsInput,      setTsInput]      = useState('')
  const [savingTs,     setSavingTs]     = useState(false)
  // Single-job "Service Record" export (mirrors mobile photo-detail export)
  const [jobExporting, setJobExporting] = useState(false)
  const [jobLatestOnly, setJobLatestOnly] = useState(false)

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

    // F2/F3 — client-side service-level (category) filter
    if (serviceLevel) {
      data = data.filter(r => (r.category || 'standard') === serviceLevel)
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
  }, [date, dateTo, status, serviceLevel, search, timeFrom, timeTo])

  useEffect(() => { load() }, [load])

  // F11 — load saved recipients once
  useEffect(() => {
    getRecipients().then(setRecipients).catch(() => {})
  }, [])

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
    setPayInput(r.pay_rate != null ? String(r.pay_rate) : '')
    setEditingTs(false)
    setTsInput(toLocalInput(r.timestamp))
  }

  // Reflect an edit in both the open modal and the table row, without a full reload
  const applyItemUpdate = (id, patch) => {
    setRows(prev => prev.map(r => (r.id === id ? { ...r, ...patch } : r)))
    setDetailItem(prev => (prev && prev.id === id ? { ...prev, ...patch } : prev))
  }

  // F7 — set/edit the per-job pay rate (whole dollars)
  const handleSavePayRate = async () => {
    if (!detailItem) return
    const val = payInput.trim()
    if (val === '' || isNaN(Number(val)) || Number(val) < 0) {
      showToast('⚠️ Enter a valid dollar amount'); return
    }
    setSavingPay(true)
    try {
      const res = await updatePayRate(detailItem.id, Math.round(Number(val)))
      applyItemUpdate(detailItem.id, { pay_rate: res.pay_rate })
      showToast(`✅ Pay rate set to $${res.pay_rate}`)
    } catch (err) {
      showToast(`❌ ${err.response?.data?.detail || 'Could not save pay rate'}`)
    } finally { setSavingPay(false) }
  }

  // F10 — job status workflow; "completed" is what makes pay count toward payouts
  const handleSetStatus = async (newStatus) => {
    if (!detailItem) return
    setSavingStatus(true)
    try {
      await updateStatus(detailItem.id, newStatus)
      applyItemUpdate(detailItem.id, {
        status: newStatus,
        completed_at: newStatus === 'completed'
          ? (detailItem.completed_at || new Date().toISOString())
          : detailItem.completed_at,
      })
      showToast(newStatus === 'completed'
        ? '✅ Job marked complete — added to payouts'
        : `Status set to ${newStatus}`)
    } catch (err) {
      showToast(`❌ ${err.response?.data?.detail || 'Could not update status'}`)
    } finally { setSavingStatus(false) }
  }

  // F6 — is the photo still inside the 10-minute timestamp-edit window?
  const tsWithinWindow = (item) => {
    if (!item) return false
    // Window is anchored to pin-CREATION time (created_at), not capture time
    const anchor = new Date(item.created_at || item.original_timestamp || item.timestamp)
    if (isNaN(anchor)) return false
    return (Date.now() - anchor.getTime()) <= 10 * 60 * 1000
  }

  const handleSaveTimestamp = async () => {
    if (!detailItem || !tsInput) return
    setSavingTs(true)
    try {
      const iso = new Date(tsInput).toISOString()
      const res = await editTimestamp(detailItem.id, iso)
      applyItemUpdate(detailItem.id, { timestamp: res.timestamp, edited_timestamp: res.timestamp })
      setEditingTs(false)
      showToast('✅ Timestamp updated')
    } catch (err) {
      const msg = err.response?.status === 423
        ? '🔒 Edit window (10 min) has passed — timestamp locked'
        : (err.response?.data?.detail || 'Could not update timestamp')
      showToast(`❌ ${msg}`)
    } finally { setSavingTs(false) }
  }

  const resetFilters = () => {
    setDate(''); setDateTo(''); setStatus(''); setServiceLevel(''); setSearch(''); setTimeFrom(''); setTimeTo('')
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

  // ── F11: Excel export + saved recipients ────────────────────────────────
  // Manual selection → one row per selected profile, with that profile's most
  // recent photo embedded (watermarked). Full list → one row per profile, no
  // photo. Both share the same profile-centric column set.
  const buildProfileRecords = (includePhoto) => {
    // Group the export rows by profile, keeping each profile's latest photo.
    const byProfile = new Map()
    for (const r of exportRows) {
      const pid  = r.profile_id ?? r.profiles?.[0]?.id
      const key  = pid ?? `row-${r.id}`
      const when = new Date(r.taken_at || r.timestamp || 0).getTime()
      const cur  = byProfile.get(key)
      if (!cur || when > cur._when) byProfile.set(key, { ...r, _pid: pid, _when: when })
    }
    return [...byProfile.values()].map(r => {
      const name = r.profiles?.[0]?.name ?? r.profile_name ?? ''
      const rec = {
        file_number:    r._pid ?? '',
        name,
        date_time:      exportDateTime(r.taken_at || r.timestamp),
        priority_level: SERVICE_META[r.category]?.label || exportSvcLabel(r.service_type),
        address:        exportStreetZip(r),
        notes:          r.note || '',
      }
      if (includePhoto) rec.photo_id = r.id   // backend embeds this photo, watermarked
      return rec
    })
  }

  const handleExportExcel = async () => {
    if (exportRows.length === 0) { showToast('⚠️ No records to export — adjust your filters first.'); return }
    const targets = recipients.filter(r => selectedRecipients.has(r.id)).map(r => r.email)
    if (targets.length === 0) { showToast('⚠️ Select at least one saved recipient.'); return }
    const manual = selectedIds.size > 0   // manual selection embeds latest photo per profile
    setExportingExcel(true)
    try {
      const result = await exportExcel(targets, buildProfileRecords(manual), manual)
      if (result.file_base64) {
        // email not configured — download the file the server returned
        const bin = atob(result.file_base64)
        const bytes = new Uint8Array(bin.length)
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
        downloadFile(bytes, result.filename || 'log_export.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        showToast('📥 Email not configured — Excel downloaded')
      } else {
        showToast(`✅ Excel sent to ${targets.length} recipient${targets.length !== 1 ? 's' : ''}`)
      }
    } catch (err) {
      showToast(`❌ Export failed: ${err.response?.data?.detail || err.message}`)
    } finally {
      setExportingExcel(false)
    }
  }

  const handleAddRecipient = async () => {
    const email = newRecipient.trim()
    if (!email.includes('@')) { showToast('⚠️ Enter a valid email.'); return }
    try {
      const r = await addRecipient({ email })
      setRecipients(prev => [...prev, r])
      setNewRecipient('')
      showToast('✅ Recipient saved')
    } catch (err) { showToast(`❌ ${err.response?.data?.detail || 'Could not save'}`) }
  }

  const handleDeleteRecipient = async (id) => {
    await deleteRecipient(id).catch(() => {})
    setRecipients(prev => prev.filter(r => r.id !== id))
    setSelectedRecipients(prev => { const n = new Set(prev); n.delete(id); return n })
  }

  const toggleRecipient = (id) => setSelectedRecipients(prev => {
    const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n
  })

  // Download an .xlsx returned by the server as base64
  const downloadXlsxB64 = (b64, filename) => {
    const bin = atob(b64)
    const bytes = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
    downloadFile(bytes, filename, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
  }

  // Single-job Service Record export (mode: 'email' | 'download').
  // A "job" = every attempt (photo) for the same profile, newest-first.
  const handleExportServiceRecord = async (mode) => {
    if (!detailItem || jobExporting) return
    if (mode === 'email') {
      const targets = recipients.filter(r => selectedRecipients.has(r.id)).map(r => r.email)
      if (targets.length === 0) { showToast('⚠️ Select at least one saved recipient.'); return }
    }
    setJobExporting(true)
    try {
      // Gather all attempts for this job. Fall back to the single open record.
      let attempts = [detailItem]
      if (detailItem.profile_id != null) {
        try {
          const photos = await getProfilePhotos(detailItem.profile_id)
          if (photos && photos.length) attempts = photos
        } catch { /* offline / no extra attempts — use the open record */ }
      }
      attempts = [...attempts].sort((a, b) =>
        String(b.taken_at || b.timestamp || '').localeCompare(String(a.taken_at || a.timestamp || '')))
      const selected = jobLatestOnly ? attempts.slice(0, 1) : attempts
      const total = attempts.length
      const agent = currentAgentName()

      const records = selected.map(p => jobRecord(p, total - attempts.indexOf(p), agent))

      const safe = (detailItem.profile_name || 'job').replace(/[^A-Za-z0-9_-]+/g, '_')
      const baseName = `service-record-${safe}`

      if (mode === 'email') {
        const targets = recipients.filter(r => selectedRecipients.has(r.id)).map(r => r.email)
        // Attach the watermarked photos (stored image is already stamped at capture)
        const attachments = []
        for (const p of selected) {
          const a = await photoAttachment(p, total - attempts.indexOf(p))
          if (a) attachments.push(a)
        }
        const res = await exportJobExcel({
          recipients: targets, records, attachments,
          subject: `Service Record — ${detailItem.profile_name || ''}`,
          body: `Service record for ${detailItem.profile_name || 'this job'} attached.`,
          base_name: baseName,
        })
        if (res.file_base64) {
          downloadXlsxB64(res.file_base64, res.filename || `${baseName}.xlsx`)
          showToast('📥 Email not set up on the server — Service Record downloaded')
        } else {
          showToast(`✅ Service record emailed to ${targets.length} recipient${targets.length !== 1 ? 's' : ''}`)
        }
      } else {
        const res = await exportJobExcel({ recipients: [], records, base_name: baseName })
        if (res.file_base64) {
          downloadXlsxB64(res.file_base64, res.filename || `${baseName}.xlsx`)
          showToast(`✅ Service Record downloaded — ${records.length} attempt${records.length !== 1 ? 's' : ''}`)
        }
      }
    } catch (err) {
      showToast(`❌ Export failed: ${err.response?.data?.detail || err.message || 'Network error'}`)
    } finally {
      setJobExporting(false)
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

      <LogDetailModal
        detailItem={detailItem}
        setDetailItem={setDetailItem}
        editingTs={editingTs}
        setEditingTs={setEditingTs}
        tsInput={tsInput}
        setTsInput={setTsInput}
        tsWithinWindow={tsWithinWindow}
        handleSaveTimestamp={handleSaveTimestamp}
        savingTs={savingTs}
        handleSetStatus={handleSetStatus}
        savingStatus={savingStatus}
        payInput={payInput}
        setPayInput={setPayInput}
        handleSavePayRate={handleSavePayRate}
        savingPay={savingPay}
        jobLatestOnly={jobLatestOnly}
        setJobLatestOnly={setJobLatestOnly}
        recipients={recipients}
        selectedRecipients={selectedRecipients}
        toggleRecipient={toggleRecipient}
        newRecipient={newRecipient}
        setNewRecipient={setNewRecipient}
        handleAddRecipient={handleAddRecipient}
        handleExportServiceRecord={handleExportServiceRecord}
        jobExporting={jobExporting}
      />

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

          {/* ── Excel export (F11) ── */}
          <button
            className="btn btn-dark"
            style={{ fontSize: 12, padding: '7px 14px', display: 'flex', alignItems: 'center', gap: 6, background: '#16a34a' }}
            onClick={() => setShowExport(true)}
            title="Export to Excel and send to saved recipients"
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18M3 9h18"/>
            </svg>
            Excel
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

          {/* ── F11: Excel export with saved recipients ── */}
          <div style={{ borderTop: '1px dashed var(--border-c,#e2e8f0)', paddingTop: 12, marginTop: 4 }}>
            <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 8 }}>📊 Excel Export → Saved Recipients</div>

            {/* recipient chips */}
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 10 }}>
              {recipients.length === 0 && <span style={{ fontSize: 12, opacity: 0.5 }}>No saved recipients yet — add one below.</span>}
              {recipients.map(r => {
                const sel = selectedRecipients.has(r.id)
                return (
                  <span key={r.id} onClick={() => toggleRecipient(r.id)}
                    style={{
                      display: 'inline-flex', alignItems: 'center', gap: 6, cursor: 'pointer',
                      fontSize: 12, fontWeight: 600, padding: '5px 10px', borderRadius: 20,
                      border: '1px solid ' + (sel ? '#16a34a' : '#cbd5e1'),
                      background: sel ? '#16a34a' : 'transparent', color: sel ? '#fff' : '#64748b',
                    }}>
                    {sel ? '✓ ' : ''}{r.label || r.email}
                    <span onClick={e => { e.stopPropagation(); handleDeleteRecipient(r.id) }}
                      style={{ opacity: 0.6, fontWeight: 800 }} title="Delete">×</span>
                  </span>
                )
              })}
            </div>

            <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
              <input type="email" placeholder="add@recipient.com (max 10)" value={newRecipient}
                onChange={e => setNewRecipient(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleAddRecipient()}
                style={{ marginBottom: 0, width: 220, fontSize: 12 }} />
              <button className="btn btn-outline" style={{ fontSize: 12, padding: '8px 14px' }}
                onClick={handleAddRecipient}>+ Add</button>
              <button className="btn btn-green" style={{ fontSize: 12, padding: '8px 16px' }}
                onClick={handleExportExcel}
                disabled={exportRows.length === 0 || selectedRecipients.size === 0 || exportingExcel}>
                {exportingExcel ? 'Sending…' : 'Send'}
              </button>
            </div>
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

        {/* F2/F3 — Service level filter */}
        <div className="log-filter-group">
          <label>Service Level</label>
          <select
            value={serviceLevel}
            onChange={e => setServiceLevel(e.target.value)}
            style={{ marginBottom: 0, width: 130 }}
          >
            <option value="">All</option>
            <option value="asap">ASAP</option>
            <option value="next_day">Next Day</option>
            <option value="standard">Standard</option>
            <option value="special">Special / S.O.</option>
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
