from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime
import os, shutil, uuid

app = FastAPI()

# Allow both localhost (dev) and Vercel frontend (prod)
origins = os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# DB setup
DATABASE_URL = "sqlite:///./photo_tracker.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


class Profile(Base):
    __tablename__ = "profiles"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    service_type = Column(String, default="standard")  # standard or rush


class Photo(Base):
    __tablename__ = "photos"
    id = Column(Integer, primary_key=True, index=True)
    image_url = Column(String)
    timestamp = Column(DateTime, default=datetime.utcnow)
    latitude = Column(Float)
    longitude = Column(Float)
    profile_id = Column(Integer)


Base.metadata.create_all(bind=engine)


def seed_data():
    db = SessionLocal()
    if db.query(Profile).count() == 0:
        profiles = [
            Profile(name="Alice Johnson", service_type="standard"),
            Profile(name="Bob Rush", service_type="rush"),
            Profile(name="Carol Standard", service_type="standard"),
            Profile(name="Dave Express", service_type="rush"),
        ]
        db.add_all(profiles)
        db.commit()

        photos = [
            Photo(image_url="/uploads/sample1.jpg", timestamp=datetime(2026, 4, 20, 10, 30),
                  latitude=37.7749, longitude=-122.4194, profile_id=1),
            Photo(image_url="/uploads/sample2.jpg", timestamp=datetime(2026, 4, 21, 14, 15),
                  latitude=37.7849, longitude=-122.4094, profile_id=2),
            Photo(image_url="/uploads/sample3.jpg", timestamp=datetime(2026, 4, 22, 9, 0),
                  latitude=37.7649, longitude=-122.4294, profile_id=3),
            Photo(image_url="/uploads/sample4.jpg", timestamp=datetime(2026, 4, 23, 16, 45),
                  latitude=37.7949, longitude=-122.3994, profile_id=4),
        ]
        db.add_all(photos)
        db.commit()
    db.close()


seed_data()


# --- ROUTES ---

@app.get("/profiles")
def get_profiles():
    db = SessionLocal()
    profiles = db.query(Profile).all()
    db.close()
    return [{"id": p.id, "name": p.name, "service_type": p.service_type} for p in profiles]


@app.post("/profiles")
def create_profile(name: str = Form(...), service_type: str = Form("standard")):
    db = SessionLocal()
    profile = Profile(name=name, service_type=service_type)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    db.close()
    return {"id": profile.id, "name": profile.name, "service_type": profile.service_type}


@app.get("/photos")
def get_photos():
    db = SessionLocal()
    photos = db.query(Photo).all()
    profiles = {p.id: p for p in db.query(Profile).all()}
    db.close()
    result = []
    for ph in photos:
        profile = profiles.get(ph.profile_id)
        result.append({
            "id": ph.id,
            "image_url": ph.image_url,
            "timestamp": ph.timestamp.isoformat() if ph.timestamp else None,
            "latitude": ph.latitude,
            "longitude": ph.longitude,
            "profile_id": ph.profile_id,
            "profile_name": profile.name if profile else "Unknown",
            "service_type": profile.service_type if profile else "standard",
        })
    return result


@app.post("/upload")
async def upload_photo(
    file: UploadFile = File(...),
    profile_id: int = Form(...),
    latitude: float = Form(...),
    longitude: float = Form(...),
):
    ext = os.path.splitext(file.filename)[1] or ".jpg"
    filename = f"{uuid.uuid4()}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    with open(filepath, "wb") as f:
        shutil.copyfileobj(file.file, f)

    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")

    # Capture profile values as plain strings BEFORE any commit expires the object
    profile_name = str(profile.name)
    service_type = str(profile.service_type)

    photo = Photo(
        image_url=f"/uploads/{filename}",
        timestamp=datetime.utcnow(),
        latitude=latitude,
        longitude=longitude,
        profile_id=profile_id,
    )
    db.add(photo)
    db.commit()
    db.refresh(photo)

    result = {
        "id": photo.id,
        "image_url": photo.image_url,
        "timestamp": photo.timestamp.isoformat(),
        "latitude": photo.latitude,
        "longitude": photo.longitude,
        "profile_id": photo.profile_id,
        "profile_name": profile_name,
        "service_type": service_type,
    }
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


@app.delete("/photos/{photo_id}")
def delete_photo(photo_id: int):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    # Remove file from disk
    filepath = photo.image_url.lstrip("/")
    if os.path.exists(filepath):
        os.remove(filepath)
    db.delete(photo)
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
    # Delete all photos for this profile too
    photos = db.query(Photo).filter(Photo.profile_id == profile_id).all()
    for photo in photos:
        filepath = photo.image_url.lstrip("/")
        if os.path.exists(filepath):
            os.remove(filepath)
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
    photos = db.query(Photo).filter(Photo.profile_id == profile_id).all()
    db.close()
    return {
        "profile": {"id": profile.id, "name": profile.name, "service_type": profile.service_type},
        "photos": [
            {
                "id": ph.id,
                "image_url": ph.image_url,
                "timestamp": ph.timestamp.isoformat() if ph.timestamp else None,
                "latitude": ph.latitude,
                "longitude": ph.longitude,
            }
            for ph in photos
        ],
    }
