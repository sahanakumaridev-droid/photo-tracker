# Deploy to DigitalOcean Droplet

Droplet IP: `67.205.155.35`
Stack: Nginx (frontend) + FastAPI/uvicorn (backend) + SQLite

---

## 1. Connect to your droplet

```bash
ssh root@67.205.155.35
```

---

## 2. Install system dependencies (run on droplet)

```bash
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv nginx git
```

Install Node.js 20:
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
```

---

## 3. Deploy the backend

```bash
# Create app directory
mkdir -p /opt/photo-tracker/backend
cd /opt/photo-tracker/backend

# Copy files from your local machine (run this locally, not on droplet):
# scp -r photo-tracker/backend/* root@67.205.155.35:/opt/photo-tracker/backend/

# Back on the droplet — set up Python venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create the systemd service so the backend auto-starts:
```bash
cat > /etc/systemd/system/photo-tracker.service << 'EOF'
[Unit]
Description=Photo Tracker FastAPI Backend
After=network.target

[Service]
User=root
WorkingDirectory=/opt/photo-tracker/backend
ExecStart=/opt/photo-tracker/backend/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable photo-tracker
systemctl start photo-tracker
systemctl status photo-tracker
```

---

## 4. Build and deploy the frontend

Run this **locally** in your project:
```bash
cd photo-tracker/frontend
npm install
npm run build
```

Copy the build to the droplet (run locally):
```bash
scp -r photo-tracker/frontend/dist/* root@67.205.155.35:/var/www/photo-tracker/
```

Or on the droplet, create the directory first:
```bash
mkdir -p /var/www/photo-tracker
```

---

## 5. Configure Nginx

On the droplet:
```bash
cat > /etc/nginx/sites-available/photo-tracker << 'EOF'
server {
    listen 80;
    server_name 67.205.155.35;

    root /var/www/photo-tracker;
    index index.html;

    # Serve React app — all routes fall back to index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy API calls to FastAPI backend
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        client_max_body_size 20M;
    }

    # Proxy uploaded images to FastAPI backend
    location /uploads/ {
        proxy_pass http://127.0.0.1:8000/uploads/;
        proxy_set_header Host $host;
    }
}
EOF

# Enable the site
ln -s /etc/nginx/sites-available/photo-tracker /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test config and reload
nginx -t
systemctl reload nginx
```

---

## 6. Open firewall ports

```bash
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw enable
```

---

## Done!

Visit: **http://67.205.155.35**

- Frontend served by Nginx on port 80
- API calls to `/api/*` proxied to FastAPI on port 8000 (internal only)
- Uploaded images at `/uploads/*` proxied to FastAPI
- SQLite DB + uploads stored at `/opt/photo-tracker/backend/` (persistent)

---

## Redeploy after code changes

**Backend changes:**
```bash
# Copy updated files
scp -r photo-tracker/backend/* root@67.205.155.35:/opt/photo-tracker/backend/

# Restart the service
ssh root@67.205.155.35 "systemctl restart photo-tracker"
```

**Frontend changes:**
```bash
cd photo-tracker/frontend
npm run build
scp -r dist/* root@67.205.155.35:/var/www/photo-tracker/
```

---

## Useful commands on the droplet

```bash
# Check backend status
systemctl status photo-tracker

# View backend logs
journalctl -u photo-tracker -f

# Restart backend
systemctl restart photo-tracker

# Check Nginx logs
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log
```
