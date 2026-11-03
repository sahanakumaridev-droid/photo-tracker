"""Profile lifecycle, validation, file-number sync, and location parsing."""

from __future__ import annotations

from datetime import datetime
from fastapi import HTTPException
from sqlalchemy import func

from companies import DEFAULT_COMPANY_ID, get_company
from models import Attempt, Photo, Profile
from serializers import (
    _inherited_file_number,
    _is_absent_file_number,
    _norm_profile_status,
    _normalize_attempt_status,
)


def _copy_file_number_to_attempts(db, profile):
    """Keep attempt/photo rows in sync with the profile file number."""
    fn = _inherited_file_number(profile)
    if _is_absent_file_number(fn):
        return
    for att in db.query(Attempt).filter(Attempt.profile_id == profile.id).all():
        att.file_number = fn
    for ph in list(getattr(profile, "photos", None) or []):
        ph.file_number = fn


def _profile_name_in_use(db, name, exclude_profile_id=None):
    """True when another profile already uses this name (case-insensitive)."""
    key = (name or "").strip().lower()
    if not key:
        return False
    q = db.query(Profile).filter(func.lower(Profile.name) == key)
    if exclude_profile_id is not None:
        q = q.filter(Profile.id != exclude_profile_id)
    return q.first() is not None


def _file_number_in_use(db, file_number, exclude_profile_id=None):
    """True when another profile or its attempts already has this file number."""
    fn = (file_number or "").strip()
    if not fn or fn.upper() == "N/A":
        return False
    key = fn.lower()
    q = db.query(Profile).filter(func.lower(Profile.file_number) == key)
    if exclude_profile_id is not None:
        q = q.filter(Profile.id != exclude_profile_id)
    if q.first() is not None:
        return True
    aq = db.query(Attempt).filter(func.lower(Attempt.file_number) == key)
    if exclude_profile_id is not None:
        aq = aq.filter(Attempt.profile_id != exclude_profile_id)
    return aq.first() is not None


def _attempt_outcome(att):
    return _normalize_attempt_status(att)


def _profile_attempt_outcomes(db, profile):
    """One outcome per logged attempt (Attempt rows, else photo groups)."""
    attempts = db.query(Attempt).filter(Attempt.profile_id == profile.id).all()
    if attempts:
        return [_attempt_outcome(a) for a in attempts]
    photos = db.query(Photo).filter(Photo.profile_id == profile.id).all()
    if not photos:
        return []
    grouped = {}
    for ph in photos:
        key = (
            getattr(ph, "attempt_id", None)
            or getattr(ph, "location_group_id", None)
            or ph.id
        )
        grouped.setdefault(key, []).append(ph)
    outcomes = []
    for group in grouped.values():
        if any(_normalize_attempt_status(p) == "successful" for p in group):
            outcomes.append("successful")
        elif any(_normalize_attempt_status(p) == "unsuccessful" for p in group):
            outcomes.append("unsuccessful")
        else:
            outcomes.append("pending")
    return outcomes


def _compute_profile_activity_status(db, profile):
    """pending | in_progress | completed from attempt outcomes."""
    outcomes = _profile_attempt_outcomes(db, profile)
    if any(o == "successful" for o in outcomes):
        return "completed"
    unsuccessful = sum(1 for o in outcomes if o == "unsuccessful")
    if unsuccessful == 0:
        return "pending"
    company = get_company(profile.company or DEFAULT_COMPANY_ID) or {}
    diligence = int(company.get("attempts_for_diligence") or 5)
    if unsuccessful >= diligence:
        return "completed"
    return "in_progress"


def _sync_work_to_profile_status(db, profile, target):
    """Keep attempt and photo job-status aligned with the profile rule."""
    if target not in ("pending", "in_progress", "completed"):
        return
    desired = "completed" if target == "completed" else "in_progress"
    attempts = db.query(Attempt).filter(Attempt.profile_id == profile.id).all()
    attempt_ids = [a.id for a in attempts]
    photos = []
    if attempt_ids:
        photos.extend(
            db.query(Photo).filter(Photo.attempt_id.in_(attempt_ids)).all()
        )
    photos.extend(
        db.query(Photo).filter(Photo.profile_id == profile.id).all()
    )

    def _apply(row):
        if (row.status or "") == "archived":
            return
        if desired == "completed":
            row.status = "completed"
            if not row.completed_at:
                row.completed_at = datetime.utcnow()
        elif (row.status or "") in ("completed", "open", "", None):
            row.status = "in_progress"
            row.completed_at = None

    for att in attempts:
        _apply(att)
    seen_photos = set()
    for ph in photos:
        if ph.id in seen_photos:
            continue
        seen_photos.add(ph.id)
        _apply(ph)


def _advance_profile_status(db, profile):
    """Archived stays archived. Every other status follows attempt outcomes."""
    current = _norm_profile_status(profile.status)
    if current == "archived":
        if (profile.status or "").strip().lower() != "archived":
            profile.status = "archived"
        return current
    target = _compute_profile_activity_status(db, profile)
    if (profile.status or "") != target:
        profile.status = target
        profile.updated_at = datetime.utcnow()
    _sync_work_to_profile_status(db, profile, target)
    return target


def _profile_blocks_new_attempts(db, profile):
    st = _norm_profile_status(profile.status)
    if st in ("completed", "archived"):
        return True
    return _compute_profile_activity_status(db, profile) == "completed"


def _parse_profile_location(data, profile):
    """Applies address/city/state/postal_code/lat/lng fields from `data` onto `profile`."""
    for field in ("address", "city", "state", "postal_code"):
        if field in data:
            value = data[field]
            setattr(profile, field, value.strip() if isinstance(value, str) else value)

    for field in ("latitude", "longitude"):
        if field in data:
            value = data[field]
            if value is None:
                setattr(profile, field, None)
                continue
            try:
                value = float(value)
            except (TypeError, ValueError):
                raise HTTPException(status_code=422, detail=f"{field} must be a number")
            if field == "latitude" and not (-90 <= value <= 90):
                raise HTTPException(
                    status_code=422, detail="latitude must be between -90 and 90"
                )
            if field == "longitude" and not (-180 <= value <= 180):
                raise HTTPException(
                    status_code=422, detail="longitude must be between -180 and 180"
                )
            setattr(profile, field, value)

    if (
        profile.latitude is not None
        and profile.longitude is not None
        and abs(profile.latitude) <= 0.0001
        and abs(profile.longitude) <= 0.0001
    ):
        profile.latitude = None
        profile.longitude = None
