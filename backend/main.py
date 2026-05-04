from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Text, ForeignKey, Table
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
from typing import Optional
import os, shutil, uuid

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
    # fallback: if no m2m profiles yet, use legacy profile_id
    primary = profiles[0] if profiles else None
    return {
        "id":           ph.id,
        "image_url":    ph.image_url,
        "timestamp":    ph.timestamp.isoformat() if ph.timestamp else None,
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
def create_profile(name: str = Form(...), service_type: str = Form("standard")):
    db = SessionLocal()
    profile = Profile(name=name, service_type=service_type)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    db.close()
    return {"id": profile.id, "name": profile.name, "service_type": profile.service_type}


@app.patch("/profiles/{profile_id}")
def update_profile(profile_id: int, data: dict):
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
    db.close()
    return {"ok": True}


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


@app.patch("/photos/{photo_id}/location")
def update_photo_location(photo_id: int, data: dict):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    photo.latitude  = data.get("latitude",  photo.latitude)
    photo.longitude = data.get("longitude", photo.longitude)
    db.commit()
    db.close()
    return {"ok": True}


@app.patch("/photos/{photo_id}/note")
def update_photo_note(photo_id: int, data: dict):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    photo.note = data.get("note", photo.note)
    db.commit()
    db.close()
    return {"ok": True}


@app.patch("/photos/{photo_id}/profiles")
def update_photo_profiles(photo_id: int, data: dict):
    """Add or replace profiles associated with a pin."""
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    profile_ids = data.get("profile_ids", [])
    profiles = db.query(Profile).filter(Profile.id.in_(profile_ids)).all()
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
