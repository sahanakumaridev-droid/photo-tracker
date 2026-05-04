import React, { useEffect, useRef } from 'react'
import { useTheme } from '../context/ThemeContext'

export default function SettingsPanel({ open, onClose, user, onLogout }) {
  const { mode, setMode, accent, setAccent, ACCENT_PRESETS } = useTheme()
  const popoverRef = useRef(null)

  // Close on outside click
  useEffect(() => {
    if (!open) return
    const handler = (e) => {
      if (popoverRef.current && !popoverRef.current.contains(e.target)) onClose()
    }
    setTimeout(() => document.addEventListener('mousedown', handler), 0)
    return () => document.removeEventListener('mousedown', handler)
  }, [open, onClose])

  // Close on Escape
  useEffect(() => {
    const handler = (e) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [onClose])

  if (!open) return null

  return (
    <div ref={popoverRef} className="sp-popover">

      {/* Arrow pointing down toward the footer */}
      <div className="sp-popover-arrow" />

      {/* Header */}
      <div className="sp-pop-header">
        <span className="sp-pop-title">Appearance</span>
        <button className="sp-pop-close" onClick={onClose}>
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none">
            <line x1="18" y1="6" x2="6" y2="18" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"/>
            <line x1="6" y1="6" x2="18" y2="18" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"/>
          </svg>
        </button>
      </div>

      {/* Theme toggle — pill style */}
      <div className="sp-pop-section">
        <div className="sp-pop-label">Theme</div>
        <div className="sp-theme-toggle">
          <button
            className={`sp-theme-btn ${mode === 'light' ? 'sp-theme-active' : ''}`}
            onClick={() => setMode('light')}
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
              <circle cx="12" cy="12" r="5" fill="currentColor"/>
              <line x1="12" y1="1" x2="12" y2="3" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="12" y1="21" x2="12" y2="23" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="1" y1="12" x2="3" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="21" y1="12" x2="23" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
            </svg>
            Light
          </button>
          <button
            className={`sp-theme-btn ${mode === 'dark' ? 'sp-theme-active' : ''}`}
            onClick={() => setMode('dark')}
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
              <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" fill="currentColor"/>
            </svg>
            Dark
          </button>
        </div>
      </div>

      {/* Accent colors — compact dot grid */}
      <div className="sp-pop-section">
        <div className="sp-pop-label">Accent</div>
        <div className="sp-color-row">
          {ACCENT_PRESETS.map(preset => (
            <button
              key={preset.id}
              className={`sp-color-dot ${accent === preset.id ? 'sp-color-active' : ''}`}
              onClick={() => setAccent(preset.id)}
              title={preset.label}
              style={{ background: preset.primary }}
            >
              {accent === preset.id && (
                <svg width="9" height="9" viewBox="0 0 24 24" fill="none">
                  <polyline points="20 6 9 17 4 12" stroke="#fff" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Divider */}
      <div className="sp-pop-divider" />

      {/* Sign out */}
      <button className="sp-pop-logout" onClick={onLogout}>
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
          <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          <polyline points="16 17 21 12 16 7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          <line x1="21" y1="12" x2="9" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
        </svg>
        Sign out
      </button>

    </div>
  )
}
