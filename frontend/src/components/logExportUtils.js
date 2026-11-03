// Build a <input type="datetime-local"> value (YYYY-MM-DDTHH:MM) from an ISO string
export function toLocalInput(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d)) return ''
  const pad = n => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export const SERVICE_META = {
  asap:     { label: 'ASAP',     color: '#DC2626' },
  next_day: { label: 'Next Day', color: '#CA8A04' },
  standard: { label: 'Standard', color: '#059669' },
  special:  { label: 'Special',  color: '#EA580C' },
}

// PST formatter
export function toPST(ts) {
  if (!ts) return '—'
  return new Date(ts).toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    month: 'short', day: 'numeric', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }) + ' PST'
}

// Shared export helpers — keep in sync with mobile and backend
export function exportSvcLabel(t) {
  switch ((t || '').toLowerCase()) {
    case 'rush': case 'asap': return 'ASAP'
    case 'airport':           return 'Airport'
    default:                  return 'Standard'
  }
}
export function exportDateTime(ts) {
  if (!ts) return ''
  const d = new Date(ts)
  if (isNaN(d)) return ''
  const pad = n => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}
export function exportIdCtrl(r) {
  const pid  = r.profile_id ?? ''
  const name = (r.profiles?.length > 0 ? r.profiles[0].name : r.profile_name) ?? ''
  return pid && name ? `${pid} / ${name}` : String(pid || name || '')
}
// Full location for email / watermarks: street, city, state, ZIP.
export function exportStreetZip(r) {
  let full = (r.address || '').trim().replace(/\s+/g, ' ')
  let zip = (r.zip_code || '').trim()
  if (!zip) {
    const m = full.match(/\b\d{5}(?:-\d{4})?\b/)
    zip = m ? m[0] : ''
  }
  if (!full) return zip
  if (zip && !new RegExp('\\b' + zip.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b').test(full)) {
    return `${full}, ${zip}`
  }
  return full
}

export const STATUS_LABEL = { open: 'Open', completed: 'Completed', archived: 'Archived' }

// Build one Service-Record row for an attempt — matches mobile _jobRecord and
// the backend _EXPORT_COLUMNS_JOB schema (8 columns). attemptNo: #1 = earliest.
export function jobRecord(p, attemptNo, agentName) {
  let address = p.address || ''
  const zip = p.zip_code || ''
  if (!address) address = zip
  else if (zip && !address.includes(zip)) address = `${address}, ${zip}`
  const note = (p.note || '').trim()
  const svc = SERVICE_META[p.category]?.label || exportSvcLabel(p.service_type)
  const lat = Number(p.latitude), lng = Number(p.longitude)
  return {
    id_ctrl:         exportIdCtrl(p),
    date_time:       exportDateTime(p.taken_at || p.timestamp),
    service_ordered: svc,
    address,
    coordinates:     `${isNaN(lat) ? '' : lat.toFixed(6)}, ${isNaN(lng) ? '' : lng.toFixed(6)}`,
    job_status:      STATUS_LABEL[p.status || 'open'] || 'Open',
    agent:           agentName,
    detailed_notes:  note || `Attempt #${attemptNo}`,
  }
}

// Logged-in agent's display name (local-part of email), for the Agent column
export function currentAgentName() {
  try {
    const u = JSON.parse(localStorage.getItem('geo_user')) || {}
    const e = u.email || ''
    return e.includes('@') ? e.split('@')[0] : (e || u.name || '')
  } catch { return '' }
}

// Fetch a photo and return { filename, content_b64, mimetype } for emailing
async function photoAttachment(p, attemptNo) {
  try {
    const res  = await fetch(p.image_url)
    const blob = await res.blob()
    const b64  = await new Promise((resolve, reject) => {
      const fr = new FileReader()
      fr.onload  = () => resolve(String(fr.result).split(',')[1])
      fr.onerror = reject
      fr.readAsDataURL(blob)
    })
    return { filename: `attempt_${attemptNo}_${p.id}.jpg`, content_b64: b64, mimetype: blob.type || 'image/jpeg' }
  } catch { return null }
}

// Build CSV string from rows — canonical 5-column format
export function buildCSV(rows) {
  const headers = ['ID & Cntrl #', 'Date & Time', 'Service Ordered', 'Address', 'Detailed Notes']
  const escape  = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`
  const lines = [
    headers.join(','),
    ...rows.map(r => [
      escape(exportIdCtrl(r)),
      escape(exportDateTime(r.timestamp)),
      escape(exportSvcLabel(r.service_type)),
      escape(r.address || r.zip_code || ''),
      escape(r.note || ''),
    ].join(','))
  ]
  return lines.join('\n')
}

// Download a string as a file
export function downloadFile(content, filename, mime) {
  const blob = new Blob([content], { type: mime })
  const url  = URL.createObjectURL(blob)
  const a    = document.createElement('a')
  a.href = url; a.download = filename; a.click()
  URL.revokeObjectURL(url)
}

// Build plain-text email body for mailto
export function buildEmailBody(rows) {
  if (rows.length === 0) return 'No records found for the selected filters.'
  const agent = currentAgentName()
  const body = rows.map((r, i) => {
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
  // Wrap the records in a professional greeting + sign-off (from/regards).
  const intro = `Hello,\n\nPlease find the GeoTagging CRM activity log you requested below, containing ${rows.length} record${rows.length !== 1 ? 's' : ''}. All times are shown in PST.`
  const outro = `If you have any questions or need anything further, feel free to reply to this email.\n\nBest regards,\n${agent || 'The GeoTagging CRM Team'}`
  return `${intro}\n\n${body}\n\n${outro}`
}

