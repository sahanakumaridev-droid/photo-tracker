#!/bin/bash
# One-command deploy to the Namecheap VPS
# Usage: ./deploy.sh
# Run from the photo-tracker/ directory

set -e

# Namecheap VPS (159.198.79.219 / zedev.website). The mobile app talks to
# https://159-198-79-219.nip.io which is served from this host.
# NOTE: the DB now lives in PostgreSQL on this box (DATABASE_URL in backend/.env),
# not in the SQLite file. The rsync below ships code only and never touches .env,
# so the connection string is preserved across deploys.
DROPLET_IP="159.198.79.219"
REMOTE="root@${DROPLET_IP}"

echo "==> Building frontend..."
cd frontend
npm install --legacy-peer-deps
npm run build
cd ..

echo "==> Uploading backend CODE ONLY (preserves prod DB, uploads, .env)..."
ssh $REMOTE "mkdir -p /opt/photo-tracker/backend /var/www/photo-tracker"
# Ship application code ONLY. No --delete, so the server's photo_tracker.db,
# uploads/, and .env are never touched. Allowlist: .py, requirements.txt, render.yaml.
rsync -az \
  --include='*/' \
  --include='*.py' \
  --include='requirements.txt' \
  --include='render.yaml' \
  --exclude='*' \
  backend/ $REMOTE:/opt/photo-tracker/backend/

echo "==> Uploading frontend build..."
scp -r frontend/dist/* $REMOTE:/var/www/photo-tracker/

echo "==> Configuring server..."
ssh $REMOTE bash << 'ENDSSH'
set -e

# Install deps if not already installed
if ! command -v uvicorn &> /dev/null && [ ! -d /opt/photo-tracker/backend/venv ]; then
  echo "--- Installing system packages..."
  apt-get update -qq
  apt-get install -y -qq python3 python3-pip python3-venv nginx

  # Node.js 20
  if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null
    apt-get install -y -qq nodejs
  fi
fi

# Python venv + deps
cd /opt/photo-tracker/backend
if [ ! -d venv ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install -q -r requirements.txt

# Systemd service
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
systemctl restart photo-tracker

# Nginx config — FIRST-TIME SETUP ONLY.
# If a config already exists (e.g. one that certbot upgraded to HTTPS/443),
# DO NOT overwrite it — that would strip the SSL server block and break
# https://159-198-79-219.nip.io, which the mobile app depends on. Deploys
# only refresh code + static files; TLS/nginx is managed out of band.
if [ -f /etc/nginx/sites-available/photo-tracker ]; then
  echo "--- nginx config already present — leaving it untouched (preserves HTTPS)."
else
  cat > /etc/nginx/sites-available/photo-tracker << 'EOF'
server {
    listen 80;
    server_name _;

    root /var/www/photo-tracker;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        client_max_body_size 20M;
    }

    location /uploads/ {
        proxy_pass http://127.0.0.1:8000/uploads/;
        proxy_set_header Host $host;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/photo-tracker /etc/nginx/sites-enabled/photo-tracker
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx
  echo "--- nginx configured (HTTP). Run certbot --nginx afterwards to enable HTTPS."
fi

# Firewall
ufw allow OpenSSH > /dev/null 2>&1 || true
ufw allow 'Nginx Full' > /dev/null 2>&1 || true
ufw --force enable > /dev/null 2>&1 || true

echo "--- Done!"
ENDSSH

echo ""
echo "✅ Deployed successfully!"
echo "   Visit: http://${DROPLET_IP}"
