"""Activity log, master-pin locations, nearby proximity, and schedule routes."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException

from database import SessionLocal
from models import Photo
from serializers import _haversine_ft, _photo_dict, _pst_naive_to_utc, _to_pst_iso

router = APIRouter()

_SERVICE_LEVELS = ("asap", "stake_out", "next_day", "standard", "special")
_PRIORITY = {"asap": 0, "next_day": 1, "special": 2, "standard": 3}
_NEARBY_DEFAULT_FT = 200.0


def _group_key(ph):
    return ph.location_group_id or ph.id


def _master_pin_dict(group_photos):
    """Collapse a list of attempt-Photos sharing a group into one master pin."""
    attempts = sorted(group_photos, key=lambda p: p.id)
    root = attempts[0]
    statuses = {p.status or "in_progress" for p in attempts}
    if statuses == {"archived"}:
        status = "archived"
    elif "in_progress" in statuses or "open" in statuses:
        status = "in_progress"
    else:
        status = "completed"
    pay = next((p.pay_rate for p in attempts if p.pay_rate is not None), None)

    active = [
        p
        for p in attempts
        if (p.status or "in_progress") not in ("archived", "completed")
    ]
    service_level = (active[-1] if active else attempts[-1]).category or "standard"

    return {
        "location_group_id": _group_key(root),
        "latitude": root.latitude,
        "longitude": root.longitude,
        "address": root.address,
        "zip_code": root.zip_code,
        "service_level": service_level,
        "pay_rate": pay,
        "status": status,
        "attempt_count": len(attempts),
        "first_attempt_at": _to_pst_iso(root.original_timestamp or root.timestamp),
        "last_attempt_at": _to_pst_iso(attempts[-1].timestamp),
        "attempts": [_photo_dict(p) for p in attempts],
    }


def _all_master_pins(db):
    photos = db.query(Photo).all()
    groups = {}
    for ph in photos:
        groups.setdefault(_group_key(ph), []).append(ph)
    return [_master_pin_dict(g) for g in groups.values()]


@router.get("/log")
def get_log(
    date: Optional[str] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    zip_code: Optional[str] = None,
    status: Optional[str] = None,
    search: Optional[str] = None,
):
    db = SessionLocal()
    query = db.query(Photo)

    if start_time or end_time:
        def _parse_dt(s):
            for fmt in (
                "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%dT%H:%M",
                "%Y-%m-%d %H:%M:%S",
                "%Y-%m-%d %H:%M",
                "%Y-%m-%d",
            ):
                try:
                    return datetime.strptime(s, fmt)
                except ValueError:
                    continue
            return None

        if start_time:
            dt_start = _parse_dt(start_time)
            if dt_start:
                query = query.filter(Photo.timestamp >= _pst_naive_to_utc(dt_start))
        if end_time:
            dt_end = _parse_dt(end_time)
            if dt_end:
                if "T" not in end_time and " " not in end_time.strip():
                    dt_end = dt_end.replace(hour=23, minute=59, second=59)
                query = query.filter(Photo.timestamp <= _pst_naive_to_utc(dt_end))
    elif date:
        try:
            d = datetime.strptime(date, "%Y-%m-%d")
            query = query.filter(
                Photo.timestamp >= _pst_naive_to_utc(d.replace(hour=0, minute=0, second=0)),
                Photo.timestamp <= _pst_naive_to_utc(d.replace(hour=23, minute=59, second=59)),
            )
        except ValueError:
            pass

    if zip_code:
        query = query.filter(Photo.zip_code.ilike(f"%{zip_code}%"))

    photos = query.order_by(Photo.timestamp.desc()).all()
    result = []
    for ph in photos:
        d = _photo_dict(ph)
        if status and d["service_type"] != status:
            continue
        if search:
            s = search.lower()
            note_match = ph.note and s in ph.note.lower()
            address_match = ph.address and s in ph.address.lower()
            profile_match = any(s in p["name"].lower() for p in d["profiles"])
            zip_match = ph.zip_code and s in ph.zip_code.lower()
            if not (note_match or address_match or profile_match or zip_match):
                continue
        result.append(d)

    db.close()
    return result


@router.get("/locations/nearby")
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


@router.get("/locations")
def list_locations(
    service_levels: Optional[str] = None, status: Optional[str] = None
):
    """Master-pin list with optional service-level + status filters."""
    db = SessionLocal()
    pins = _all_master_pins(db)
    db.close()
    if service_levels:
        wanted = {s.strip().lower() for s in service_levels.split(",") if s.strip()}
        pins = [p for p in pins if p["service_level"] in wanted]
    if status:
        pins = [p for p in pins if p["status"] == status]
    return pins


@router.get("/locations/{group_id}/attempts")
def location_attempts(group_id: int):
    """Full attempt history / timeline for one master pin."""
    db = SessionLocal()
    photos = (
        db.query(Photo)
        .filter((Photo.location_group_id == group_id) | (Photo.id == group_id))
        .all()
    )
    if not photos:
        db.close()
        raise HTTPException(status_code=404, detail="Location not found")
    result = _master_pin_dict(photos)
    db.close()
    return result


@router.get("/schedule")
def get_schedule(
    queue: Optional[str] = None,
    user_lat: Optional[float] = None,
    user_lng: Optional[float] = None,
):
    """Scheduling queues derived from service level."""
    db = SessionLocal()
    pins = [p for p in _all_master_pins(db) if p["status"] != "archived"]
    db.close()
    if queue:
        q = queue.strip().lower()
        pins = [p for p in pins if p["service_level"] == q]
    for p in pins:
        p["priority"] = _PRIORITY.get(p["service_level"], 3)
        if (
            user_lat is not None
            and user_lng is not None
            and p["latitude"]
            and p["longitude"]
        ):
            dist_ft = _haversine_ft(user_lat, user_lng, p["latitude"], p["longitude"])
            p["distance_mi"] = round(dist_ft / 5280, 2)
        else:
            p["distance_mi"] = None
    pins.sort(
        key=lambda p: (
            p["priority"],
            p["distance_mi"] if p["distance_mi"] is not None else float("inf"),
        )
    )
    queues = {lvl: [] for lvl in _SERVICE_LEVELS}
    for p in pins:
        queues.setdefault(p["service_level"], []).append(p)
    return {"queues": queues, "items": pins}
