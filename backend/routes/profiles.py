"""Profile, company, and attempt duplication routes."""

from __future__ import annotations

from datetime import datetime
import os
import shutil
import uuid

from fastapi import APIRouter, Body, HTTPException

from companies import (
    COMPANIES,
    DEFAULT_COMPANY_ID,
    company_allows_priority,
    default_priority_for_company,
    normalize_company_id,
)
from database import SessionLocal, UPLOAD_DIR
from models import Attempt, Photo, Profile
from serializers import (
    _attempt_dict,
    _in_united_states,
    _inherited_file_number,
    _norm_profile_status,
    _photo_dict,
    _profile_dict,
)
from services.profile_service import (
    _advance_profile_status,
    _copy_file_number_to_attempts,
    _file_number_in_use,
    _parse_profile_location,
    _profile_blocks_new_attempts,
    _profile_name_in_use,
)

router = APIRouter()


@router.get("/companies")
def list_companies():
    """Hardcoded company catalog for client selectors and rate rules."""
    return COMPANIES


@router.get("/profiles")
def get_profiles():
    db = SessionLocal()
    profiles = db.query(Profile).all()
    changed = False
    for p in profiles:
        before = p.status
        _advance_profile_status(db, p)
        if p.status != before:
            changed = True
    if changed:
        db.commit()
        for p in profiles:
            db.refresh(p)
    result = [_profile_dict(p) for p in profiles]
    db.close()
    return result


@router.post("/profiles")
async def create_profile(data: dict = Body(...)):
    name = data.get("name", "").strip()
    service_type = data.get("service_type", "standard").strip()

    if not name:
        raise HTTPException(status_code=422, detail="Profile name is required")

    company_id = normalize_company_id(data.get("company"), required=True)
    if company_id is None:
        if (data.get("company") or "").strip():
            raise HTTPException(status_code=422, detail="Unknown company")
        company_id = DEFAULT_COMPANY_ID

    if service_type not in (
        "standard",
        "special",
        "next_day",
        "asap",
        "stake_out",
        "rush",
        "airport",
    ):
        service_type = "standard"
    if not company_allows_priority(company_id, service_type):
        service_type = default_priority_for_company(company_id)

    pay_rate = data.get("pay_rate")
    if pay_rate is not None:
        try:
            pay_rate = int(round(float(pay_rate)))
        except (TypeError, ValueError):
            raise HTTPException(
                status_code=422, detail="pay_rate must be a whole dollar number"
            )
        if pay_rate <= 0:
            raise HTTPException(
                status_code=422, detail="pay_rate must be greater than 0"
            )

    delivery_style = (data.get("delivery_style") or "").strip() or None
    file_number = (data.get("file_number") or "").strip() or None

    db = SessionLocal()
    if _profile_name_in_use(db, name):
        db.close()
        raise HTTPException(
            status_code=409,
            detail="This name already exists. Use a new name.",
        )
    if _file_number_in_use(db, file_number):
        db.close()
        raise HTTPException(
            status_code=409,
            detail="This file number already exists",
        )
    profile = Profile(
        name=name,
        service_type=service_type,
        pay_rate=pay_rate,
        company=company_id,
        delivery_style=delivery_style,
        file_number=file_number,
        status="pending",
    )
    try:
        _parse_profile_location(data, profile)
    except HTTPException:
        db.close()
        raise
    if profile.latitude is not None and profile.longitude is not None:
        if not _in_united_states(profile.latitude, profile.longitude):
            db.close()
            raise HTTPException(
                status_code=422,
                detail="Pins and hot routes can only be added in the United States.",
            )
    profile.status = "pending"
    db.add(profile)
    db.commit()
    db.refresh(profile)
    result = _profile_dict(profile)
    db.close()
    return result


@router.patch("/profiles/{profile_id}")
async def update_profile(profile_id: int, data: dict = Body(...)):
    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")

    if "name" in data:
        next_name = (data["name"] or "").strip()
        if not next_name:
            db.close()
            raise HTTPException(status_code=422, detail="Profile name is required")
        if _profile_name_in_use(db, next_name, exclude_profile_id=profile.id):
            db.close()
            raise HTTPException(
                status_code=409,
                detail="This name already exists. Use a new name.",
            )
        profile.name = next_name
    if "service_type" in data:
        profile.service_type = data["service_type"]
    if "note" in data:
        profile.note = data["note"]
    if "company" in data:
        company_id = normalize_company_id(data.get("company"), required=True)
        if company_id is None:
            db.close()
            raise HTTPException(status_code=422, detail="Unknown company")
        profile.company = company_id
        if not company_allows_priority(company_id, profile.service_type):
            profile.service_type = default_priority_for_company(company_id)
    if "pay_rate" in data:
        pay_rate = data["pay_rate"]
        if pay_rate is not None:
            try:
                pay_rate = int(round(float(pay_rate)))
            except (TypeError, ValueError):
                db.close()
                raise HTTPException(
                    status_code=422, detail="pay_rate must be a whole dollar number"
                )
            if pay_rate <= 0:
                db.close()
                raise HTTPException(
                    status_code=422, detail="pay_rate must be greater than 0"
                )
        profile.pay_rate = pay_rate
    if "delivery_style" in data:
        style = data["delivery_style"]
        profile.delivery_style = (
            style.strip() if isinstance(style, str) and style.strip() else None
        )
    if "file_number" in data:
        fn = data["file_number"]
        next_fn = fn.strip() if isinstance(fn, str) and fn.strip() else None
        if _file_number_in_use(db, next_fn, exclude_profile_id=profile.id):
            db.close()
            raise HTTPException(
                status_code=409,
                detail="This file number already exists",
            )
        profile.file_number = next_fn
        _copy_file_number_to_attempts(db, profile)

    if "status" in data:
        requested = _norm_profile_status(data.get("status"))
        current = _norm_profile_status(profile.status)
        if requested == "archived":
            if current not in ("completed", "archived"):
                db.close()
                raise HTTPException(
                    status_code=422,
                    detail="Archive is only allowed after the profile is completed",
                )
            profile.status = "archived"
        elif requested != current:
            db.close()
            raise HTTPException(
                status_code=422,
                detail="Profile status is set automatically from attempts",
            )

    try:
        _parse_profile_location(data, profile)
    except HTTPException:
        db.close()
        raise

    if _norm_profile_status(profile.status) != "archived":
        _advance_profile_status(db, profile)

    profile.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(profile)
    result = _profile_dict(profile)
    db.close()
    return result


@router.delete("/profiles/{profile_id}")
def delete_profile(profile_id: int):
    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")

    photos_to_delete = []
    for photo in list(profile.photos):
        if len(photo.profiles) == 1:
            photos_to_delete.append(photo)
        else:
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


@router.get("/profiles/{profile_id}/photos")
def get_profile_photos(profile_id: int):
    """Legacy endpoint returning one photo-shaped row per Attempt."""
    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")
    attempts = (
        db.query(Attempt)
        .filter(Attempt.profile_id == profile_id)
        .order_by(Attempt.id.desc())
        .all()
    )
    attempts.sort(
        key=lambda a: a.taken_at or a.timestamp or datetime.min,
        reverse=True,
    )
    photos_out = []
    if attempts:
        for att in attempts:
            d = _attempt_dict(att)
            photos_out.append({
                "id": d.get("photo_id") or d["id"],
                "attempt_id": d["id"],
                "image_url": d.get("image_url"),
                "timestamp": d.get("timestamp"),
                "taken_at": d.get("taken_at"),
                "latitude": d.get("latitude"),
                "longitude": d.get("longitude"),
                "zip_code": d.get("zip_code"),
                "address": d.get("address"),
                "note": d.get("note"),
                "category": d.get("category"),
                "completion_type": d.get("completion_type"),
                "served_to": d.get("served_to"),
                "relation_to": d.get("relation_to"),
                "file_number": d.get("file_number"),
                "successful": d.get("successful"),
                "attempt_status": d.get("attempt_status"),
                "pay_rate": d.get("pay_rate"),
                "status": d.get("status"),
                "completed_at": d.get("completed_at"),
                "location_group_id": d.get("location_group_id"),
                "profile_id": d.get("profile_id"),
                "profile_name": d.get("profile_name"),
                "service_type": d.get("service_type"),
                "photos": d.get("photos"),
                "photo_count": d.get("photo_count"),
                "is_favorited": False,
            })
    else:
        photos_out = [_photo_dict(ph) for ph in profile.photos]
    result = {
        "profile": {
            "id": profile.id,
            "name": profile.name,
            "service_type": profile.service_type,
        },
        "photos": photos_out,
    }
    db.close()
    return result


@router.get("/profiles/{profile_id}/attempts")
def get_profile_attempts(profile_id: int):
    """Profile -> Attempts (newest first), each with nested photos."""
    db = SessionLocal()
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        db.close()
        raise HTTPException(status_code=404, detail="Profile not found")
    attempts = (
        db.query(Attempt)
        .filter(Attempt.profile_id == profile_id)
        .order_by(Attempt.id.desc())
        .all()
    )
    attempts.sort(
        key=lambda a: a.taken_at or a.timestamp or datetime.min,
        reverse=True,
    )
    result = {
        "profile": _profile_dict(profile),
        "attempts": [_attempt_dict(a) for a in attempts],
    }
    db.close()
    return result


@router.post("/attempts/{attempt_id}/duplicate")
def duplicate_attempt(attempt_id: int, data: dict = Body(...)):
    """Duplicate an attempt onto other nearby profiles."""
    profile_ids = data.get("profile_ids") or []
    if not isinstance(profile_ids, list) or not profile_ids:
        raise HTTPException(status_code=422, detail="profile_ids required")
    db = SessionLocal()
    source = db.query(Attempt).filter(Attempt.id == attempt_id).first()
    if not source:
        db.close()
        raise HTTPException(status_code=404, detail="Attempt not found")
    created = []
    for raw_pid in profile_ids:
        try:
            pid = int(raw_pid)
        except (TypeError, ValueError):
            continue
        if pid == source.profile_id:
            continue
        profile = db.query(Profile).filter(Profile.id == pid).first()
        if not profile:
            continue
        _advance_profile_status(db, profile)
        if _profile_blocks_new_attempts(db, profile):
            continue
        clone = Attempt(
            profile_id=pid,
            latitude=source.latitude,
            longitude=source.longitude,
            zip_code=source.zip_code,
            address=source.address,
            note=source.note,
            category=source.category,
            completion_type=source.completion_type,
            served_to=source.served_to,
            relation_to=source.relation_to,
            file_number=_inherited_file_number(profile, source.file_number),
            successful=source.successful,
            attempt_status=source.attempt_status,
            pay_rate=source.pay_rate,
            status=source.status or "in_progress",
            completed_at=None,
            user_id=source.user_id,
            location_group_id=None,
            taken_at=source.taken_at,
            original_timestamp=source.original_timestamp or source.taken_at,
            timestamp=source.timestamp or datetime.utcnow(),
            created_at=datetime.utcnow(),
        )
        db.add(clone)
        db.flush()
        clone.location_group_id = clone.id
        for ph in list(source.photos or []):
            src_path = (ph.image_url or "").lstrip("/")
            new_url = ph.image_url
            if src_path and os.path.exists(src_path):
                ext = os.path.splitext(src_path)[1] or ".jpg"
                filename = f"{uuid.uuid4()}{ext}"
                dest = os.path.join(UPLOAD_DIR, filename)
                try:
                    shutil.copy2(src_path, dest)
                    new_url = f"/uploads/{filename}"
                except OSError:
                    new_url = ph.image_url
            new_ph = Photo(
                image_url=new_url,
                timestamp=ph.timestamp or clone.timestamp,
                taken_at=ph.taken_at or clone.taken_at,
                original_timestamp=ph.original_timestamp or clone.taken_at,
                latitude=clone.latitude,
                longitude=clone.longitude,
                zip_code=clone.zip_code,
                address=clone.address,
                note=clone.note,
                category=clone.category,
                completion_type=clone.completion_type,
                served_to=clone.served_to,
                relation_to=clone.relation_to,
                file_number=clone.file_number,
                successful=clone.successful,
                attempt_status=clone.attempt_status,
                pay_rate=clone.pay_rate,
                user_id=clone.user_id,
                status=clone.status,
                profile_id=pid,
                attempt_id=clone.id,
                location_group_id=clone.id,
            )
            new_ph.profiles = [profile]
            db.add(new_ph)
        created.append(clone)
        _advance_profile_status(db, profile)
    db.commit()
    out = []
    for a in created:
        db.refresh(a)
        out.append(_attempt_dict(a))
    db.close()
    return {"ok": True, "duplicated": len(out), "attempts": out}
