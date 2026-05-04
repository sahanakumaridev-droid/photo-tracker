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
    const fd = new FormData()
    fd.append('file', file)
    fd.append('profile_id', selected.id)
    fd.append('latitude',   lat)
    fd.append('longitude',  lng)
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
            <div className="modal-sub" style={{fontFamily:'Geist Mono, monospace'}}>
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
                    <div style={{fontWeight:700, fontSize:13, color:'#fff'}}>{p.name}</div>
                  </div>
                  <span className={`badge badge-${p.service_type}`}>{p.service_type}</span>
                  {selected?.id === p.id && <span style={{fontWeight:800, color:'#a5b4fc', marginLeft:4}}>✓</span>}
                </div>
              ))}
            </div>
          </div>

          {/* File drop */}
          <div>
            <div className="card-label" style={{marginBottom:8}}>Photo</div>
            <label style={{
              display:'block',
              border:'1.5px dashed rgba(255,255,255,0.15)',
              borderRadius:10,
              padding: preview ? 8 : '20px 16px',
              textAlign:'center',
              cursor:'pointer',
              background:'rgba(255,255,255,0.04)',
              transition:'all 0.15s',
            }}>
              {preview
                ? <img src={preview} alt="" style={{width:'100%', maxHeight:160, objectFit:'cover', borderRadius:8, display:'block'}} />
                : <>
                    <div style={{fontSize:24, marginBottom:6}}>🖼</div>
                    <div style={{fontSize:13, fontWeight:600, color:'rgba(255,255,255,0.7)'}}>Click to choose image</div>
                    <div style={{fontSize:11, color:'rgba(255,255,255,0.35)', marginTop:3}}>PNG · JPG · WEBP</div>
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
