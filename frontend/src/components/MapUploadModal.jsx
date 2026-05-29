import React, { useState, useEffect } from 'react'
import { getProfiles, uploadPhoto } from '../api'

export default function MapUploadModal({ lat, lng, onClose, onUploaded }) {
  const [profiles,  setProfiles]  = useState([])
  const [selected,  setSelected]  = useState(null)
  const [file,      setFile]      = useState(null)
  const [preview,   setPreview]   = useState(null)
  const [uploading, setUploading] = useState(false)
  const [error,     setError]     = useState('')

  useEffect(() => {
    getProfiles().then(setProfiles)
    const fn = e => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', fn)
    return () => window.removeEventListener('keydown', fn)
  }, [onClose])

  const pickFile = f => { setFile(f); setPreview(URL.createObjectURL(f)) }

  const handleUpload = async () => {
    if (!file || !selected) return
    setUploading(true)

    // Reverse geocode the pin location
    let address = ''
    try {
      const res = await fetch(
        `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1&extratags=1&_t=${Date.now()}`,
        { headers: { 'Accept-Language': 'en' } }
      )
      const data = await res.json()
      if (data?.address) {
        const a = data.address
        const seen = new Set()
        const parts = []
        const road = a.road || a.pedestrian || a.path
        if (road) {
          const street = a.house_number ? `${a.house_number} ${road}` : road
          parts.push(street)
          seen.add(street.toLowerCase())
        }
        const city = a.city || a.town || a.village || a.municipality
        if (city && !seen.has(city.toLowerCase())) parts.push(city)
        if (a.state_code || a.state) {
          const st = a.state_code || a.state
          if (!seen.has(st.toLowerCase())) parts.push(st)
        }
        if (a.postcode) parts.push(a.postcode)
        address = parts.join(', ') || data.display_name || ''
      }
    } catch { /* non-critical */ }

    const fd = new FormData()
    fd.append('file', file)
    fd.append('profile_id', selected.id)
    fd.append('latitude',   lat)
    fd.append('longitude',  lng)
    if (address) fd.append('address', address)
    try {
      await uploadPhoto(fd)
      onUploaded()
      onClose()
    } catch { setError('Upload failed. Try again.') }
    setUploading(false)
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" style={{maxWidth:480}} onClick={e => e.stopPropagation()}>

        {/* Header */}
        <div className="modal-header">
          <div>
            <div className="modal-title">📍 Upload at this location</div>
            <div className="modal-sub">
              {lat.toFixed(5)}, {lng.toFixed(5)}
            </div>
          </div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div style={{padding:'16px 20px', display:'flex', flexDirection:'column', gap:14}}>

          {/* Profile select */}
          <div>
            <div className="card-label" style={{marginBottom:8}}>Select Profile</div>
            <div style={{display:'flex', flexDirection:'column', gap:6, maxHeight:180, overflowY:'auto'}}>
              {profiles.map(p => (
                <div
                  key={p.id}
                  className={`profile-row ${selected?.id === p.id ? 'selected' : ''}`}
                  style={{padding:'10px 12px'}}
                  onClick={() => setSelected(p)}
                >
                  <div className={`avatar av-${p.service_type}`} style={{width:32,height:32,fontSize:13,borderRadius:8}}>
                    {p.name.charAt(0)}
                  </div>
                  <div style={{flex:1}}>
                    <div style={{fontWeight:700, fontSize:13}}>{p.name}</div>
                  </div>
                  <span className={`badge badge-${p.service_type}`}>{p.service_type}</span>
                  {selected?.id === p.id && <span style={{fontWeight:800, color:'var(--accent)', marginLeft:4}}>✓</span>}
                </div>
              ))}
            </div>
          </div>

          {/* File drop */}
          <div>
            <div className="card-label" style={{marginBottom:8}}>Photo</div>
            <label className={`drop-zone ${preview ? 'filled' : ''}`}>
              {preview
                ? <img src={preview} alt="" style={{width:'100%', maxHeight:160, objectFit:'cover', borderRadius:8, display:'block'}} />
                : <>
                    <div className="drop-icon">🖼</div>
                    <div className="drop-title">Click to choose image</div>
                    <div className="drop-sub">PNG · JPG · WEBP</div>
                  </>
              }
              <input type="file" accept="image/*" style={{display:'none'}}
                onChange={e => e.target.files[0] && pickFile(e.target.files[0])} />
            </label>
            {file && (
              <button className="btn btn-outline" style={{fontSize:11, padding:'4px 10px', marginTop:6}}
                onClick={() => { setFile(null); setPreview(null) }}>✕ Remove</button>
            )}
          </div>

          {error && <div className="modal-error">✕ {error}</div>}

          {/* Actions */}
          <div className="modal-actions" style={{padding:0}}>
            <button className="btn btn-outline" onClick={onClose}>Cancel</button>
            <button
              className="btn btn-green"
              onClick={handleUpload}
              disabled={!file || !selected || uploading}
            >
              {uploading
                ? <><div className="spinner" style={{width:13,height:13,borderTopColor:'#fff'}}/>Uploading…</>
                : '↑ Upload here'
              }
            </button>
          </div>

        </div>
      </div>
    </div>
  )
}
