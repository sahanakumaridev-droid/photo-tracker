import React, { useState, useRef, useEffect } from 'react'
import { useMap } from 'react-leaflet'

export default function LocationSearch({ onPick }) {
  const [query,    setQuery]    = useState('')
  const [results,  setResults]  = useState([])
  const [loading,  setLoading]  = useState(false)
  const [open,     setOpen]     = useState(false)
  const map = useMap()
  const timer = useRef(null)
  const wrapRef = useRef(null)

  // Close dropdown on outside click
  useEffect(() => {
    const fn = e => { if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', fn)
    return () => document.removeEventListener('mousedown', fn)
  }, [])

  const search = (val) => {
    setQuery(val)
    clearTimeout(timer.current)
    if (!val.trim()) { setResults([]); setOpen(false); return }
    timer.current = setTimeout(async () => {
      setLoading(true)
      try {
        const res = await fetch(
          `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(val)}&limit=6`,
          { headers: { 'Accept-Language': 'en' } }
        )
        const data = await res.json()
        setResults(data)
        setOpen(true)
      } catch { setResults([]) }
      setLoading(false)
    }, 400)
  }

  const pick = (item) => {
    const lat = parseFloat(item.lat)
    const lng = parseFloat(item.lon)
    onPick(lat, lng)
    map.flyTo([lat, lng], 15, { duration: 1 })
    setQuery(item.display_name.split(',').slice(0, 2).join(','))
    setOpen(false)
    setResults([])
  }

  return (
    <div ref={wrapRef} className="loc-search-wrap">
      <div className="loc-search-input-row">
        <span className="loc-search-icon">🔍</span>
        <input
          className="loc-search-input"
          type="text"
          placeholder="Search city, address, place…"
          value={query}
          onChange={e => search(e.target.value)}
          onFocus={() => results.length > 0 && setOpen(true)}
          autoComplete="off"
        />
        {loading && <div className="spinner" style={{width:14,height:14,flexShrink:0,marginRight:8}} />}
        {query && !loading && (
          <button className="loc-search-clear" onClick={() => { setQuery(''); setResults([]); setOpen(false) }}>✕</button>
        )}
      </div>

      {open && results.length > 0 && (
        <div className="loc-search-dropdown">
          {results.map((r, i) => (
            <div key={i} className="loc-search-item" onClick={() => pick(r)}>
              <span className="loc-search-item-icon">📍</span>
              <div>
                <div className="loc-search-item-name">{r.display_name.split(',').slice(0,2).join(',')}</div>
                <div className="loc-search-item-sub">{r.display_name.split(',').slice(2,4).join(',').trim()}</div>
              </div>
            </div>
          ))}
        </div>
      )}

      {open && results.length === 0 && !loading && query && (
        <div className="loc-search-dropdown">
          <div className="loc-search-empty">No results found</div>
        </div>
      )}
    </div>
  )
}
