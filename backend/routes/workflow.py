"""Timestamp editing, pay-rate updates, job/attempt status transitions, and archive routes."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Body, HTTPException

from database import SessionLocal
from models import Attempt, Photo, Profile, StatusHistory, TimestampEdit
from serializers import (
    _norm_profile_status,
    _parse_device_ts,
    _photo_dict,
    _to_pst_iso,
)
from services.profile_service import (
    _advance_profile_status,
    _compute_profile_activity_status,
)

router = APIRouter()

_EDIT_WINDOW_MIN = 10


@router.patch("/photos/{photo_id}/timestamp")
async def edit_timestamp(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    anchor = (
        photo.created_at
        or photo.original_timestamp
        or photo.timestamp
        or datetime.utcnow()
    )
    age_min = (datetime.utcnow() - anchor).total_seconds() / 60
    if age_min > _EDIT_WINDOW_MIN:
        db.close()
        raise HTTPException(
            status_code=423,
            detail=f"Timestamp locked — edit window of {_EDIT_WINDOW_MIN} min elapsed",
        )
    new_ts = _parse_device_ts(data.get("timestamp"))
    if not new_ts:
        db.close()
        raise HTTPException(
            status_code=422, detail="Valid 'timestamp' (ISO) required"
        )
    old = photo.timestamp
    photo.timestamp = new_ts
    photo.edited_timestamp = new_ts
    db.add(
        TimestampEdit(
            photo_id=photo.id,
            old_value=old,
            new_value=new_ts,
            edited_by=data.get("user_id"),
        )
    )
    db.commit()
    db.close()
    return {"ok": True, "timestamp": _to_pst_iso(new_ts)}


@router.get("/photos/{photo_id}/timestamp-history")
def timestamp_history(photo_id: int):
    db = SessionLocal()
    edits = (
        db.query(TimestampEdit)
        .filter(TimestampEdit.photo_id == photo_id)
        .order_by(TimestampEdit.edited_at)
        .all()
    )
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    result = {
        "photo_id": photo_id,
        "original_timestamp": _to_pst_iso(photo.original_timestamp) if photo else None,
        "current_timestamp": _to_pst_iso(photo.timestamp) if photo else None,
        "edits": [
            {
                "old_value": _to_pst_iso(e.old_value),
                "new_value": _to_pst_iso(e.new_value),
                "edited_by": e.edited_by,
                "edited_at": _to_pst_iso(e.edited_at),
            }
            for e in edits
        ],
    }
    db.close()
    return result


@router.patch("/photos/{photo_id}/pay-rate")
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
        raise HTTPException(
            status_code=422, detail="pay_rate must be a whole dollar number"
        )
    db.commit()
    pay_val = photo.pay_rate
    db.close()
    return {"ok": True, "pay_rate": pay_val, "status": photo.status}


@router.patch("/photos/{photo_id}/status")
async def update_status(photo_id: int, data: dict = Body(...)):
    db = SessionLocal()
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if not photo:
        db.close()
        raise HTTPException(status_code=404, detail="Photo not found")
    st = (data.get("status") or "").strip().lower()
    if st not in ("open", "in_progress", "completed", "archived"):
        db.close()
        raise HTTPException(
            status_code=422, detail="status must be open|in_progress|completed|archived"
        )
    old_status = photo.status or "open"
    photo.status = st
    if st in ("completed", "archived") and not photo.completed_at:
        photo.completed_at = datetime.utcnow()
    if st in ("open", "in_progress"):
        photo.completed_at = None
    if photo.profile_id and st in ("completed", "archived"):
        profile = db.query(Profile).filter(Profile.id == photo.profile_id).first()
        if profile and _norm_profile_status(profile.status) != "archived":
            profile.status = "archived" if st == "archived" else "completed"
            profile.updated_at = datetime.utcnow()
    if photo.profile_id and st in ("open", "in_progress"):
        profile = db.query(Profile).filter(Profile.id == photo.profile_id).first()
        if profile and _norm_profile_status(profile.status) == "completed":
            profile.status = _compute_profile_activity_status(db, profile)
            profile.updated_at = datetime.utcnow()
    db.add(
        StatusHistory(
            photo_id=photo_id,
            old_status=old_status,
            new_status=st,
            updated_by=data.get("updated_by"),
        )
    )
    db.commit()
    db.close()
    return {"ok": True, "status": st, "previous_status": old_status}


@router.patch("/attempts/{attempt_id}/status")
async def update_attempt_status(attempt_id: int, data: dict = Body(...)):
    """Cascades a status change to the Attempt row and every sibling Photo row."""
    db = SessionLocal()
    attempt = db.query(Attempt).filter(Attempt.id == attempt_id).first()
    if not attempt:
        db.close()
        raise HTTPException(status_code=404, detail="Attempt not found")
    st = (data.get("status") or "").strip().lower()
    if st not in ("open", "in_progress", "completed", "archived"):
        db.close()
        raise HTTPException(
            status_code=422, detail="status must be open|in_progress|completed|archived"
        )

    if st == "completed":
        profile = db.query(Profile).filter(Profile.id == attempt.profile_id).first()
        applied = _advance_profile_status(db, profile) if profile else "in_progress"
        db.commit()
        db.close()
        return {"ok": True, "status": applied, "photos_updated": 0}

    attempt.status = st
    if st in ("completed", "archived") and not attempt.completed_at:
        attempt.completed_at = datetime.utcnow()
    if st in ("open", "in_progress"):
        attempt.completed_at = None

    photos = db.query(Photo).filter(Photo.attempt_id == attempt_id).all()
    for photo in photos:
        old_status = photo.status or "open"
        photo.status = st
        if st in ("completed", "archived") and not photo.completed_at:
            photo.completed_at = datetime.utcnow()
        if st in ("open", "in_progress"):
            photo.completed_at = None
        db.add(
            StatusHistory(
                photo_id=photo.id,
                old_status=old_status,
                new_status=st,
                updated_by=data.get("updated_by"),
            )
        )
    db.commit()
    db.close()
    return {"ok": True, "status": st, "photos_updated": len(photos)}


@router.get("/photos/{photo_id}/status-history")
def status_history(photo_id: int):
    db = SessionLocal()
    rows = (
        db.query(StatusHistory)
        .filter(StatusHistory.photo_id == photo_id)
        .order_by(StatusHistory.updated_at.desc())
        .all()
    )
    db.close()
    return [
        {
            "id": r.id,
            "old_status": r.old_status,
            "new_status": r.new_status,
            "updated_by": r.updated_by,
            "updated_at": _to_pst_iso(r.updated_at),
        }
        for r in rows
    ]


@router.get("/archive")
def get_archive(
    search: Optional[str] = None,
    service_level: Optional[str] = None,
    status: str = "archived",
):
    """Job list for the Archive screen, filtered by lifecycle status."""
    db = SessionLocal()
    st = (status or "archived").strip().lower()
    if st == "active":
        status_filter = Photo.status.in_(("open", "in_progress"))
    elif st in ("open", "in_progress", "completed", "archived"):
        status_filter = Photo.status == st
    else:
        status_filter = Photo.status == "archived"
    photos = (
        db.query(Photo).filter(status_filter).order_by(Photo.timestamp.desc()).all()
    )
    result = []
    for ph in photos:
        d = _photo_dict(ph)
        if service_level and d["category"] != service_level:
            continue
        if search:
            s = search.lower()
            hay = " ".join(
                str(x or "")
                for x in [
                    ph.note,
                    ph.address,
                    ph.zip_code,
                    *[p["name"] for p in d["profiles"]],
                ]
            ).lower()
            if s not in hay:
                continue
        result.append(d)
    db.close()
    return result
