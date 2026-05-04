# Free Deployment — Render + Vercel

## Step 1 — Push to GitHub

```bash
cd photo-tracker
git init
git add .
git commit -m "initial commit"
```

Create a repo at github.com/new then:

```bash
git remote add origin https://github.com/YOUR_USERNAME/photo-tracker.git
git push -u origin main
```

---

## Step 2 — Backend on Render (free)

1. Go to render.com, sign up free
2. New → Web Service → connect your GitHub repo
3. Settings:
   - Root Directory: `backend`
   - Runtime: Python 3
   - Build Command: `pip install -r requirements.txt`
   - Start Command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
4. Deploy — you get a URL like `https://geotagging-backend.onrender.com`

---

## Step 3 — Frontend on Vercel (free)

1. Go to vercel.com, sign up with GitHub
2. New Project → import your repo
3. Settings:
   - Root Directory: `frontend`
   - Framework: Vite
   - Build Command: `npm run build`
   - Output Directory: `dist`
4. Add Environment Variable:
   - Key: `VITE_API_URL`
   - Value: your Render URL from Step 2
5. Deploy — you get a URL like `https://geotagging.vercel.app`

---

## Notes

- Render free tier sleeps after 15 min idle (30s cold start on first visit)
- Vercel frontend is always fast, no sleep
- SQLite data resets on Render redeploy (free tier has no persistent disk)
- For persistent data, add a free PostgreSQL on Render and update DATABASE_URL
