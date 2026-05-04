import React, { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { getProfilePhotos, updateProfile, updatePhotoNote } from '../api'

export default function ProfileDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [data,       setData]       = useState(null)
  const [loading,    setLoading]    = useState(true)
  const [editing,    setEditing]    = useState(false)
  const [editName,   setEditName]   = useState('')
  const [editSvc,    setEditSvc]    = useState('standard')
  const [editNote,   setEditNote]   = useState('')
  const [saving,     setSaving]     = useState(false)

  const load = () => {
    getProfilePhotos(id)
      .then(d => {
        setData(d)
        setEditName(d.profile.name)
        setEditSvc(d.profile.service_type)
        setEditNote(d.profile.note || '')
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }

  useEffect(() => { load() }, [id])

  const handleSave = async () => {
    setSaving(true)
    await updateProfile(id, { name: editName, service_type: editSvc, note: editNote })
    setSaving(false)
    setEditing(false)
    load()
  }

  if (loading) return <div className="dk-loading" style={{height:'100vh'}}><div className="dk-spinner"/>Loading…</div>
  if (!data)   return <div className="page" style={{padding:32}}><p style={{color:'rgba(255,255,255,0.4)'}}>Profile not found.</p></div>

  const { profile, photos } = data

  return (
    <div className="page" style={{display:'flex', flexDirection:'column', height:'100vh'}}>
      {/* Header */}
      <div className="page-header">
        <div style={{display:'flex', alignItems:'center', gap:14}}>
          <button className="back-btn" onClick={() => navigate('/profiles')}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z" fill="currentColor"/></svg>
            Profiles
          </button>
          <div style={{width:1, height:20, background:'rgba(255,255,255,0.1)'}}/>
          <div className={`avatar av-${profile.service_type}`} style={{width:36,height:36,fontSize:15,borderRadius:10}}>
            {profile.name.charAt(0).toUpperCase()}
          </div>
          <div>
            <div className="page-title" style={{fontSize:16}}>{profile.name}</div>
            <div className="page-sub" style={{marginTop:1}}>
              <span className={`badge badge-${profile.service_type}`}>{profile.service_type}</span>
              <span style={{fontFamily:'Geist Mono, monospace', fontSize:10, marginLeft:8, color:'rgba(255,255,255,0.3)'}}>#{profile.id}</span>
            </div>
          </div>
        </div>
        <div style={{display:'flex', alignItems:'center', gap:12}}>
          <button
            className="btn btn-outline"
            style={{fontSize:12, padding:'6px 14px'}}
            onClick={() => setEditing(v => !v)}
          >
            {editing ? '✕ Cancel' : '✏️ Edit Profile'}
          </button>
          <div style={{textAlign:'right'}}>
            <div style={{fontSize:28, fontWeight:900, letterSpacing:'-1px', color:'#fff', fontFamily:'Geist Mono, monospace'}}>{photos.length}</div>
            <div style={{fontSize:10, color:'rgba(255,255,255,0.3)', textTransform:'uppercase', letterSpacing:'0.8px', marginTop:2}}>photos</div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div style={{flex:1, overflowY:'auto', padding:'20px 28px'}}>

        {/* Edit form */}
        {editing && (
          <div className="card" style={{marginBottom:16}}>
            <div className="step-head" style={{marginBottom:16}}>
              <div className="step-num">✏</div>
              <div className="step-title">Edit Profile</div>
            </div>
            <label>Name</label>
            <input
              value={editName}
              onChange={e => setEditName(e.target.value)}
              placeholder="Profile name"
            />
            <label>Service Type</label>
            <div style={{display:'flex', gap:8, marginBottom:14}}>
              {['standard','rush'].map(t => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setEditSvc(t)}
                  className={`btn ${editSvc === t ? (t === 'rush' ? 'btn-dark' : 'btn-green') : 'btn-outline'}`}
                  style={{fontSize:12, padding:'6px 16px'}}
                >
                  {t === 'rush' ? '🔴 Rush (ASAP)' : '🟢 Standard'}
                </button>
              ))}
            </div>
            <label>Profile Note</label>
            <textarea
              value={editNote}
              onChange={e => setEditNote(e.target.value)}
              rows={3}
              placeholder="Add a note about this profile…"
              style={{
                width:'100%', padding:'10px 13px',
                background:'rgba(255,255,255,0.06)',
                border:'1px solid rgba(255,255,255,0.1)',
                borderRadius:9, fontSize:13.5, color:'#e2e8f0',
                outline:'none', resize:'vertical',
                fontFamily:'Geist, sans-serif', marginBottom:14,
              }}
            />
            <button
              className="btn btn-dark"
              onClick={handleSave}
              disabled={saving || !editName.trim()}
            >
              {saving ? <><div className="dk-spinner" style={{width:13,height:13}}/>Saving…</> : '✓ Save Changes'}
            </button>
          </div>
        )}

        {/* Profile note display */}
        {!editing && profile.note && (
          <div className="card" style={{marginBottom:16, borderColor:'rgba(99,102,241,0.2)'}}>
            <div style={{fontSize:10, fontWeight:700, color:'rgba(255,255,255,0.3)', textTransform:'uppercase', letterSpacing:'0.8px', marginBottom:8}}>Profile Note</div>
            <div style={{fontSize:13, color:'rgba(255,255,255,0.7)', lineHeight:1.6}}>{profile.note}</div>
          </div>
        )}

        {/* Photos */}
        <div className="card">
          <div className="sec-header">
            <span className="sec-title" style={{color:'rgba(255,255,255,0.7)'}}>Photos</span>
            <span className="sec-count">{photos.length}</span>
          </div>
          {photos.length === 0
            ? <div className="dk-empty"><div>No photos uploaded yet</div></div>
            : <div className="dk-photo-grid">
                {photos.map(p => (
                  <PhotoCard key={p.id} p={p} onNoteUpdated={load} />
                ))}
              </div>
          }
        </div>
      </div>
    </div>
  )
}

function PhotoCard({ p, onNoteUpdated }) {
  const [note,    setNote]    = useState(p.note || '')
  const [editing, setEditing] = useState(false)
  const [saving,  setSaving]  = useState(false)

  const save = async () => {
    setSaving(true)
    await updatePhotoNote(p.id, note)
    setSaving(false)
    setEditing(false)
    onNoteUpdated()
  }

  return (
    <div className="dk-photo-card">
      <img src={p.image_url} alt=""
        onError={e => { e.target.src='https://via.placeholder.com/400x300/1e1b4b/6366f1?text=Photo' }}/>
      <div className="dk-photo-meta">
        <div className="dk-photo-info">🕐 {new Date(p.timestamp).toLocaleString()}</div>
        <div className="dk-photo-info" style={{fontFamily:'Geist Mono, monospace'}}>
          📍 {p.latitude?.toFixed(5)}, {p.longitude?.toFixed(5)}
        </div>
        {p.zip_code && <div className="dk-photo-info">📮 {p.zip_code}</div>}

        {/* Editable note */}
        <div style={{marginTop:8, paddingTop:8, borderTop:'1px solid rgba(255,255,255,0.06)'}}>
          {editing ? (
            <>
              <textarea
                value={note}
                onChange={e => setNote(e.target.value)}
                rows={2}
                autoFocus
                style={{
                  width:'100%', padding:'6px 8px',
                  background:'rgba(255,255,255,0.06)',
                  border:'1px solid rgba(99,102,241,0.4)',
                  borderRadius:6, fontSize:11.5, color:'#e2e8f0',
                  outline:'none', resize:'vertical',
                  fontFamily:'Geist, sans-serif', marginBottom:6,
                }}
              />
              <div style={{display:'flex', gap:5}}>
                <button className="popup-save-btn" onClick={save} disabled={saving}>{saving ? '…' : 'Save'}</button>
                <button className="popup-cancel-btn" onClick={() => { setEditing(false); setNote(p.note || '') }}>Cancel</button>
              </div>
            </>
          ) : (
            <div
              onClick={() => setEditing(true)}
              style={{
                fontSize:11.5, color: note ? 'rgba(255,255,255,0.55)' : 'rgba(255,255,255,0.2)',
                cursor:'pointer', padding:'4px 6px', borderRadius:5,
                border:'1px solid rgba(255,255,255,0.05)',
                background:'rgba(255,255,255,0.02)',
                fontStyle: note ? 'normal' : 'italic',
              }}
            >
              {note || 'Add note…'} <span style={{opacity:0.4, fontSize:10}}>✏️</span>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
