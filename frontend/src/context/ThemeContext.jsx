import React, { createContext, useContext, useState, useEffect } from 'react'

const ACCENT_PRESETS = [
  { id: 'indigo',  label: 'Indigo',  primary: '#6366f1', secondary: '#8b5cf6', hex: '#6366f1' },
  { id: 'blue',    label: 'Blue',    primary: '#3b82f6', secondary: '#6366f1', hex: '#3b82f6' },
  { id: 'violet',  label: 'Violet',  primary: '#7c3aed', secondary: '#a78bfa', hex: '#7c3aed' },
  { id: 'rose',    label: 'Rose',    primary: '#f43f5e', secondary: '#fb7185', hex: '#f43f5e' },
  { id: 'emerald', label: 'Emerald', primary: '#10b981', secondary: '#34d399', hex: '#10b981' },
  { id: 'amber',   label: 'Amber',   primary: '#f59e0b', secondary: '#fbbf24', hex: '#f59e0b' },
  { id: 'cyan',    label: 'Cyan',    primary: '#06b6d4', secondary: '#22d3ee', hex: '#06b6d4' },
  { id: 'slate',   label: 'Slate',   primary: '#475569', secondary: '#64748b', hex: '#475569' },
]

const ThemeContext = createContext(null)

export function ThemeProvider({ children }) {
  const [mode, setMode]           = useState(() => localStorage.getItem('theme-mode') || 'light')
  const [accent, setAccent]       = useState(() => localStorage.getItem('theme-accent') || 'indigo')
  const [settingsOpen, setSettings] = useState(false)

  const accentPreset = ACCENT_PRESETS.find(p => p.id === accent) || ACCENT_PRESETS[0]

  useEffect(() => {
    const root = document.documentElement
    localStorage.setItem('theme-mode', mode)
    localStorage.setItem('theme-accent', accent)

    // ── Accent tokens ──
    root.style.setProperty('--accent',       accentPreset.primary)
    root.style.setProperty('--accent2',      accentPreset.secondary)
    root.style.setProperty('--accent-light', hexToRgba(accentPreset.primary, 0.12))
    root.style.setProperty('--accent-mid',   hexToRgba(accentPreset.primary, 0.20))
    root.style.setProperty('--accent-text',  accentPreset.primary)

    // ── Mode tokens ──
    if (mode === 'dark') {
      root.style.setProperty('--bg-page',    '#0f0e1a')
      root.style.setProperty('--bg-surface', '#13111f')
      root.style.setProperty('--bg-card',    '#1a1830')
      root.style.setProperty('--bg-input',   'rgba(255,255,255,0.06)')
      root.style.setProperty('--bg-hover',   'rgba(255,255,255,0.07)')
      root.style.setProperty('--bg-subtle',  'rgba(255,255,255,0.04)')
      root.style.setProperty('--border-c',   'rgba(255,255,255,0.08)')
      root.style.setProperty('--border-c2',  'rgba(255,255,255,0.12)')
      root.style.setProperty('--text-1',     '#f1f5f9')
      root.style.setProperty('--text-2',     'rgba(255,255,255,0.6)')
      root.style.setProperty('--text-3',     'rgba(255,255,255,0.35)')
      root.style.setProperty('--shadow-card','0 4px 24px rgba(0,0,0,0.4)')
    } else {
      root.style.setProperty('--bg-page',    '#f1f5f9')
      root.style.setProperty('--bg-surface', '#ffffff')
      root.style.setProperty('--bg-card',    '#ffffff')
      root.style.setProperty('--bg-input',   '#f8fafc')
      root.style.setProperty('--bg-hover',   '#f8fafc')
      root.style.setProperty('--bg-subtle',  '#f8fafc')
      root.style.setProperty('--border-c',   '#e2e8f0')
      root.style.setProperty('--border-c2',  '#cbd5e1')
      root.style.setProperty('--text-1',     '#0f172a')
      root.style.setProperty('--text-2',     '#475569')
      root.style.setProperty('--text-3',     '#94a3b8')
      root.style.setProperty('--shadow-card','0 4px 16px rgba(0,0,0,0.07)')
    }

    // data attribute for CSS selectors
    root.setAttribute('data-theme', mode)
  }, [mode, accent])

  return (
    <ThemeContext.Provider value={{ mode, setMode, accent, setAccent, accentPreset, ACCENT_PRESETS, settingsOpen, setSettings }}>
      {children}
    </ThemeContext.Provider>
  )
}

export const useTheme = () => useContext(ThemeContext)

function hexToRgba(hex, alpha) {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r},${g},${b},${alpha})`
}

export { ACCENT_PRESETS }
