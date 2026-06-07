from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Body, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Text, ForeignKey, Table, event
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from typing import Optional
import os, shutil, uuid, smtplib, json
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dotenv import load_dotenv

# Try importing sendgrid, will fail gracefully if not installed
try:
    from sendgrid import SendGridAPIClient
    from sendgrid.helpers.mail import Mail
except ImportError:
    SendGridAPIClient = None
    Mail = None

# F11: Excel generation (graceful fallback to CSV if openpyxl missing)
try:
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill
except ImportError:
    Workbook = None

import base64, io, csv as _csv

load_dotenv()

PST = ZoneInfo("America/Los_Angeles")

app = FastAPI()

origins = os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def rewrite_api_prefix(request: Request, call_next):
    if request.scope["path"].startswith("/api/"):
        request.scope["path"] = request.scope["path"][4:]
    return await call_next(request)


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
    """A Photo is one *attempt*. Attempts that share a location_group_id belong
    to the same master pin (see Feature 1 / nearby detection)."""
    __tablename__ = "photos"
    id        = Column(Integer, primary_key=True, index=True)
    image_url = Column(String)
    timestamp = Column(DateTime, default=datetime.utcnow)
    latitude  = Column(Float)
    longitude = Column(Float)
    zip_code  = Column(String, nullable=True)
    address   = Column(Text,   nullable=True)   # human-readable address
    note      = Column(Text,   nullable=True)
    # per-photo priority category: standard | special | next_day | asap
    category  = Column(String, nullable=True, default="standard")
    # legacy single profile_id kept for backward compat
    profile_id    = Column(Integer, nullable=True)
    is_favorited  = Column(Integer, nullable=False, default=0)

    # ── F1: master-pin grouping. NULL group means a standalone pin whose
    #    own id is its group root. Attempts appended to an existing pin
    #    copy that pin's location_group_id (or its id if none yet). ──
    location_group_id = Column(Integer, nullable=True, index=True)

    # ── F6: timestamp integrity ──
    taken_at           = Column(DateTime, nullable=True)  # device capture time
    original_timestamp = Column(DateTime, nullable=True)  # immutable copy of taken_at
    edited_timestamp   = Column(DateTime, nullable=True)  # last manual edit

    # ── F7: pay rate (whole dollars) ──
    pay_rate = Column(Integer, nullable=True)

    # ── F10: job lifecycle: open | completed | archived ──
    status       = Column(String, nullable=False, default="open")
    completed_at = Column(DateTime, nullable=True)

    # ── F8/F9: ownership for payouts/earnings ──
    user_id = Column(Integer, nullable=True)

    profiles      = relationship("Profile", secondary=pin_profile, back_populates="photos")


class User(Base):
    """Lightweight user record (no password wall for the demo — identity only,
    so attempts/payouts/earnings can be attributed)."""
    __tablename__ = "users"
    id         = Column(Integer, primary_key=True, index=True)
    email      = Column(String, unique=True, nullable=False)
    name       = Column(String, nullable=True)
    role       = Column(String, nullable=False, default="field")  # field | admin
    created_at = Column(DateTime, default=datetime.utcnow)


class EmailRecipient(Base):
    """F11: saved export recipients (5–10 per user)."""
    __tablename__ = "email_recipients"
    id      = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=True)
    label   = Column(String, nullable=True)
    email   = Column(String, nullable=False)


class PinDraft(Base):
    """F5: optional cloud backup of an in-progress pin."""
    __tablename__ = "pin_drafts"
    id         = Column(String, primary_key=True)   # client-generated uuid
    user_id    = Column(Integer, nullable=True)
    payload    = Column(Text, nullable=False)        # JSON blob
    updated_at = Column(DateTime, default=datetime.utcnow)


class TimestampEdit(Base):
    """F6: audit trail for every timestamp change."""
    __tablename__ = "timestamp_edits"
    id        = Column(Integer, primary_key=True, index=True)
    photo_id  = Column(Integer, ForeignKey("photos.id", ondelete="CASCADE"))
    old_value = Column(DateTime, nullable=True)
    new_value = Column(DateTime, nullable=True)
    edited_by = Column(Integer, nullable=True)
    edited_at = Column(DateTime, default=datetime.utcnow)


class PayoutPeriod(Base):
    """F8: finalized pay-period snapshot (live totals are aggregated on demand)."""
    __tablename__ = "payout_periods"
    id           = Column(Integer, primary_key=True, index=True)
    user_id      = Column(Integer, nullable=True)
    period_start = Column(DateTime, nullable=True)
    period_end   = Column(DateTime, nullable=True)
    total_amount = Column(Integer, nullable=True)
    jobs_count   = Column(Integer, nullable=True)
    finalized_at = Column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(bind=engine)


def _ensure_columns():
    """Lightweight SQLite migration: add columns introduced after the table
    was first created. create_all() never alters existing tables."""
    from sqlalchemy import text, inspect
    inspector = inspect(engine)
    existing = {c["name"] for c in inspector.get_columns("photos")}
    # column name -> DDL fragment to add it
    new_cols = {
        "category":           "VARCHAR DEFAULT 'standard'",
        "is_favorited":       "INTEGER NOT NULL DEFAULT 0",
        "location_group_id":  "INTEGER",
        "taken_at":           "DATETIME",
        "original_timestamp": "DATETIME",
        "edited_timestamp":   "DATETIME",
        "pay_rate":           "INTEGER",
        "status":             "VARCHAR NOT NULL DEFAULT 'open'",
        "completed_at":       "DATETIME",
        "user_id":            "INTEGER",
    }
    with engine.connect() as conn:
        for col, ddl in new_cols.items():
            if col not in existing:
                conn.execute(text(f"ALTER TABLE photos ADD COLUMN {col} {ddl}"))
                conn.commit()
        # Backfill timestamp-integrity + grouping columns for legacy rows
        conn.execute(text(
            "UPDATE photos SET taken_at = timestamp WHERE taken_at IS NULL"))
        conn.execute(text(
            "UPDATE photos SET original_timestamp = timestamp WHERE original_timestamp IS NULL"))
        conn.execute(text(
            "UPDATE photos SET location_group_id = id WHERE location_group_id IS NULL"))
        conn.execute(text(
            "UPDATE photos SET status = 'open' WHERE status IS NULL"))
        conn.commit()


_ensure_columns()


def _to_pst_iso(ts):
    if not ts:
        return None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return ts.astimezone(PST).isoformat()


def _haversine_ft(lat1, lon1, lat2, lon2):
    """Great-circle distance in feet between two lat/lng points."""
    from math import radians, sin, cos, sqrt, atan2
    R_ft = 20925524.9  # Earth radius in feet
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return R_ft * 2 * atan2(sqrt(a), sqrt(1 - a))


def _photo_dict(ph):
    profiles = [{"id": p.id, "name": p.name, "service_type": p.service_type} for p in ph.profiles]
    primary = profiles[0] if profiles else None
    return {
        "id":                 ph.id,
        "image_url":          ph.image_url,
        "timestamp":          _to_pst_iso(ph.timestamp),
        "taken_at":           _to_pst_iso(ph.taken_at),
        "original_timestamp": _to_pst_iso(ph.original_timestamp),
        "edited_timestamp":   _to_pst_iso(ph.edited_timestamp),
        "latitude":           ph.latitude,
        "longitude":          ph.longitude,
        "zip_code":           ph.zip_code,
        "address":            ph.address,
        "note":               ph.note,
        "category":           ph.category or "standard",
        "pay_rate":           ph.pay_rate,
        "status":             ph.status or "open",
        "completed_at":       _to_pst_iso(ph.completed_at),
        "user_id":            ph.user_id,
        "location_group_id":  ph.location_group_id or ph.id,
        "profile_id":         primary["id"]   if primary else ph.profile_id,
        "profile_name":       primary["name"] if primary else "Unknown",
        "service_type":       primary["service_type"] if primary else "standard",
        "profiles":           profiles,
        "is_favorited":       bool(ph.is_favorited),
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
    
    # Priority categories (+ legacy rush/airport kept for backward compat)
    if service_type not in (
        "standard", "special", "next_day", "asap", "rush", "airport"
    ):
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

    # Cascade: delete all photos that belong ONLY to this profile
    # (photos linked to multiple profiles are unlinked, not deleted)
    photos_to_delete = []
    for photo in list(profile.photos):
        if len(photo.profiles) == 1:
            # Only linked to this profile — delete the photo file + record
            photos_to_delete.append(photo)
        else:
            # Linked to other profiles too — just remove the association
            photo.profiles = [p for p in photo.profiles if p.id != profile_id]

    for photo in photos_to_delete:
        filepath = photo.image_url.lstrip("/")
        if os.path.exists(filepath):
            try:
                os.remove(filepath)
            except OSError:
                pass
        db.delete(photo)

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


def _parse_device_ts(s):
    """Parse a device-supplied ISO timestamp; return None on failure."""
    if not s:
        return None
    s = s.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M",
                "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            return datetime.strptime(s.replace("Z", "").split("+")[0], fmt)
        except ValueError:
            continue
    return None


@app.post("/upload")
async def upload_photo(
    file:              UploadFile = File(...),
    profile_id:        int        = Form(...),
    latitude:          float      = Form(...),
    longitude:         float      = Form(...),
    zip_code:          str        = Form(""),
    address:           str        = Form(""),
    note:              str        = Form(""),
    category:          str        = Form("standard"),
    taken_at:          str        = Form(""),    # F6: device capture time (ISO)
    pay_rate:          str        = Form(""),     # F7: whole dollars
    user_id:           str        = Form(""),     # F8/F9: attribution
    location_group_id: str        = Form(""),     # F1: append to existing master pin
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

    # F6: lock timestamp to device capture time when provided; the upload time
    # is no longer authoritative. original_timestamp is the immutable record.
    device_ts = _parse_device_ts(taken_at) or datetime.utcnow()

    # F7: parse whole-dollar pay rate
    pay_val = None
    if pay_rate.strip():
        try:
            pay_val = int(round(float(pay_rate.strip())))
        except ValueError:
            pay_val = None

    uid = int(user_id) if user_id.strip().isdigit() else None
    grp = int(location_group_id) if location_group_id.strip().isdigit() else None

    photo = Photo(
        image_url          = f"/uploads/{filename}",
        timestamp          = device_ts,
        taken_at           = device_ts,
        original_timestamp = device_ts,
        latitude           = latitude,
        longitude          = longitude,
        zip_code           = zip_code.strip() or None,
        address            = address.strip()  or None,
        note               = note.strip()     or None,
        category           = (category.strip().lower()
                              if category.strip().lower() in
                              ("standard", "special", "next_day", "asap")
                              else "standard"),
        pay_rate           = pay_val,
        user_id            = uid,
        status             = "open",
        profile_id         = profile_id,
    )
    photo.profiles = [profile]
    db.add(photo)
    db.commit()
    db.refresh(photo)
    # F1: if appending to an existing master pin use its group; else the row is
    # its own group root.
    photo.location_group_id = grp if grp else photo.id
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


@app.patch("/photos/{photo_id}/address")
async def update_photo_address(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    photo.address  = data.get("address",  photo.address)
    photo.zip_code = data.get("zip_code", photo.zip_code)
    db.commit()
    db.close()
    return {"ok": True}


@app.patch("/photos/{photo_id}/category")
async def update_photo_category(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    cat = (data.get("category") or "standard").strip().lower()
    if cat not in ("standard", "special", "next_day", "asap"):
        cat = "standard"
    photo.category = cat
    db.commit()
    db.close()
    return {"ok": True, "category": cat}


@app.patch("/photos/{photo_id}/favorite")
async def toggle_favorite(photo_id: int):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    new_val = 0 if photo.is_favorited else 1
    photo.is_favorited = new_val
    db.commit()
    db.close()
    return {"ok": True, "is_favorited": bool(new_val)}


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
    date:       Optional[str] = None,
    start_time: Optional[str] = None,   # ISO datetime or "YYYY-MM-DD HH:MM"
    end_time:   Optional[str] = None,   # ISO datetime or "YYYY-MM-DD HH:MM"
    zip_code:   Optional[str] = None,
    status:     Optional[str] = None,
    search:     Optional[str] = None,
):
    db = SessionLocal()
    query = db.query(Photo)

    # ── Time range filtering ──────────────────────────────────────────────
    if start_time or end_time:
        # Explicit time range takes priority over date-only filter
        def _parse_dt(s):
            for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
                try:
                    return datetime.strptime(s, fmt)
                except ValueError:
                    continue
            return None

        if start_time:
            dt_start = _parse_dt(start_time)
            if dt_start:
                query = query.filter(Photo.timestamp >= dt_start)
        if end_time:
            dt_end = _parse_dt(end_time)
            if dt_end:
                # If only date provided (no time), extend to end of that day
                if "T" not in end_time and " " not in end_time.strip():
                    dt_end = dt_end.replace(hour=23, minute=59, second=59)
                query = query.filter(Photo.timestamp <= dt_end)
    elif date:
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
        # filter by note text search — also matches profile names, zip, and address
        if search:
            s = search.lower()
            note_match    = ph.note    and s in ph.note.lower()
            address_match = ph.address and s in ph.address.lower()
            profile_match = any(s in p["name"].lower() for p in d["profiles"])
            zip_match     = ph.zip_code and s in ph.zip_code.lower()
            if not (note_match or address_match or profile_match or zip_match):
                continue
        result.append(d)

    db.close()
    return result


# ─── EMAIL EXPORT ─────────────────────────────────────────────────────────────

@app.post("/export/email")
async def export_log_email(request: Request):
    """
    Send a log export to an email address.
    Supports both JSON body (mobile) and Form data (web)
    """
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        data = await request.json()
        to_email = data.get("to", "").strip()
        records_list = data.get("records", [])
    else:
        form = await request.form()
        to_email = (form.get("to") or "").strip()
        try:
            records_list = json.loads(form.get("records", "[]"))
        except Exception:
            records_list = []

    if not to_email:
        raise HTTPException(status_code=422, detail="Email address required")

    # Category display metadata: label + colour
    _CATEGORY_META = {
        "standard": ("Standard", "#059669"),
        "special":  ("Special",  "#EA580C"),
        "next_day": ("Next Day", "#CA8A04"),
        "asap":     ("ASAP",     "#DC2626"),
    }

    # Build HTML table
    rows_html = ""
    for r in records_list:
        cat_label, cat_color = _CATEGORY_META.get(
            (r.get("category") or "standard").lower(),
            _CATEGORY_META["standard"],
        )
        profiles = ", ".join(p["name"] for p in r.get("profiles", [])) or r.get("profile_name", "—")
        lat = r.get('latitude', '')
        lng = r.get('longitude', '')
        coords = f"{lat:.4f}, {lng:.4f}" if isinstance(lat, (int, float)) and isinstance(lng, (int, float)) else "—"
        address = r.get('address') or "—"
        zip_val = r.get('zip_code') or "—"
        # Format address inline with ZIP
        if r.get('address') and r.get('zip_code') and r['zip_code'] not in r['address']:
            address = f"{r['address']}, {r['zip_code']}"
        elif r.get('address'):
            address = r['address']
        rows_html += f"""
        <tr>
          <td>{r.get('timestamp','—')}</td>
          <td>{profiles}</td>
          <td>{r.get('service_type','—').upper()}</td>
          <td><span style="color:{cat_color};font-weight:700;">{cat_label}</span></td>
          <td>{address}</td>
          <td>{coords}</td>
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
          <th>Category</th><th>Address</th><th>Coordinates</th><th>Note</th>
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
    
    sg_api_key = os.environ.get("SENDGRID_API_KEY")
    sg_sender = os.environ.get("SENDGRID_SENDER_EMAIL")

    if not sg_api_key and (not smtp_host or not smtp_user):
        # Return the HTML as a download instead
        return {"ok": True, "message": "Email not configured — export data returned", "html": html, "count": len(records_list)}

    try:
        # Use SendGrid if configured
        if sg_api_key and SendGridAPIClient and Mail:
            if not sg_sender:
                raise HTTPException(status_code=500, detail="SENDGRID_SENDER_EMAIL is required in environment variables when using SendGrid.")
                
            message = Mail(
                from_email=sg_sender,
                to_emails=to_email,
                subject=f"GeoTagging Log Export — {len(records_list)} records",
                html_content=html
            )
            sg = SendGridAPIClient(sg_api_key)
            sg.send(message)
            return {"ok": True, "message": f"Log exported to {to_email} via SendGrid", "count": len(records_list)}
            
        # Fallback to standard SMTP (e.g. Ethereal Testing)
        else:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = f"GeoTagging Log Export — {len(records_list)} records"
            msg["From"]    = smtp_user
            msg["To"]      = to_email
            msg.attach(MIMEText(html, "html"))

            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, to_email, msg.as_string())

            return {"ok": True, "message": f"Log exported to {to_email} via SMTP", "count": len(records_list)}
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Email send failed: {str(e)}")


# ════════════════════════════════════════════════════════════════════════════
#  ENHANCEMENT FEATURES (F1–F11)
# ════════════════════════════════════════════════════════════════════════════

# Service-level / scheduling metadata
_SERVICE_LEVELS = ("asap", "next_day", "standard", "special")
_PRIORITY = {"asap": 0, "next_day": 1, "special": 2, "standard": 3}
_NEARBY_DEFAULT_FT = 100.0


def _group_key(ph):
    return ph.location_group_id or ph.id


def _master_pin_dict(group_photos):
    """Collapse a list of attempt-Photos sharing a group into one master pin."""
    attempts = sorted(group_photos, key=lambda p: p.id)
    root = attempts[0]
    statuses = {p.status or "open" for p in attempts}
    if statuses == {"archived"}:
        status = "archived"
    elif "open" in statuses:
        status = "open"
    else:
        status = "completed"
    pay = next((p.pay_rate for p in attempts if p.pay_rate is not None), None)
    return {
        "location_group_id": _group_key(root),
        "latitude":          root.latitude,
        "longitude":         root.longitude,
        "address":           root.address,
        "zip_code":          root.zip_code,
        "service_level":     root.category or "standard",
        "pay_rate":          pay,
        "status":            status,
        "attempt_count":     len(attempts),
        "first_attempt_at":  _to_pst_iso(root.original_timestamp or root.timestamp),
        "last_attempt_at":   _to_pst_iso(attempts[-1].timestamp),
        "attempts":          [_photo_dict(p) for p in attempts],
    }


def _all_master_pins(db):
    photos = db.query(Photo).all()
    groups = {}
    for ph in photos:
        groups.setdefault(_group_key(ph), []).append(ph)
    return [_master_pin_dict(g) for g in groups.values()]


# ─── F1: DUPLICATE DETECTION / EXISTING PIN REUSE ───────────────────────────

@app.get("/locations/nearby")
def nearby_locations(lat: float, lng: float, radius_ft: float = _NEARBY_DEFAULT_FT):
    """Return existing master pins within `radius_ft` feet of (lat, lng)."""
    db = SessionLocal()
    pins = _all_master_pins(db)
    db.close()
    out = []
    for pin in pins:
        if pin["latitude"] is None or pin["longitude"] is None:
            continue
        dist = _haversine_ft(lat, lng, pin["latitude"], pin["longitude"])
        if dist <= radius_ft:
            pin["distance_ft"] = round(dist, 1)
            out.append(pin)
    out.sort(key=lambda p: p["distance_ft"])
    return out


@app.get("/locations")
def list_locations(service_levels: Optional[str] = None, status: Optional[str] = None):
    """Master-pin list with optional service-level (comma list) + status filters."""
    db = SessionLocal()
    pins = _all_master_pins(db)
    db.close()
    if service_levels:
        wanted = {s.strip().lower() for s in service_levels.split(",") if s.strip()}
        pins = [p for p in pins if p["service_level"] in wanted]
    if status:
        pins = [p for p in pins if p["status"] == status]
    return pins


@app.get("/locations/{group_id}/attempts")
def location_attempts(group_id: int):
    """Full attempt history / timeline for one master pin."""
    db = SessionLocal()
    photos = db.query(Photo).filter(
        (Photo.location_group_id == group_id) | (Photo.id == group_id)
    ).all()
    if not photos:
        db.close()
        raise HTTPException(status_code=404, detail="Location not found")
    result = _master_pin_dict(photos)   # build while session is open (lazy profiles)
    db.close()
    return result


# ─── F4: SERVICE-LEVEL SCHEDULING QUEUES ────────────────────────────────────

@app.get("/schedule")
def get_schedule(queue: Optional[str] = None):
    """Scheduling queues derived from service level. queue ∈ service levels."""
    db = SessionLocal()
    pins = [p for p in _all_master_pins(db) if p["status"] != "archived"]
    db.close()
    if queue:
        q = queue.strip().lower()
        pins = [p for p in pins if p["service_level"] == q]
    for p in pins:
        p["priority"] = _PRIORITY.get(p["service_level"], 3)
    pins.sort(key=lambda p: (p["priority"], p["first_attempt_at"] or ""))
    # Group into named queues for convenience
    queues = {lvl: [] for lvl in _SERVICE_LEVELS}
    for p in pins:
        queues.setdefault(p["service_level"], []).append(p)
    return {"queues": queues, "items": pins}


# ─── F6: TIMESTAMP EDIT (10-MIN WINDOW) + AUDIT ─────────────────────────────

_EDIT_WINDOW_MIN = 10


@app.patch("/photos/{photo_id}/timestamp")
async def edit_timestamp(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    # Window is measured from original capture/creation time
    anchor = photo.original_timestamp or photo.timestamp or datetime.utcnow()
    age_min = (datetime.utcnow() - anchor).total_seconds() / 60
    if age_min > _EDIT_WINDOW_MIN:
        db.close()
        raise HTTPException(status_code=423,
                            detail=f"Timestamp locked — edit window of {_EDIT_WINDOW_MIN} min elapsed")
    new_ts = _parse_device_ts(data.get("timestamp"))
    if not new_ts:
        db.close()
        raise HTTPException(status_code=422, detail="Valid 'timestamp' (ISO) required")
    old = photo.timestamp
    photo.timestamp = new_ts
    photo.edited_timestamp = new_ts
    db.add(TimestampEdit(photo_id=photo.id, old_value=old, new_value=new_ts,
                         edited_by=data.get("user_id")))
    db.commit()
    db.close()
    return {"ok": True, "timestamp": _to_pst_iso(new_ts)}


@app.get("/photos/{photo_id}/timestamp-history")
def timestamp_history(photo_id: int):
    db = SessionLocal()
    edits = db.query(TimestampEdit).filter(TimestampEdit.photo_id == photo_id).order_by(
        TimestampEdit.edited_at).all()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    result = {
        "photo_id":           photo_id,
        "original_timestamp": _to_pst_iso(photo.original_timestamp) if photo else None,
        "current_timestamp":  _to_pst_iso(photo.timestamp) if photo else None,
        "edits": [{
            "old_value": _to_pst_iso(e.old_value),
            "new_value": _to_pst_iso(e.new_value),
            "edited_by": e.edited_by,
            "edited_at": _to_pst_iso(e.edited_at),
        } for e in edits],
    }
    db.close()
    return result


# ─── F7: PAY RATE ───────────────────────────────────────────────────────────

@app.patch("/photos/{photo_id}/pay-rate")
async def update_pay_rate(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    try:
        photo.pay_rate = int(round(float(data.get("pay_rate"))))
    except (TypeError, ValueError):
        db.close()
        raise HTTPException(status_code=422, detail="pay_rate must be a whole dollar number")
    db.commit()
    pay_val = photo.pay_rate
    db.close()
    return {"ok": True, "pay_rate": pay_val}


# ─── F10: ARCHIVE / JOB STATUS WORKFLOW ─────────────────────────────────────

@app.patch("/photos/{photo_id}/status")
async def update_status(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    st = (data.get("status") or "").strip().lower()
    if st not in ("open", "completed", "archived"):
        db.close()
        raise HTTPException(status_code=422, detail="status must be open|completed|archived")
    photo.status = st
    if st == "completed" and not photo.completed_at:
        photo.completed_at = datetime.utcnow()
    db.commit()
    db.close()
    return {"ok": True, "status": st}


@app.get("/archive")
def get_archive(search: Optional[str] = None, service_level: Optional[str] = None):
    """Archived jobs with search + service-level filter."""
    db = SessionLocal()
    photos = db.query(Photo).filter(Photo.status == "archived").order_by(
        Photo.timestamp.desc()).all()
    result = []
    for ph in photos:
        d = _photo_dict(ph)   # build while session is open (lazy profiles)
        if service_level and d["category"] != service_level:
            continue
        if search:
            s = search.lower()
            hay = " ".join(str(x or "") for x in
                           [ph.note, ph.address, ph.zip_code,
                            *[p["name"] for p in d["profiles"]]]).lower()
            if s not in hay:
                continue
        result.append(d)
    db.close()
    return result


# ─── F8 / F9: EARNINGS + PAYOUTS / TIMESHEETS ───────────────────────────────

def _period_bounds(period):
    """Return (start_utc, label) for today|week|biweekly|month."""
    now = datetime.now(PST)
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "today":
        start = today
    elif period == "week":
        start = today - timedelta(days=today.weekday())
    elif period == "biweekly":
        start = today - timedelta(days=14)
    elif period == "month":
        start = today.replace(day=1)
    else:
        start = today
    return start.astimezone(timezone.utc).replace(tzinfo=None)


@app.get("/earnings/summary")
def earnings_summary(period: str = "today", user_id: Optional[int] = None):
    """Aggregate completed-job earnings for the period (Uber-style)."""
    start = _period_bounds(period)
    db = SessionLocal()
    q = db.query(Photo).filter(Photo.status == "completed",
                               Photo.completed_at >= start)
    if user_id is not None:
        q = q.filter(Photo.user_id == user_id)
    jobs = q.all()
    db.close()
    total = sum((j.pay_rate or 0) for j in jobs)
    count = len(jobs)
    # daily breakdown for trend chart
    daily = {}
    for j in jobs:
        day = (_to_pst_iso(j.completed_at) or "")[:10]
        daily[day] = daily.get(day, 0) + (j.pay_rate or 0)
    return {
        "period":          period,
        "jobs_completed":  count,
        "total_earnings":  total,
        "average_per_job": round(total / count, 2) if count else 0,
        "daily_totals":    [{"date": d, "amount": a} for d, a in sorted(daily.items())],
    }


@app.get("/payouts")
def get_payouts(user_id: Optional[int] = None):
    """Closed jobs with running earnings, grouped by completion day."""
    db = SessionLocal()
    q = db.query(Photo).filter(Photo.status == "completed")
    if user_id is not None:
        q = q.filter(Photo.user_id == user_id)
    jobs = q.order_by(Photo.completed_at.desc()).all()
    db.close()
    days = {}
    for j in jobs:
        day = (_to_pst_iso(j.completed_at) or "")[:10]
        days.setdefault(day, {"date": day, "jobs": 0, "amount": 0})
        days[day]["jobs"] += 1
        days[day]["amount"] += (j.pay_rate or 0)
    daily = sorted(days.values(), key=lambda d: d["date"], reverse=True)
    return {
        "total_earnings": sum(d["amount"] for d in daily),
        "total_jobs":     sum(d["jobs"] for d in daily),
        "daily":          daily,
    }


@app.post("/payouts/finalize")
async def finalize_payout(data: dict = Body(...)):
    """Snapshot a pay period so historical totals don't drift."""
    db = SessionLocal()
    start = _parse_device_ts(data.get("period_start"))
    end = _parse_device_ts(data.get("period_end"))
    uid = data.get("user_id")
    q = db.query(Photo).filter(Photo.status == "completed")
    if uid is not None:
        q = q.filter(Photo.user_id == uid)
    if start:
        q = q.filter(Photo.completed_at >= start)
    if end:
        q = q.filter(Photo.completed_at <= end)
    jobs = q.all()
    snap = PayoutPeriod(
        user_id=uid, period_start=start, period_end=end,
        total_amount=sum((j.pay_rate or 0) for j in jobs), jobs_count=len(jobs))
    db.add(snap)
    db.commit()
    db.refresh(snap)
    out = {"id": snap.id, "total_amount": snap.total_amount, "jobs_count": snap.jobs_count}
    db.close()
    return out


# ─── F5: DRAFT AUTO-SAVE ────────────────────────────────────────────────────

@app.put("/drafts")
async def save_draft(data: dict = Body(...)):
    """Upsert a pin draft (continuous autosave from mobile)."""
    draft_id = (data.get("id") or str(uuid.uuid4()))
    db = SessionLocal()
    draft = db.query(PinDraft).filter(PinDraft.id == draft_id).first()
    if not draft:
        draft = PinDraft(id=draft_id)
        db.add(draft)
    draft.user_id    = data.get("user_id")
    draft.payload    = json.dumps(data.get("payload", {}))
    draft.updated_at = datetime.utcnow()
    db.commit()
    db.close()
    return {"ok": True, "id": draft_id}


@app.get("/drafts")
def list_drafts(user_id: Optional[int] = None):
    db = SessionLocal()
    q = db.query(PinDraft)
    if user_id is not None:
        q = q.filter(PinDraft.user_id == user_id)
    drafts = q.order_by(PinDraft.updated_at.desc()).all()
    out = [{"id": d.id, "user_id": d.user_id,
            "payload": json.loads(d.payload or "{}"),
            "updated_at": _to_pst_iso(d.updated_at)} for d in drafts]
    db.close()
    return out


@app.delete("/drafts/{draft_id}")
def delete_draft(draft_id: str):
    db = SessionLocal()
    draft = db.query(PinDraft).filter(PinDraft.id == draft_id).first()
    if draft:
        db.delete(draft)
        db.commit()
    db.close()
    return {"ok": True}


# ─── F11: SAVED EMAIL RECIPIENTS ────────────────────────────────────────────

@app.get("/recipients")
def list_recipients(user_id: Optional[int] = None):
    db = SessionLocal()
    q = db.query(EmailRecipient)
    if user_id is not None:
        q = q.filter(EmailRecipient.user_id == user_id)
    rows = q.all()
    out = [{"id": r.id, "label": r.label, "email": r.email, "user_id": r.user_id} for r in rows]
    db.close()
    return out


@app.post("/recipients")
async def add_recipient(data: dict = Body(...)):
    email = (data.get("email") or "").strip()
    if "@" not in email:
        raise HTTPException(status_code=422, detail="Valid email required")
    db = SessionLocal()
    # cap at 10 per user
    uid = data.get("user_id")
    count = db.query(EmailRecipient).filter(EmailRecipient.user_id == uid).count()
    if count >= 10:
        db.close()
        raise HTTPException(status_code=422, detail="Maximum of 10 saved recipients reached")
    r = EmailRecipient(user_id=uid, label=(data.get("label") or "").strip() or None, email=email)
    db.add(r)
    db.commit()
    db.refresh(r)
    out = {"id": r.id, "label": r.label, "email": r.email}
    db.close()
    return out


@app.patch("/recipients/{rid}")
async def edit_recipient(rid: int, data: dict = Body(...)):
    db = SessionLocal()
    r = db.query(EmailRecipient).filter(EmailRecipient.id == rid).first()
    if not r:
        db.close()
        raise HTTPException(status_code=404, detail="Recipient not found")
    if "email" in data:
        r.email = data["email"].strip()
    if "label" in data:
        r.label = (data["label"] or "").strip() or None
    db.commit()
    out = {"id": r.id, "label": r.label, "email": r.email}
    db.close()
    return out


@app.delete("/recipients/{rid}")
def delete_recipient(rid: int):
    db = SessionLocal()
    r = db.query(EmailRecipient).filter(EmailRecipient.id == rid).first()
    if r:
        db.delete(r)
        db.commit()
    db.close()
    return {"ok": True}


# ─── F11: EXCEL EXPORT (replaces multi-format exports) ──────────────────────

_EXPORT_COLUMNS = [
    ("timestamp",    "Timestamp (PST)"),
    ("profile_name", "Profile"),
    ("service_type", "Status"),
    ("category",     "Service Level"),
    ("pay_rate",     "Pay Rate ($)"),
    ("address",      "Address"),
    ("zip_code",     "ZIP"),
    ("latitude",     "Latitude"),
    ("longitude",    "Longitude"),
    ("note",         "Note"),
]


def _build_xlsx(records):
    """Return (bytes, filename) for an .xlsx of the records."""
    if Workbook is None:
        # Fallback: CSV bytes
        buf = io.StringIO()
        w = _csv.writer(buf)
        w.writerow([h for _, h in _EXPORT_COLUMNS])
        for r in records:
            w.writerow([r.get(k, "") for k, _ in _EXPORT_COLUMNS])
        return buf.getvalue().encode(), "log_export.csv"
    wb = Workbook()
    ws = wb.active
    ws.title = "Activity Log"
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill("solid", fgColor="6366F1")
    for col, (_, label) in enumerate(_EXPORT_COLUMNS, start=1):
        c = ws.cell(row=1, column=col, value=label)
        c.font = header_font
        c.fill = header_fill
    for ri, r in enumerate(records, start=2):
        for ci, (key, _) in enumerate(_EXPORT_COLUMNS, start=1):
            val = r.get(key, "")
            if key == "category":
                val = str(val).replace("_", " ").title()
            ws.cell(row=ri, column=ci, value=val)
    for col in range(1, len(_EXPORT_COLUMNS) + 1):
        ws.column_dimensions[chr(64 + col)].width = 18
    bio = io.BytesIO()
    wb.save(bio)
    return bio.getvalue(), "log_export.xlsx"


@app.post("/export/excel")
async def export_excel(request: Request):
    """Generate an Excel file and email it to one or more recipients."""
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        data = await request.json()
        recipients = data.get("recipients") or ([data["to"]] if data.get("to") else [])
        records = data.get("records", [])
    else:
        form = await request.form()
        recipients = json.loads(form.get("recipients", "[]")) or (
            [form.get("to")] if form.get("to") else [])
        try:
            records = json.loads(form.get("records", "[]"))
        except Exception:
            records = []

    recipients = [e.strip() for e in recipients if e and "@" in e]
    if not recipients:
        raise HTTPException(status_code=422, detail="At least one recipient email required")

    file_bytes, fname = _build_xlsx(records)
    b64 = base64.b64encode(file_bytes).decode()

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    sg_api_key = os.environ.get("SENDGRID_API_KEY")
    sg_sender = os.environ.get("SENDGRID_SENDER_EMAIL")

    if not sg_api_key and (not smtp_host or not smtp_user):
        # Not configured: return the file as base64 for client download
        return {"ok": True, "message": "Email not configured — file returned",
                "filename": fname, "file_base64": b64, "count": len(records)}

    subject = f"GeoTagging Excel Export — {len(records)} records"
    try:
        if sg_api_key and SendGridAPIClient and Mail:
            from sendgrid.helpers.mail import Attachment, FileContent, FileName, FileType, Disposition
            message = Mail(from_email=sg_sender, to_emails=recipients,
                           subject=subject,
                           html_content=f"<p>{len(records)} record(s) attached.</p>")
            message.attachment = Attachment(
                FileContent(b64), FileName(fname),
                FileType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
                Disposition("attachment"))
            SendGridAPIClient(sg_api_key).send(message)
            return {"ok": True, "message": f"Excel sent to {', '.join(recipients)}",
                    "count": len(records)}
        else:
            from email.mime.application import MIMEApplication
            msg = MIMEMultipart()
            msg["Subject"] = subject
            msg["From"] = smtp_user
            msg["To"] = ", ".join(recipients)
            msg.attach(MIMEText(f"{len(records)} record(s) attached.", "plain"))
            part = MIMEApplication(file_bytes, _subtype="vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            part.add_header("Content-Disposition", "attachment", filename=fname)
            msg.attach(part)
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, recipients, msg.as_string())
            return {"ok": True, "message": f"Excel sent to {', '.join(recipients)}",
                    "count": len(records)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Excel export failed: {str(e)}")


# ─── USERS (lightweight identity for attribution) ───────────────────────────

@app.get("/users")
def list_users():
    db = SessionLocal()
    users = db.query(User).all()
    out = [{"id": u.id, "email": u.email, "name": u.name, "role": u.role} for u in users]
    db.close()
    return out


@app.post("/users")
async def create_user(data: dict = Body(...)):
    email = (data.get("email") or "").strip()
    if "@" not in email:
        raise HTTPException(status_code=422, detail="Valid email required")
    db = SessionLocal()
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        out = {"id": existing.id, "email": existing.email, "name": existing.name, "role": existing.role}
        db.close()
        return out
    u = User(email=email, name=(data.get("name") or "").strip() or None,
             role=data.get("role", "field"))
    db.add(u)
    db.commit()
    db.refresh(u)
    out = {"id": u.id, "email": u.email, "name": u.name, "role": u.role}
    db.close()
    return out
