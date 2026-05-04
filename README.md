# 📍 GeoTagging — Full Stack App

## Quick Start (2 terminals)

### Terminal 1 — Backend
```bash
cd photo-tracker/backend
pip3 install -r requirements.txt
uvicorn main:app --reload --port 8000
```

### Terminal 2 — Frontend
```bash
cd photo-tracker/frontend
npm install
npm run dev
```

Then open: http://localhost:3000

---

## Features
- 🗺 Interactive map with red (Rush) and blue (Standard) pins
- 📷 Upload photos with auto GPS + timestamp capture
- 👤 Profile management with service type flagging
- 🟢 Your current location shown on map
- 🔄 Auto-refresh after upload

## Stack
- Frontend: React + Vite + React-Leaflet (OpenStreetMap)
- Backend: FastAPI + SQLite
- Sample data preloaded on first run
