import React, { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { getProfilePhotos } from '../api'

export default function ProfileDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [data,    setData]    = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    getProfilePhotos(id)
      .then(d => { setData(d); setLoading(false) })
      .catch(() => setLoading(false))
  }, [id])

  if (loading) return <div className="loading"><div className="spinner"/>Loading…</div>
  if (!data)   return <div className="page"><p style={{color:'var(--text3)'}}>Profile not found.</p></div>

  const { profile, photos } = data

  return (
    <div className="page">
      <button className="back-btn" onClick={() => navigate('/profiles')}>← Profiles</button>

      <div className="profile-hero">
        <div className={`avatar av-${profile.service_type}`} style={{width:56,height:56,fontSize:22,borderRadius:14}}>
          {profile.name.charAt(0).toUpperCase()}
        </div>
        <div style={{flex:1}}>
          <div className="hero-name">{profile.name}</div>
          <div className="hero-meta">
            <span className={`badge badge-${profile.service_type}`}>{profile.service_type}</span>
            <span style={{fontFamily:'Geist Mono, monospace', fontSize:11}}>#{profile.id}</span>
          </div>
        </div>
        <div style={{textAlign:'right'}}>
          <div style={{fontSize:30, fontWeight:900, letterSpacing:'-1px'}}>{photos.length}</div>
          <div style={{fontSize:11, color:'var(--text3)', textTransform:'uppercase', letterSpacing:'0.8px', marginTop:2}}>photos</div>
        </div>
      </div>

      <div className="card">
        <div className="sec-header">
          <span className="sec-title">Photos</span>
          <span className="sec-count">{photos.length}</span>
        </div>
        {photos.length === 0
          ? <div className="empty"><div className="empty-icon">📷</div><div className="empty-text">No photos uploaded yet</div></div>
          : <div className="photo-grid">
              {photos.map(p => (
                <div className="photo-card" key={p.id}>
                  <img
                    src={p.image_url} alt=""
                    onError={e => { e.target.src='https://via.placeholder.com/400x300/f5f5f4/a8a29e?text=Photo' }}
                  />
                  <div className="photo-meta-wrap">
                    <div className="photo-meta">🕐 {new Date(p.timestamp).toLocaleString()}</div>
                    <div className="photo-meta" style={{fontFamily:'Geist Mono, monospace'}}>
                      {p.latitude?.toFixed(5)}, {p.longitude?.toFixed(5)}
                    </div>
                  </div>
                </div>
              ))}
            </div>
        }
      </div>
    </div>
  )
}
