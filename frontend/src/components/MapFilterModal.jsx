import React, { useState } from 'react'

// Priority levels — kept in sync with Dashboard pills / Log SERVICE_META.
const CATEGORIES = [
  { value: 'asap',     label: 'ASAP',     color: '#DC2626' },
  { value: 'next_day', label: 'Next Day', color: '#CA8A04' },
  { value: 'standard', label: 'Standard', color: '#059669' },
  { value: 'special',  label: 'Special',  color: '#EA580C' },
]
const ALL_LEVELS = CATEGORIES.map(c => c.value)

// Reverse-geocode a coordinate to its ZIP via Nominatim (same source the
// upload flow uses). Returns '' when it can't be resolved.
async function zipForLocation(lat, lng) {
  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1&_t=${Date.now()}`,
      { headers: { 'Accept-Language': 'en' } }
    )
    const data = await res.json()
    return data?.address?.postcode || ''
  } catch { return '' }
}

/**
 * Map pin-filter popup.
 *
 * Distance: EITHER a radius slider (0–100 mi from current location) OR a ZIP
 * text field / "My zip". Only one applies at a time — whichever UI element was
 * touched most recently wins (`distanceMode`).
 *
 * Priority level: tappable bubbles that OR together, plus Select all / Clear.
 */
export default function MapFilterModal({
  onClose, geo, photos,
  svcLevels, setSvcLevels,
  distanceMi, setDistanceMi,
  zipFilter, setZipFilter,
  distanceMode, setDistanceMode,
  distanceMiles,
}) {
  const [zipBusy, setZipBusy] = useState(false)
  const hasLocation = !!geo?.location

  // Live count of pins that pass the current distance/zip filter (service
  // level excluded, so the number reflects just this section).
  const geoed = photos.filter(p => p.latitude != null && p.longitude != null)
  const withinDistance = hasLocation
    ? geoed.filter(p => distanceMiles(geo.location.lat, geo.location.lng, p.latitude, p.longitude) <= distanceMi).length
    : 0
  const inZip = (() => {
    const z = String(zipFilter || '').trim()
    if (!z) return photos.length
    return photos.filter(p => {
      const pz = (p.zip_code || '').trim()
      return pz ? pz === z : (p.address || '').includes(z)
    }).length
  })()

  const onSlider = (v) => { setDistanceMi(Number(v)); setDistanceMode('distance') }
  const onZipText = (v) => { setZipFilter(v); setDistanceMode('zip') }
  const useMyZip = async () => {
    if (!hasLocation || zipBusy) return
    setZipBusy(true)
    const z = await zipForLocation(geo.location.lat, geo.location.lng)
    setZipBusy(false)
    if (z) { setZipFilter(z); setDistanceMode('zip') }
  }
  const clearDistance = () => { setDistanceMode(null); setZipFilter('') }

  const toggleLevel = (k) => setSvcLevels(prev => {
    const next = new Set(prev)
    next.has(k) ? next.delete(k) : next.add(k)
    return next
  })
  const selectAll = () => setSvcLevels(new Set(ALL_LEVELS))
  const clearLevels = () => setSvcLevels(new Set())

  const bubble = (label, active, color, onClick, key) => (
    <button key={key} type="button" onClick={onClick}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6, cursor: 'pointer',
        fontSize: 12.5, fontWeight: 700, padding: '7px 14px', borderRadius: 99,
        border: '1px solid ' + (active ? (color || '#7C3AED') : 'rgba(0,0,0,0.14)'),
        background: active ? (color || '#7C3AED') : 'transparent',
        color: active ? '#fff' : '#64748b', transition: 'all .15s ease',
      }}>
      {color && <span style={{ width: 7, height: 7, borderRadius: '50%', background: active ? '#fff' : color }} />}
      {label}
    </button>
  )

  const sectionTitle = (t) => (
    <div style={{ fontSize: 13, fontWeight: 800, color: '#0f172a', marginBottom: 10, letterSpacing: '-0.01em' }}>{t}</div>
  )

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" style={{ maxWidth: 460 }} onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <div>
            <div className="modal-title">Filter pins</div>
            <div className="modal-sub">Distance & priority level</div>
          </div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div style={{ padding: '18px 20px', display: 'flex', flexDirection: 'column', gap: 22 }}>

          {/* ── Distance ── */}
          <div>
            {sectionTitle('Distance')}

            {/* Radius slider */}
            <div style={{ opacity: hasLocation ? 1 : 0.5 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
                <label style={{ fontSize: 12.5, fontWeight: 600, color: distanceMode === 'distance' ? '#7C3AED' : '#64748b' }}>
                  Within {distanceMi} mile{distanceMi !== 1 ? 's' : ''} of me
                </label>
                {distanceMode === 'distance' && hasLocation && (
                  <span style={{ fontSize: 11, fontWeight: 700, color: '#7C3AED' }}>{withinDistance} pin{withinDistance !== 1 ? 's' : ''}</span>
                )}
              </div>
              <input
                type="range" min="0" max="100" step="1"
                value={distanceMi}
                disabled={!hasLocation}
                onChange={e => onSlider(e.target.value)}
                style={{ width: '100%', accentColor: '#7C3AED', cursor: hasLocation ? 'pointer' : 'not-allowed' }}
              />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10.5, color: '#94a3b8', marginTop: 2 }}>
                <span>0 mi</span><span>100 mi</span>
              </div>
              {!hasLocation && (
                <div style={{ fontSize: 11.5, color: '#ef4444', marginTop: 6 }}>
                  Current location unavailable — enable GPS to filter by distance.
                </div>
              )}
            </div>

            <div style={{ textAlign: 'center', fontSize: 11, fontWeight: 700, color: '#cbd5e1', margin: '12px 0 10px' }}>— or —</div>

            {/* ZIP code */}
            <label style={{ fontSize: 12.5, fontWeight: 600, color: distanceMode === 'zip' ? '#7C3AED' : '#64748b' }}>ZIP code</label>
            <div style={{ display: 'flex', gap: 8, marginTop: 6 }}>
              <input
                type="text" inputMode="numeric" placeholder="e.g. 92101"
                value={zipFilter}
                onChange={e => onZipText(e.target.value.replace(/[^0-9-]/g, ''))}
                style={{
                  flex: 1, padding: '9px 12px', borderRadius: 9, fontSize: 13.5,
                  border: '1px solid ' + (distanceMode === 'zip' ? '#7C3AED' : 'rgba(0,0,0,0.14)'),
                  outline: 'none', background: 'rgba(0,0,0,0.03)',
                }}
              />
              <button type="button" onClick={useMyZip} disabled={!hasLocation || zipBusy}
                title={hasLocation ? 'Use my current ZIP' : 'Current location unavailable'}
                style={{
                  padding: '9px 14px', borderRadius: 9, fontSize: 12.5, fontWeight: 700,
                  border: '1px solid rgba(124,58,237,0.35)', background: 'rgba(124,58,237,0.08)',
                  color: '#7C3AED', cursor: (hasLocation && !zipBusy) ? 'pointer' : 'not-allowed',
                  whiteSpace: 'nowrap',
                }}>
                {zipBusy ? '…' : '📍 My zip'}
              </button>
            </div>
            {distanceMode === 'zip' && zipFilter && (
              <div style={{ fontSize: 11, color: '#7C3AED', fontWeight: 700, marginTop: 6 }}>{inZip} pin{inZip !== 1 ? 's' : ''} in {zipFilter}</div>
            )}

            {distanceMode && (
              <button type="button" onClick={clearDistance}
                style={{ marginTop: 10, fontSize: 12, fontWeight: 600, padding: '5px 10px', borderRadius: 99,
                  border: 'none', background: 'transparent', color: '#94a3b8', cursor: 'pointer' }}>
                ✕ Clear distance filter
              </button>
            )}
          </div>

          <div style={{ borderTop: '1px solid rgba(0,0,0,0.08)' }} />

          {/* ── Priority level ── */}
          <div>
            {sectionTitle('Priority Level')}
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {CATEGORIES.map(c => bubble(
                c.label, svcLevels.has(c.value), c.color, () => toggleLevel(c.value), c.value))}
            </div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 10 }}>
              {bubble('Select all', svcLevels.size === ALL_LEVELS.length, null, selectAll, '__all')}
              {bubble('Clear selection', svcLevels.size === 0, null, clearLevels, '__clear')}
            </div>
            <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 8 }}>
              {svcLevels.size === 0 ? 'Showing all priority levels.' : `Showing ${svcLevels.size} of ${ALL_LEVELS.length} priority levels.`}
            </div>
          </div>

          <button className="btn btn-dark" onClick={onClose}
            style={{ width: '100%', justifyContent: 'center', padding: '11px', fontSize: 14, fontWeight: 700, borderRadius: 10 }}>
            Done
          </button>
        </div>
      </div>
    </div>
  )
}
