from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Text, ForeignKey, Table
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from typing import Optional
import os, shutil, uuid, smtplib, json
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

PST = ZoneInfo("America/Los_Angeles")

app = FastAPI()

origins = os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DATABASE_URL = "sqlite:///./photo_tracker.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


# ── Many-to-many: Pin (Photo) <-> Profile ──
pin_profile = Table(
    "pin_profile",
    Base.metadata,
    Column("photo_id",   Integer, ForeignKey("photos.id",   ondelete="CASCADE"), primary_key=True),
    Column("profile_id", Integer, ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True),
)


class Profile(Base):
    __tablename__ = "profiles"
    id           = Column(Integer, primary_key=True, index=True)
    name         = Column(String, nullable=False)
    service_type = Column(String, default="standard")
    note         = Column(Text, nullable=True)
    photos       = relationship("Photo", secondary=pin_profile, back_populates="profiles")


class Photo(Base):
    __tablename__ = "photos"
    id        = Column(Integer, primary_key=True, index=True)
    image_url = Column(String)
    timestamp = Column(DateTime, default=datetime.utcnow)
    latitude  = Column(Float)
    longitude = Column(Float)
    zip_code  = Column(String, nullable=True)
    note      = Column(Text,   nullable=True)
    # legacy single profile_id kept for backward compat
    profile_id = Column(Integer, nullable=True)
    profiles   = relationship("Profile", secondary=pin_profile, back_populates="photos")


Base.metadata.create_all(bind=engine)


def _photo_dict(ph):
    profiles = [{"id": p.id, "name": p.name, "service_type": p.service_type} for p in ph.profiles]
    primary = profiles[0] if profiles else None
    # Convert timestamp to PST ISO string
    ts = ph.timestamp
    if ts:
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        ts_pst = ts.astimezone(PST).isoformat()
    else:
        ts_pst = None
    return {
        "id":           ph.id,
        "image_url":    ph.image_url,
        "timestamp":    ts_pst,
        "latitude":     ph.latitude,
        "longitude":    ph.longitude,
        "zip_code":     ph.zip_code,
        "note":         ph.note,
        "profile_id":   primary["id"]   if primary else ph.profile_id,
        "profile_name": primary["name"] if primary else "Unknown",
        "service_type": primary["service_type"] if primary else "standard",
        "profiles":     profiles,
    }


def seed_data():
    # No static seed data — app starts clean
    pass


seed_data()


# ─── PROFILE ROUTES ───────────────────────────────────────────────────────────

@app.get("/profiles")
def get_profiles():
    db = SessionLocal()
    profiles = db.query(Profile).all()
    result = [{"id": p.id, "name": p.name, "service_type": p.service_type, "note": p.note} for p in profiles]
    db.close()
    return result


@app.post("/profiles")
async def create_profile(data: dict = Body(...)):
    name = data.get("name", "").strip()
    service_type = data.get("service_type", "standard").strip()
    
    if not name:
        raise HTTPException(status_code=422, detail="Profile name is required")
    
    if service_type not in ("standard", "rush", "airport"):
        service_type = "standard"
    
    db = SessionLocal()
    profile = Profile(name=name, service_type=service_type)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    db.close()
    return {"id": profile.id, "name": profile.name, "service_type": profile.service_type, "note": profile.note}


@app.patch("/profiles/{profile_id}")
async def update_profile(profile_id: int, data: dict = Body(...)):
    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")
    
    if "name" in data:
        profile.name = data["name"]
    if "service_type" in data:
        profile.service_type = data["service_type"]
    if "note" in data:
        profile.note = data["note"]
    
    db.commit()
    db.refresh(profile)
    db.close()
    return {"id": profile.id, "name": profile.name, "service_type": profile.service_type, "note": profile.note}


@app.delete("/profiles/{profile_id}")
def delete_profile(profile_id: int):
    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")
    db.delete(profile)
    db.commit()
    db.close()
    return {"ok": True}


@app.get("/profiles/{profile_id}/photos")
def get_profile_photos(profile_id: int):
    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")
    result = {
        "profile": {"id": profile.id, "name": profile.name, "service_type": profile.service_type},
        "photos":  [_photo_dict(ph) for ph in profile.photos],
    }
    db.close()
    return result


# ─── PHOTO ROUTES ─────────────────────────────────────────────────────────────

@app.get("/photos")
def get_photos():
    db = SessionLocal()
    photos = db.query(Photo).all()
    result = [_photo_dict(ph) for ph in photos]
    db.close()
    return result


@app.post("/upload")
async def upload_photo(
    file:       UploadFile = File(...),
    profile_id: int        = Form(...),
    latitude:   float      = Form(...),
    longitude:  float      = Form(...),
    zip_code:   str        = Form(""),
    note:       str        = Form(""),
):
    # Validate coordinates
    if not (-90 <= latitude <= 90):
        raise HTTPException(status_code=422, detail="Latitude must be between -90 and 90")
    if not (-180 <= longitude <= 180):
        raise HTTPException(status_code=422, detail="Longitude must be between -180 and 180")
    ext      = os.path.splitext(file.filename)[1] or ".jpg"
    filename = f"{uuid.uuid4()}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    with open(filepath, "wb") as f:
        shutil.copyfileobj(file.file, f)

    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")

    photo = Photo(
        image_url  = f"/uploads/{filename}",
        timestamp  = datetime.utcnow(),
        latitude   = latitude,
        longitude  = longitude,
        zip_code   = zip_code.strip() or None,
        note       = note.strip()     or None,
        profile_id = profile_id,
    )
    photo.profiles = [profile]
    db.add(photo)
    db.commit()
    db.refresh(photo)
    result = _photo_dict(photo)
    db.close()
    return result


@app.patch("/photos/{photo_id}/image")
async def replace_photo_image(photo_id: int, file: UploadFile = File(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    # Delete old file
    old_path = photo.image_url.lstrip("/")
    if os.path.exists(old_path):
        os.remove(old_path)
    # Save new file
    ext      = os.path.splitext(file.filename)[1] or ".jpg"
    filename = f"{uuid.uuid4()}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    with open(filepath, "wb") as f:
        shutil.copyfileobj(file.file, f)
    photo.image_url = f"/uploads/{filename}"
    db.commit()
    result = _photo_dict(photo)
    db.close()
    return result


@app.patch("/photos/{photo_id}/location")
async def update_photo_location(photo_id: int, data: dict = Body(None), latitude: float = Form(None), longitude: float = Form(None)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    
    if data:
        photo.latitude  = data.get("latitude",  photo.latitude)
        photo.longitude = data.get("longitude", photo.longitude)
    else:
        if latitude is not None:
            photo.latitude = latitude
        if longitude is not None:
            photo.longitude = longitude
    
    db.commit()
    db.close()
    return {"ok": True}


@app.patch("/photos/{photo_id}/note")
async def update_photo_note(photo_id: int, data: dict = Body(None), note: str = Form(None)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    
    if data:
        photo.note = data.get("note", photo.note)
    else:
        if note is not None:
            photo.note = note
    
    db.commit()
    db.close()
    return {"ok": True}


@app.patch("/photos/{photo_id}/zip")
async def update_photo_zip(photo_id: int, data: dict = Body(None), zip_code: str = Form(None)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    
    if data:
        photo.zip_code = data.get("zip_code", photo.zip_code)
    else:
        if zip_code is not None:
            photo.zip_code = zip_code
    
    db.commit()
    db.close()
    return {"ok": True}


@app.patch("/photos/{photo_id}/profiles")
async def update_photo_profiles(photo_id: int, data: dict = Body(None), profile_ids: str = Form(None)):
    """Add or replace profiles associated with a pin."""
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    
    if data:
        profile_ids_list = data.get("profile_ids", [])
    else:
        # Parse comma-separated profile IDs from form
        profile_ids_list = [int(x.strip()) for x in profile_ids.split(",") if x.strip()] if profile_ids else []
    
    profiles = db.query(Profile).filter(Profile.id.in_(profile_ids_list)).all()
    photo.profiles = profiles
    db.commit()
    db.close()
    return {"ok": True}


@app.delete("/photos/{photo_id}")
def delete_photo(photo_id: int):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    filepath = photo.image_url.lstrip("/")
    if os.path.exists(filepath):
        os.remove(filepath)
    db.delete(photo)
    db.commit()
    db.close()
    return {"ok": True}


# ─── LOG ROUTE ────────────────────────────────────────────────────────────────

@app.get("/log")
def get_log(
    date:     Optional[str] = None,
    zip_code: Optional[str] = None,
    status:   Optional[str] = None,
    search:   Optional[str] = None,
):
    db = SessionLocal()
    query = db.query(Photo)

    if date:
        try:
            d = datetime.strptime(date, "%Y-%m-%d")
            query = query.filter(
                Photo.timestamp >= d.replace(hour=0, minute=0, second=0),
                Photo.timestamp <= d.replace(hour=23, minute=59, second=59),
            )
        except ValueError:
            pass

    if zip_code:
        query = query.filter(Photo.zip_code.ilike(f"%{zip_code}%"))

    photos = query.order_by(Photo.timestamp.desc()).all()
    result = []
    for ph in photos:
        d = _photo_dict(ph)
        # filter by service status after loading (needs profile data)
        if status and d["service_type"] != status:
            continue
        # filter by note text search
        if search and not (ph.note and search.lower() in ph.note.lower()):
            continue
        result.append(d)

    db.close()
    return result


# ─── EMAIL EXPORT ─────────────────────────────────────────────────────────────

@app.post("/export/email")
async def export_log_email(data: dict = Body(None), to: str = Form(None), records: str = Form(None)):
    """
    Send a log export to an email address.
    Supports both JSON body (mobile) and Form data (web)
    """
    # Support both formats
    if data:
        # JSON body from mobile
        to_email = data.get("to", "").strip()
        records_list = data.get("records", [])
    else:
        # Form data from web
        to_email = (to or "").strip()
        # Parse records from form (would be JSON string)
        try:
            records_list = json.loads(records) if records else []
        except:
            records_list = []

    if not to_email:
        raise HTTPException(status_code=422, detail="Email address required")

    # Build HTML table
    rows_html = ""
    for r in records_list:
        profiles = ", ".join(p["name"] for p in r.get("profiles", [])) or r.get("profile_name", "—")
        rows_html += f"""
        <tr>
          <td>{r.get('timestamp','—')}</td>
          <td>{profiles}</td>
          <td>{r.get('service_type','—').upper()}</td>
          <td>{r.get('zip_code','—')}</td>
          <td>{r.get('latitude',''):.4f}, {r.get('longitude',''):.4f}</td>
          <td>{r.get('note','—')}</td>
        </tr>"""

    html = f"""
    <html><body style="font-family:sans-serif;color:#0f172a;">
    <h2 style="color:#6366f1;">GeoTagging — Activity Log Export</h2>
    <p>Exported {len(records_list)} record(s) · All times in PST</p>
    <table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%;font-size:13px;">
      <thead style="background:#f1f5f9;">
        <tr>
          <th>Timestamp (PST)</th><th>Profile(s)</th><th>Status</th>
          <th>Zip</th><th>Location</th><th>Note</th>
        </tr>
      </thead>
      <tbody>{rows_html}</tbody>
    </table>
    <p style="margin-top:20px;color:#94a3b8;font-size:11px;">GeoTagging CRM · Exported {datetime.now(PST).strftime('%b %d, %Y %I:%M %p PST')}</p>
    </body></html>"""

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")

    if not smtp_host or not smtp_user:
        # Return the HTML as a download instead
        return {"ok": True, "message": "SMTP not configured — export data returned", "html": html, "count": len(records_list)}

    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"GeoTagging Log Export — {len(records_list)} records"
        msg["From"]    = smtp_user
        msg["To"]      = to_email
        msg.attach(MIMEText(html, "html"))

        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.sendmail(smtp_user, to_email, msg.as_string())

        return {"ok": True, "message": f"Log exported to {to_email}", "count": len(records_list)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Email send failed: {str(e)}")
        msg["From"]    = smtp_user
        msg["To"]      = to_email
        msg.attach(MIMEText(html, "html"))

        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.sendmail(smtp_user, to_email, msg.as_string())

        return {"ok": True, "message": f"Log exported to {to_email}", "count": len(records)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Email send failed: {str(e)}")
