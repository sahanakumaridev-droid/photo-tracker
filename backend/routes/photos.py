"""Photo listing, upload, watermarking, and metadata update routes."""

from __future__ import annotations

from datetime import datetime
import os
import shutil
from typing import Optional
import uuid

from fastapi import APIRouter, Body, File, Form, HTTPException, UploadFile
from fastapi.responses import Response

from companies import (
    DEFAULT_COMPANY_ID,
    company_allows_priority,
    default_priority_for_company,
)
from database import SessionLocal, UPLOAD_DIR
from models import Attempt, Photo, Profile
from serializers import (
    _attempt_dict,
    _feet_between,
    _haversine_ft,
    _in_united_states,
    _inherited_file_number,
    _is_absent_file_number,
    _parse_device_ts,
    _photo_dict,
    _resolve_attempt_status_input,
)
from services.profile_service import (
    _advance_profile_status,
    _profile_blocks_new_attempts,
)
from services.watermark_service import _photo_caption, _watermark_photo_png

router = APIRouter()


@router.get("/photos/{photo_id}/watermarked")
def watermarked_photo(photo_id: int, max_w: int = 1600, max_h: int = 1600):
    """Return the photo with its timestamp + geotag watermark burned in."""
    db = SessionLocal()
    ph = db.query(Photo).filter(Photo.id == photo_id).first()
    if not ph or not ph.image_url:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    caption = _photo_caption(ph)
    path = ph.image_url.lstrip("/")
    db.close()
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Image file missing")
    stamped = _watermark_photo_png(path, caption, max_w=max_w, max_h=max_h)
    if stamped:
        return Response(content=stamped[0], media_type="image/png")
    with open(path, "rb") as f:
        return Response(content=f.read(), media_type="image/jpeg")


@router.get("/photos")
def get_photos(
    user_lat: Optional[float] = None,
    user_lng: Optional[float] = None,
):
    """Return all photos, sorted nearest-first when user_lat/user_lng are provided."""
    db = SessionLocal()
    photos = db.query(Photo).order_by(Photo.id.desc()).all()
    result = []
    for ph in photos:
        d = _photo_dict(ph)
        if user_lat is not None and user_lng is not None and ph.latitude and ph.longitude:
            dist_ft = _haversine_ft(user_lat, user_lng, ph.latitude, ph.longitude)
            d["distance_mi"] = round(dist_ft / 5280, 2)
        else:
            d["distance_mi"] = None
        result.append(d)
    db.close()
    if user_lat is not None and user_lng is not None:
        result.sort(
            key=lambda d: d["distance_mi"]
            if d["distance_mi"] is not None
            else float("inf")
        )
    return result


@router.post("/upload")
async def upload_photo(
    file: UploadFile = File(...),
    profile_id: int = Form(...),
    latitude: float = Form(...),
    longitude: float = Form(...),
    zip_code: str = Form(""),
    address: str = Form(""),
    note: str = Form(""),
    category: str = Form("standard"),
    completion_type: str = Form(""),
    served_to: str = Form(""),
    relation_to: str = Form(""),
    file_number: str = Form(""),
    successful: Optional[bool] = Form(None),
    attempt_status: Optional[str] = Form(None),
    taken_at: str = Form(""),
    pay_rate: str = Form(""),
    user_id: str = Form(""),
    location_group_id: str = Form(""),
    attempt_id: str = Form(""),
    client_batch_id: str = Form(""),
):
    if not (-90 <= latitude <= 90):
        raise HTTPException(
            status_code=422, detail="Latitude must be between -90 and 90"
        )
    if not (-180 <= longitude <= 180):
        raise HTTPException(
            status_code=422, detail="Longitude must be between -180 and 180"
        )
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

    resolved_file_number = _inherited_file_number(profile, file_number)
    if _is_absent_file_number(resolved_file_number):
        resolved_file_number = (file_number or "").strip() or "N/A"

    device_ts = _parse_device_ts(taken_at) or datetime.utcnow()

    pay_val = None
    if pay_rate.strip():
        try:
            parsed_pay = int(round(float(pay_rate.strip())))
            pay_val = parsed_pay if parsed_pay > 0 else None
        except ValueError:
            pay_val = None

    uid = int(user_id) if user_id.strip().isdigit() else None
    grp = int(location_group_id) if location_group_id.strip().isdigit() else None
    existing_attempt_id = int(attempt_id) if attempt_id.strip().isdigit() else None
    batch_key = (client_batch_id or "").strip()[:80] or None
    if not existing_attempt_id and batch_key:
        prior = (
            db.query(Attempt)
            .filter(
                Attempt.profile_id == profile_id,
                Attempt.client_batch_id == batch_key,
            )
            .order_by(Attempt.id.asc())
            .first()
        )
        if prior:
            existing_attempt_id = prior.id

    _advance_profile_status(db, profile)
    if not existing_attempt_id and _profile_blocks_new_attempts(db, profile):
        db.close()
        try:
            os.remove(filepath)
        except OSError:
            pass
        raise HTTPException(
            status_code=422,
            detail="This profile is completed and cannot receive new attempts",
        )

    if not _in_united_states(latitude, longitude):
        db.close()
        try:
            os.remove(filepath)
        except OSError:
            pass
        raise HTTPException(
            status_code=422,
            detail="Attempts can only be logged in the United States.",
        )
    if profile.latitude is None or profile.longitude is None:
        db.close()
        try:
            os.remove(filepath)
        except OSError:
            pass
        raise HTTPException(
            status_code=422,
            detail="This profile has no location, so an attempt cannot be verified.",
        )
    if _feet_between(latitude, longitude, profile.latitude, profile.longitude) > 500:
        db.close()
        try:
            os.remove(filepath)
        except OSError:
            pass
        raise HTTPException(
            status_code=422,
            detail="You must be within 500 feet of this profile to log an attempt.",
        )

    initial_status = "in_progress"
    initial_completed_at = None

    cat = category.strip().lower()
    if cat not in ("standard", "special", "next_day", "asap", "stake_out"):
        cat = "standard"
    company_id = profile.company or DEFAULT_COMPANY_ID
    if not company_allows_priority(company_id, cat):
        cat = default_priority_for_company(company_id)

    attempt_st = _resolve_attempt_status_input(attempt_status, successful)

    attempt = None
    if existing_attempt_id:
        attempt = (
            db.query(Attempt)
            .filter(
                Attempt.id == existing_attempt_id,
                Attempt.profile_id == profile_id,
            )
            .first()
        )
        if not attempt:
            db.close()
            raise HTTPException(status_code=404, detail="Attempt not found")
        if _is_absent_file_number(attempt.file_number) and resolved_file_number:
            attempt.file_number = resolved_file_number
    else:
        attempt = Attempt(
            profile_id=profile_id,
            latitude=latitude,
            longitude=longitude,
            zip_code=zip_code.strip() or None,
            address=address.strip() or None,
            note=note.strip() or None,
            category=cat,
            completion_type=(getattr(profile, "delivery_style", None) or "").strip()
            or None,
            served_to=served_to.strip() or None,
            relation_to=relation_to.strip() or None,
            file_number=resolved_file_number,
            successful=1 if attempt_st == "successful" else 0,
            attempt_status=attempt_st,
            pay_rate=pay_val,
            user_id=uid,
            status=initial_status,
            completed_at=initial_completed_at,
            taken_at=device_ts,
            original_timestamp=device_ts,
            timestamp=device_ts,
            created_at=datetime.utcnow(),
            location_group_id=grp,
            client_batch_id=batch_key,
        )
        db.add(attempt)
        db.flush()
        if not attempt.location_group_id:
            attempt.location_group_id = attempt.id

    photo = Photo(
        image_url=f"/uploads/{filename}",
        timestamp=device_ts,
        taken_at=device_ts,
        original_timestamp=device_ts,
        latitude=attempt.latitude,
        longitude=attempt.longitude,
        zip_code=attempt.zip_code,
        address=attempt.address,
        note=attempt.note,
        category=attempt.category,
        completion_type=attempt.completion_type,
        served_to=attempt.served_to,
        relation_to=attempt.relation_to,
        file_number=_inherited_file_number(profile, attempt.file_number),
        successful=attempt.successful,
        attempt_status=attempt.attempt_status,
        pay_rate=attempt.pay_rate,
        user_id=uid,
        status=attempt.status or initial_status,
        completed_at=attempt.completed_at,
        profile_id=profile_id,
        attempt_id=attempt.id,
        location_group_id=attempt.location_group_id or attempt.id,
    )
    photo.profiles = [profile]
    db.add(photo)
    db.flush()
    _advance_profile_status(db, profile)
    db.commit()
    db.refresh(photo)
    db.refresh(attempt)
    result = _photo_dict(photo)
    result["attempt_id"] = attempt.id
    result["attempt"] = _attempt_dict(attempt)
    db.close()
    return result


@router.patch("/photos/{photo_id}/image")
async def replace_photo_image(photo_id: int, file: UploadFile = File(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    old_path = photo.image_url.lstrip("/")
    if os.path.exists(old_path):
        os.remove(old_path)
    ext = os.path.splitext(file.filename)[1] or ".jpg"
    filename = f"{uuid.uuid4()}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    with open(filepath, "wb") as f:
        shutil.copyfileobj(file.file, f)
    photo.image_url = f"/uploads/{filename}"
    db.commit()
    result = _photo_dict(photo)
    db.close()
    return result


@router.patch("/photos/{photo_id}/location")
async def update_photo_location(
    photo_id: int,
    data: dict = Body(None),
    latitude: float = Form(None),
    longitude: float = Form(None),
):
    raise HTTPException(
        status_code=403,
        detail="Attempt location is locked to the original GPS geotag and cannot be changed.",
    )


@router.patch("/photos/{photo_id}/note")
async def update_photo_note(
    photo_id: int, data: dict = Body(None), note: str = Form(None)
):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")

    if data:
        photo.note = data.get("note", photo.note)
    elif note is not None:
        photo.note = note

    db.commit()
    db.close()
    return {"ok": True}


@router.patch("/photos/{photo_id}/zip")
async def update_photo_zip(
    photo_id: int, data: dict = Body(None), zip_code: str = Form(None)
):
    raise HTTPException(
        status_code=403,
        detail="Attempt location is locked to the original GPS geotag and cannot be changed.",
    )


@router.patch("/photos/{photo_id}/address")
async def update_photo_address(photo_id: int, data: dict = Body(...)):
    raise HTTPException(
        status_code=403,
        detail="Attempt location is locked to the original GPS geotag and cannot be changed.",
    )


@router.patch("/photos/{photo_id}/category")
async def update_photo_category(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    cat = (data.get("category") or "standard").strip().lower()
    if cat not in ("standard", "special", "next_day", "asap", "stake_out"):
        cat = "standard"
    photo.category = cat
    db.commit()
    db.close()
    return {"ok": True, "category": cat}


@router.patch("/photos/{photo_id}/favorite")
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


@router.patch("/photos/{photo_id}/profiles")
async def update_photo_profiles(
    photo_id: int, data: dict = Body(None), profile_ids: str = Form(None)
):
    """Add or replace profiles associated with a pin."""
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")

    if data:
        profile_ids_list = data.get("profile_ids", [])
    else:
        profile_ids_list = (
            [int(x.strip()) for x in profile_ids.split(",") if x.strip()]
            if profile_ids
            else []
        )

    profiles = db.query(Profile).filter(Profile.id.in_(profile_ids_list)).all()
    photo.profiles = profiles
    db.commit()
    db.close()
    return {"ok": True}


@router.delete("/photos/{photo_id}")
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
