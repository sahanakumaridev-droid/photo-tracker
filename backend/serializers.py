"""Time, geo, status, and dictionary serialization helpers."""

from __future__ import annotations

from datetime import datetime, timezone
from math import asin, atan2, cos, radians, sin, sqrt

from companies import get_company, normalize_company_id
from database import PST


def _to_pst_iso(ts):
    if not ts:
        return None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return ts.astimezone(PST).isoformat()


def _pst_naive_to_utc(dt):
    """Interpret a naive datetime as PST wall-clock time and convert to naive UTC."""
    if dt is None:
        return None
    localized = dt.replace(tzinfo=PST)
    return localized.astimezone(timezone.utc).replace(tzinfo=None)


def _parse_device_ts(s):
    """Parse a device-supplied ISO timestamp; return None on failure."""
    if not s:
        return None
    s = s.strip()
    for fmt in (
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
    ):
        try:
            return datetime.strptime(s.replace("Z", "").split("+")[0], fmt)
        except ValueError:
            continue
    return None


def _haversine_ft(lat1, lon1, lat2, lon2):
    """Great-circle distance in feet between two lat/lng points."""
    r_ft = 20925524.9
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return r_ft * 2 * atan2(sqrt(a), sqrt(1 - a))


def _feet_between(lat1, lng1, lat2, lng2):
    lat1, lng1, lat2, lng2 = map(radians, (float(lat1), float(lng1), float(lat2), float(lng2)))
    dlat = lat2 - lat1
    dlng = lng2 - lng1
    a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlng / 2) ** 2
    return 2 * 6371000 * asin(sqrt(min(1.0, a))) * 3.28084


def _in_united_states(lat, lng):
    if lat is None or lng is None:
        return False
    try:
        lat = float(lat)
        lng = float(lng)
    except (TypeError, ValueError):
        return False
    if 24.396 <= lat <= 49.384 and -124.849 <= lng <= -66.885:
        return True
    if 51.2 <= lat <= 71.5 and -179.2 <= lng <= -129.9:
        return True
    if 18.9 <= lat <= 22.4 and -160.4 <= lng <= -154.7:
        return True
    if 17.8 <= lat <= 18.6 and -67.3 <= lng <= -65.2:
        return True
    return False


def _normalize_attempt_status(ph):
    """Resolve attempt_status from the column or legacy successful flag."""
    raw = (getattr(ph, "attempt_status", None) or "").strip().lower()
    if raw in ("pending", "successful", "unsuccessful"):
        return raw
    if ph.successful is None:
        return "pending"
    return "successful" if ph.successful else "unsuccessful"


def _attempt_is_successful(ph):
    return _normalize_attempt_status(ph) == "successful"


def _resolve_attempt_status_input(attempt_status, successful):
    """Prefer explicit attempt_status; fall back to legacy successful bool."""
    raw = (attempt_status or "").strip().lower() if attempt_status else ""
    if raw in ("pending", "successful", "unsuccessful"):
        return raw
    if successful is True:
        return "successful"
    if successful is False:
        return "unsuccessful"
    return "pending"


def _is_absent_file_number(value):
    v = (value or "").strip()
    return not v or v.upper() == "N/A"


def _inherited_file_number(profile, stored=None):
    """File number is created on the profile; attempts and photos inherit it."""
    pfn = (getattr(profile, "file_number", None) or "").strip() if profile else ""
    if pfn and pfn.upper() != "N/A":
        return pfn
    s = (stored or "").strip()
    if s:
        return s
    return pfn or None


_PROFILE_STATUS_RANK = {
    "pending": 0,
    "in_progress": 1,
    "completed": 2,
    "archived": 3,
}


def _norm_profile_status(raw):
    """Canonical profile lifecycle: pending | in_progress | completed | archived."""
    s = (raw or "").strip().lower()
    if s in ("awaiting_attempt", "open", ""):
        return "pending"
    if s == "in-progress":
        return "in_progress"
    if s in _PROFILE_STATUS_RANK:
        return s
    return "pending"


def _photo_dict(ph):
    profiles = []
    for p in ph.profiles:
        raw = (p.company or "").strip()
        cid = normalize_company_id(raw, required=True) if raw else None
        co = get_company(cid) if cid else None
        profiles.append({
            "id": p.id,
            "name": p.name,
            "service_type": p.service_type,
            "company": cid or (raw or None),
            "company_name": co["name"] if co else None,
        })
    primary = profiles[0] if profiles else None
    return {
        "id": ph.id,
        "image_url": ph.image_url,
        "timestamp": _to_pst_iso(ph.timestamp),
        "taken_at": _to_pst_iso(ph.taken_at),
        "original_timestamp": _to_pst_iso(ph.original_timestamp),
        "edited_timestamp": _to_pst_iso(ph.edited_timestamp),
        "created_at": _to_pst_iso(ph.created_at),
        "latitude": ph.latitude,
        "longitude": ph.longitude,
        "zip_code": ph.zip_code,
        "address": ph.address,
        "note": ph.note,
        "category": ph.category or "standard",
        "completion_type": ph.completion_type,
        "served_to": ph.served_to,
        "relation_to": ph.relation_to,
        "file_number": _inherited_file_number(
            (ph.profiles[0] if getattr(ph, "profiles", None) else None),
            ph.file_number,
        ),
        "successful": _attempt_is_successful(ph),
        "attempt_status": _normalize_attempt_status(ph),
        "pay_rate": ph.pay_rate,
        "status": ph.status or "open",
        "completed_at": _to_pst_iso(ph.completed_at),
        "user_id": ph.user_id,
        "location_group_id": ph.location_group_id or ph.id,
        "profile_id": primary["id"] if primary else ph.profile_id,
        "profile_name": primary["name"] if primary else "Unknown",
        "service_type": primary["service_type"] if primary else "standard",
        "profiles": profiles,
        "is_favorited": bool(ph.is_favorited),
        "attempt_id": getattr(ph, "attempt_id", None),
    }


def _attempt_dict(att):
    """Serialize an Attempt with nested photos (media)."""
    photos = list(att.photos or [])
    primary = photos[0] if photos else None
    profile = att.profile
    return {
        "id": att.id,
        "profile_id": att.profile_id,
        "profile_name": profile.name if profile else "Unknown",
        "service_type": profile.service_type if profile else "standard",
        "latitude": att.latitude,
        "longitude": att.longitude,
        "zip_code": att.zip_code,
        "address": att.address,
        "note": att.note,
        "category": att.category or "standard",
        "completion_type": att.completion_type,
        "served_to": att.served_to,
        "relation_to": att.relation_to,
        "file_number": _inherited_file_number(profile, att.file_number),
        "successful": (att.attempt_status or "") == "successful",
        "attempt_status": att.attempt_status or "pending",
        "pay_rate": att.pay_rate,
        "status": att.status or "open",
        "completed_at": _to_pst_iso(att.completed_at),
        "user_id": att.user_id,
        "location_group_id": att.location_group_id or att.id,
        "timestamp": _to_pst_iso(att.timestamp),
        "taken_at": _to_pst_iso(att.taken_at),
        "created_at": _to_pst_iso(att.created_at),
        "image_url": primary.image_url if primary else None,
        "photo_id": primary.id if primary else None,
        "photos": [
            {
                "id": primary_ph.id,
                "image_url": primary_ph.image_url,
                "taken_at": _to_pst_iso(primary_ph.taken_at),
                "is_favorited": bool(primary_ph.is_favorited),
            }
            for primary_ph in photos
        ],
        "photo_count": len(photos),
    }


def _profile_dict(p):
    """Shared response shape for profile endpoints."""
    raw_company = (p.company or "").strip()
    company_id = normalize_company_id(raw_company, required=True) if raw_company else None
    company = get_company(company_id) if company_id else None
    return {
        "id": p.id,
        "name": p.name,
        "service_type": p.service_type,
        "note": p.note,
        "pay_rate": p.pay_rate,
        "company": company_id or (raw_company or None),
        "delivery_style": getattr(p, "delivery_style", None),
        "file_number": getattr(p, "file_number", None),
        "company_name": company["name"] if company else None,
        "status": _norm_profile_status(p.status),
        "address": p.address,
        "city": p.city,
        "state": p.state,
        "postal_code": p.postal_code,
        "latitude": p.latitude,
        "longitude": p.longitude,
        "attempts_count": (
            len(p.attempts)
            if getattr(p, "attempts", None) is not None
            else len(p.photos)
        ),
        "created_at": _to_pst_iso(getattr(p, "created_at", None)),
    }
