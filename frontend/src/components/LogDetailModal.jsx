import React from 'react'
import { toLocalInput, SERVICE_META, toPST } from './logExportUtils'

export default function LogDetailModal({
  detailItem,
  setDetailItem,
  editingTs,
  setEditingTs,
  tsInput,
  setTsInput,
  tsWithinWindow,
  handleSaveTimestamp,
  savingTs,
  handleSetStatus,
  savingStatus,
  payInput,
  setPayInput,
  handleSavePayRate,
  savingPay,
  jobLatestOnly,
  setJobLatestOnly,
  recipients,
  selectedRecipients,
  toggleRecipient,
  newRecipient,
  setNewRecipient,
  handleAddRecipient,
  handleExportServiceRecord,
  jobExporting,
}) {
  if (!detailItem) return null
  return (
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
              {/* F6 — capture timestamp + 10-min edit window */}
              <div style={{ marginBottom: 12 }}>
                {!editingTs ? (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <span style={{ fontSize: 13, color: '#64748b' }}>🕐 {toPST(detailItem.timestamp)}</span>
                    {detailItem.edited_timestamp && (
                      <span style={{ fontSize: 10, fontWeight: 700, color: '#7C3AED', background: '#ede9fe', borderRadius: 6, padding: '2px 6px' }}>edited</span>
                    )}
                    {tsWithinWindow(detailItem) ? (
                      <button onClick={() => { setTsInput(toLocalInput(detailItem.timestamp)); setEditingTs(true) }}
                        className="btn btn-outline" style={{ fontSize: 11, padding: '4px 10px' }}>
                        ✏️ Edit time
                      </button>
                    ) : (
                      <span style={{ fontSize: 11, color: '#94a3b8' }}>🔒 locked</span>
                    )}
                  </div>
                ) : (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <input type="datetime-local" value={tsInput}
                      onChange={e => setTsInput(e.target.value)}
                      style={{ marginBottom: 0, fontSize: 13, padding: '6px 8px' }} />
                    <button onClick={handleSaveTimestamp} disabled={savingTs}
                      className="btn btn-dark" style={{ fontSize: 12, padding: '6px 12px' }}>
                      {savingTs ? 'Saving…' : 'Save'}
                    </button>
                    <button onClick={() => setEditingTs(false)}
                      className="btn btn-outline" style={{ fontSize: 12, padding: '6px 12px' }}>
                      Cancel
                    </button>
                  </div>
                )}
                <div style={{ fontSize: 10.5, color: '#94a3b8', marginTop: 4 }}>
                  Capture time (from photo) · editable within 10 min of creation
                </div>
              </div>
              {/* F2/F4 service level */}
              <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
                {(() => { const m = SERVICE_META[detailItem.category || 'standard'] || SERVICE_META.standard
                  return <span style={{ fontSize: 12, fontWeight: 700, color: '#fff', background: m.color, borderRadius: 8, padding: '4px 10px' }}>{m.label}</span> })()}
              </div>

              {/* F7/F10 — Payout & job-status controls (feeds Earnings/Payouts) */}
              <div style={{ border: '1px solid #e2e8f0', borderRadius: 12, padding: 14, marginBottom: 16, background: '#fbfcfe' }}>
                <div style={{ fontWeight: 800, fontSize: 11, color: '#94a3b8', letterSpacing: '0.05em', marginBottom: 10 }}>PAYOUT &amp; STATUS</div>

                {/* Status row */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12, flexWrap: 'wrap' }}>
                  <span style={{ fontSize: 13, color: '#64748b' }}>Status</span>
                  {(() => {
                    const st = detailItem.status || 'open'
                    const meta = {
                      open:      ['Open',      '#d97706', '#fffbeb'],
                      completed: ['Completed', '#16a34a', '#dcfce7'],
                      archived:  ['Archived',  '#64748b', '#f1f5f9'],
                    }[st] || ['Open', '#d97706', '#fffbeb']
                    return <span style={{ fontSize: 12, fontWeight: 700, color: meta[1], background: meta[2], border: `1px solid ${meta[1]}33`, borderRadius: 8, padding: '4px 10px' }}>{meta[0]}</span>
                  })()}
                  {detailItem.status === 'completed' ? (
                    <button onClick={() => handleSetStatus('open')} disabled={savingStatus}
                      className="btn btn-outline" style={{ marginLeft: 'auto', fontSize: 12, padding: '7px 14px' }}>
                      {savingStatus ? 'Saving…' : '↩ Reopen'}
                    </button>
                  ) : (
                    <button onClick={() => handleSetStatus('completed')} disabled={savingStatus}
                      className="btn btn-green" style={{ marginLeft: 'auto', fontSize: 12, padding: '7px 14px' }}>
                      {savingStatus ? 'Saving…' : '✓ Mark Complete'}
                    </button>
                  )}
                </div>

                {/* Pay-rate row */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                  <span style={{ fontSize: 13, color: '#64748b' }}>Pay rate&nbsp;($)</span>
                  <input type="number" min="0" step="1" value={payInput}
                    onChange={e => setPayInput(e.target.value)}
                    onKeyDown={e => e.key === 'Enter' && handleSavePayRate()}
                    placeholder="0"
                    style={{ width: 110, marginBottom: 0, fontSize: 13 }} />
                  <button onClick={handleSavePayRate} disabled={savingPay}
                    className="btn btn-dark" style={{ fontSize: 12, padding: '7px 14px' }}>
                    {savingPay ? 'Saving…' : 'Save'}
                  </button>
                </div>

                {detailItem.status !== 'completed' && (
                  <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 8 }}>
                    Set a pay rate, then mark the job complete for it to count toward payouts &amp; earnings.
                  </div>
                )}
              </div>
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

              {/* ── Single-job Service Record export (detailed Excel + photos) ── */}
              <div style={{ border: '1px solid #e2e8f0', borderRadius: 12, padding: 14, marginTop: 16, background: '#fbfcfe' }}>
                <div style={{ fontWeight: 800, fontSize: 11, color: '#94a3b8', letterSpacing: '0.05em', marginBottom: 10 }}>📄 SERVICE RECORD</div>

                <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: '#475569', marginBottom: 10, cursor: 'pointer' }}>
                  <input type="checkbox" checked={jobLatestOnly} onChange={e => setJobLatestOnly(e.target.checked)} style={{ marginBottom: 0, width: 'auto' }} />
                  Latest attempt only <span style={{ fontSize: 11, color: '#94a3b8' }}>(otherwise every attempt for this profile)</span>
                </label>

                {/* Recipient chips (shared with the Excel export panel) */}
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 8 }}>
                  {recipients.length === 0 && <span style={{ fontSize: 12, opacity: 0.5 }}>No saved recipients — add one below or just download.</span>}
                  {recipients.map(r => {
                    const sel = selectedRecipients.has(r.id)
                    return (
                      <span key={r.id} onClick={() => toggleRecipient(r.id)}
                        style={{
                          display: 'inline-flex', alignItems: 'center', gap: 6, cursor: 'pointer',
                          fontSize: 12, fontWeight: 600, padding: '4px 9px', borderRadius: 20,
                          border: '1px solid ' + (sel ? '#16a34a' : '#cbd5e1'),
                          background: sel ? '#16a34a' : 'transparent', color: sel ? '#fff' : '#64748b',
                        }}>
                        {sel ? '✓ ' : ''}{r.label || r.email}
                      </span>
                    )
                  })}
                </div>

                <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', marginBottom: 10 }}>
                  <input type="email" placeholder="add@recipient.com" value={newRecipient}
                    onChange={e => setNewRecipient(e.target.value)}
                    onKeyDown={e => e.key === 'Enter' && handleAddRecipient()}
                    style={{ marginBottom: 0, width: 190, fontSize: 12 }} />
                  <button className="btn btn-outline" style={{ fontSize: 12, padding: '7px 12px' }}
                    onClick={handleAddRecipient}>+ Add</button>
                </div>

                <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                  <button className="btn btn-green" style={{ fontSize: 12, padding: '8px 14px' }}
                    onClick={() => handleExportServiceRecord('email')}
                    disabled={jobExporting || selectedRecipients.size === 0}>
                    {jobExporting ? 'Working…' : '✉ Email Service Record'}
                  </button>
                  <button className="btn btn-dark" style={{ fontSize: 12, padding: '8px 14px' }}
                    onClick={() => handleExportServiceRecord('download')}
                    disabled={jobExporting}>
                    {jobExporting ? 'Working…' : '⬇ Download .xlsx'}
                  </button>
                </div>
                <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 8 }}>
                  Detailed sheet (one row per attempt) with Lat/Long, status &amp; agent. Email also attaches the photo(s).
                </div>
              </div>
            </div>
          </div>
        </div>
  )
}
