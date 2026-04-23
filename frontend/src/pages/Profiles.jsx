import React, { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getProfiles, createProfile, deleteProfile } from '../api'

export default function Profiles({ showToast }) {
  const [profiles, setProfiles] = useState([])
  const [loading,  setLoading]  = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [name,     setName]     = useState('')
  const [svcType,  setSvcType]  = useState('standard')
  const [saving,   setSaving]   = useState(false)
  const navigate = useNavigate()

  const load = async () => {
    setLoading(true)
    setProfiles(await getProfiles())
    setLoading(false)
  }

  useEffect(() => { load() }, [])

  const handleCreate = async (e) => {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    const fd = new FormData()
    fd.append('name', name)
    fd.append('service_type', svcType)
    try {
      await createProfile(fd)
      showToast('Profile created')
      setName(''); setSvcType('standard'); setShowForm(false)
      load()
    } catch { showToast('Failed to create profile', 'error') }
    setSaving(false)
  }

  const handleDelete = async (id) => {
    try {
      await deleteProfile(id)
      showToast('Profile deleted')
      load()
    } catch { showToast('Failed to delete profile', 'error') }
  }

  const rush     = profiles.filter(p => p.service_type === 'rush')
  const standard = profiles.filter(p => p.service_type === 'standard')

  return (
    <div className="page">
      <div className="page-header">
        <div>
          <div className="page-title">Profiles</div>
          <div className="page-sub">{profiles.length} profiles · {rush.length} rush · {standard.length} standard</div>
        </div>
        <button className="btn btn-dark" onClick={() => setShowForm(v => !v)}>
          {showForm ? '✕ Cancel' : '+ New profile'}
        </button>
      </div>

      {showForm && (
        <div className="form-slide">
          <div className="card-label">New Profile</div>
          <form onSubmit={handleCreate}>
            <label>Name</label>
            <input value={name} onChange={e => setName(e.target.value)} placeholder="Full name" required />
            <label>Service type</label>
            <select value={svcType} onChange={e => setSvcType(e.target.value)}>
              <option value="standard">Standard</option>
              <option value="rush">Rush</option>
            </select>
            <button className="btn btn-dark" type="submit" disabled={saving}>
              {saving ? <><div className="spinner" style={{width:13,height:13,borderTopColor:'#fff'}}/>Creating…</> : 'Create profile'}
            </button>
          </form>
        </div>
      )}

      {loading
        ? <div className="loading"><div className="spinner"/>Loading…</div>
        : profiles.length === 0
          ? <div className="empty"><div className="empty-icon">👤</div><div className="empty-text">No profiles yet</div></div>
          : <>
              {rush.length > 0 && (
                <>
                  <div className="group-label">Rush</div>
                  {rush.map(p => <ProfileRow key={p.id} p={p} onClick={() => navigate(`/profiles/${p.id}`)} onDelete={handleDelete} />)}
                </>
              )}
              {standard.length > 0 && (
                <>
                  <div className="group-label">Standard</div>
                  {standard.map(p => <ProfileRow key={p.id} p={p} onClick={() => navigate(`/profiles/${p.id}`)} onDelete={handleDelete} />)}
                </>
              )}
            </>
      }
    </div>
  )
}

function ProfileRow({ p, onClick, onDelete }) {
  const [confirming, setConfirming] = useState(false)
  return (
    <div className="profile-row" onClick={!confirming ? onClick : undefined} style={{cursor: confirming ? 'default' : 'pointer'}}>
      <div className={`avatar av-${p.service_type}`}>{p.name.charAt(0).toUpperCase()}</div>
      <div style={{flex:1}}>
        <div style={{fontWeight:700, fontSize:14}}>{p.name}</div>
        <div style={{fontSize:11, color:'var(--text3)', marginTop:2, fontFamily:'Geist Mono, monospace'}}>#{p.id}</div>
      </div>
      <span className={`badge badge-${p.service_type}`}>{p.service_type}</span>
      {confirming ? (
        <div style={{display:'flex', gap:6, alignItems:'center', marginLeft:8}} onClick={e => e.stopPropagation()}>
          <span style={{fontSize:12, color:'var(--text2)'}}>Delete?</span>
          <button className="del-yes" onClick={() => { onDelete(p.id); setConfirming(false) }}>Yes</button>
          <button className="del-no"  onClick={() => setConfirming(false)}>No</button>
        </div>
      ) : (
        <button className="row-delete-btn" onClick={e => { e.stopPropagation(); setConfirming(true) }} title="Delete">✕</button>
      )}
    </div>
  )
}
