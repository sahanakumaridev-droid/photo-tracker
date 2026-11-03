"""Mileage tracking, earnings summary, and payout period routes."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Body

from database import PST, SessionLocal
from models import Attempt, MileageDaily, PayoutPeriod, Photo, Profile, User
from serializers import (
    _haversine_ft,
    _norm_profile_status,
    _parse_device_ts,
    _to_pst_iso,
)
from services.profile_service import _compute_profile_activity_status

router = APIRouter()


def _user_by_email(db, email):
    email = (email or "").strip().lower()
    if not email:
        email = "field@local"
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        user = User(email=email, name=email.split("@")[0], role="field")
        db.add(user)
        db.flush()
    return user


def _mileage_payload(db, user, today=None):
    total = float(user.mileage_total_miles or 0)
    raw_today = (today or "").strip()
    try:
        today_dt = (
            datetime.strptime(raw_today, "%Y-%m-%d")
            if len(raw_today) == 10
            else datetime.utcnow()
        )
    except ValueError:
        today_dt = datetime.utcnow()
    today = today_dt.strftime("%Y-%m-%d")
    week_start = (today_dt - timedelta(days=7)).strftime("%Y-%m-%d")
    snaps = db.query(MileageDaily).filter(MileageDaily.user_id == user.id).all()
    by_day = {s.day: float(s.total_miles or 0) for s in snaps}
    prior = None
    for day in sorted(by_day):
        if day < today:
            prior = by_day[day]
    today_miles = total - prior if prior is not None else total
    if today_miles < 0:
        today_miles = 0
    week_prior = None
    for day in sorted(by_day):
        if day <= week_start:
            week_prior = by_day[day]
    week_miles = total - (week_prior if week_prior is not None else 0)
    if week_miles < 0:
        week_miles = 0
    return {
        "total_miles": round(total, 2),
        "today_miles": round(today_miles, 2),
        "week_miles": round(week_miles, 2),
        "daily": [
            {"day": s.day, "total_miles": float(s.total_miles or 0)}
            for s in sorted(snaps, key=lambda x: x.day)
        ],
    }


@router.get("/mileage")
def get_mileage(email: str = "", day: str = ""):
    db = SessionLocal()
    try:
        user = _user_by_email(db, email)
        return _mileage_payload(db, user, today=day)
    finally:
        db.close()


@router.post("/mileage/ping")
def mileage_ping(data: dict = Body(...)):
    db = SessionLocal()
    try:
        user = _user_by_email(db, data.get("email"))
        tracking = bool(data.get("tracking", True))
        user.mileage_tracking = 1 if tracking else 0
        lat = data.get("latitude")
        lng = data.get("longitude")
        if not tracking:
            user.mileage_last_lat = None
            user.mileage_last_lng = None
        day = (data.get("day") or "").strip()
        today = day if len(day) == 10 else datetime.utcnow().strftime("%Y-%m-%d")
        existing_today = (
            db.query(MileageDaily)
            .filter(
                MileageDaily.user_id == user.id,
                MileageDaily.day == today,
            )
            .first()
        )
        if existing_today is None:
            existing_today = MileageDaily(
                user_id=user.id,
                day=today,
                total_miles=float(user.mileage_total_miles or 0),
            )
            db.add(existing_today)
        if tracking and lat is not None and lng is not None:
            lat = float(lat)
            lng = float(lng)
            if user.mileage_last_lat is not None and user.mileage_last_lng is not None:
                miles = (
                    _haversine_ft(
                        user.mileage_last_lat, user.mileage_last_lng, lat, lng
                    )
                    / 5280.0
                )
                if 0.002 < miles < 80:
                    user.mileage_total_miles = (
                        float(user.mileage_total_miles or 0) + miles
                    )
            user.mileage_last_lat = lat
            user.mileage_last_lng = lng
        existing_today.total_miles = float(user.mileage_total_miles or 0)
        db.commit()
        db.refresh(user)
        return _mileage_payload(db, user, today=today)
    finally:
        db.close()


def _period_bounds(period):
    """Return start_utc for today|week|biweekly|month."""
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


def _dedupe_by_attempt(jobs):
    """Deduplicate Photo rows by Attempt so pay_rate is counted once per attempt."""
    seen = set()
    out = []
    for j in jobs:
        key = j.attempt_id or f"photo:{j.id}"
        if key in seen:
            continue
        seen.add(key)
        out.append(j)
    return out


def _earned_pay(job, db=None):
    """Whole-dollar pay for one attempt, falling back to the profile rate."""
    if getattr(job, "pay_rate", None):
        return job.pay_rate
    for p in getattr(job, "profiles", None) or []:
        if getattr(p, "pay_rate", None):
            return p.pay_rate
    if db is None:
        return 0
    profile_ids = []
    if getattr(job, "profile_id", None):
        profile_ids.append(job.profile_id)
    if getattr(job, "attempt_id", None):
        attempt = db.query(Attempt).filter(Attempt.id == job.attempt_id).first()
        if attempt is not None:
            if attempt.pay_rate:
                return attempt.pay_rate
            if attempt.profile_id:
                profile_ids.append(attempt.profile_id)
    for pid in profile_ids:
        profile = db.query(Profile).filter(Profile.id == pid).first()
        if profile is not None and profile.pay_rate:
            return profile.pay_rate
    return 0


@router.get("/earnings/summary")
def earnings_summary(
    period: str = "today",
    user_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
):
    """Aggregate completed-job earnings for the period."""
    db = SessionLocal()
    q = db.query(Photo).filter(
        Photo.status.in_(("completed", "archived")),
        Photo.completed_at.isnot(None),
    )
    if start_date or end_date:
        period = "custom"
        start = _parse_device_ts(start_date)
        if start:
            q = q.filter(Photo.completed_at >= start)
        end = _parse_device_ts(end_date)
        if end:
            end = end.replace(hour=23, minute=59, second=59, microsecond=999999)
            q = q.filter(Photo.completed_at <= end)
    else:
        start = _period_bounds(period)
        q = q.filter(Photo.completed_at >= start)
    if user_id is not None:
        q = q.filter(Photo.user_id == user_id)
    jobs = q.all()
    jobs = _dedupe_by_attempt(jobs)
    total = sum(_earned_pay(j, db) for j in jobs)
    count = len(jobs)

    daily = {}
    for j in jobs:
        day = (_to_pst_iso(j.completed_at) or "")[:10]
        daily[day] = daily.get(day, 0) + _earned_pay(j, db)

    def _job_summary(j):
        if j is None:
            return None
        return {
            "id": j.id,
            "pay_rate": _earned_pay(j, db),
            "profile_name": (j.profiles[0].name if j.profiles else "Unknown"),
            "category": j.category or "standard",
            "address": j.address,
            "completed_at": _to_pst_iso(j.completed_at),
        }

    highest = _job_summary(max(jobs, key=_earned_pay, default=None))
    lowest = _job_summary(min(jobs, key=_earned_pay, default=None))

    finished_ids = set()
    for row in (
        db.query(Photo).filter(Photo.status.in_(("completed", "archived"))).all()
    ):
        if row.profile_id:
            finished_ids.add(row.profile_id)
        if row.attempt_id:
            finished_ids.add(("attempt", row.attempt_id))
    for row in (
        db.query(Attempt).filter(Attempt.status.in_(("completed", "archived"))).all()
    ):
        if row.profile_id:
            finished_ids.add(row.profile_id)
    open_jobs = []
    for p in db.query(Profile).all():
        if _norm_profile_status(p.status) in ("completed", "archived"):
            continue
        if p.id in finished_ids:
            continue
        if _compute_profile_activity_status(db, p) == "completed":
            continue
        pay = p.pay_rate
        if not pay:
            for a in list(getattr(p, "attempts", None) or []):
                if a.pay_rate:
                    pay = a.pay_rate
                    break
        if not pay:
            continue
        open_jobs.append({
            "id": p.id,
            "name": p.name,
            "pay_rate": pay,
        })

    db.close()
    return {
        "period": period,
        "jobs_completed": count,
        "total_earnings": total,
        "available_earnings": sum(j["pay_rate"] for j in open_jobs),
        "open_jobs": open_jobs,
        "average_per_job": round(total / count, 2) if count else 0,
        "highest_paying_job": highest,
        "lowest_paying_job": lowest,
        "daily_totals": [{"date": d, "amount": a} for d, a in sorted(daily.items())],
    }


@router.get("/payouts")
def get_payouts(user_id: Optional[int] = None):
    """Closed-out pins grouped by completion day."""
    db = SessionLocal()
    q = db.query(Photo).filter(
        Photo.status.in_(("completed", "archived")),
        Photo.completed_at.isnot(None),
    )
    if user_id is not None:
        q = q.filter(Photo.user_id == user_id)
    jobs = q.order_by(Photo.completed_at.desc()).all()
    jobs = _dedupe_by_attempt(jobs)

    days = {}
    for j in jobs:
        day = (_to_pst_iso(j.completed_at) or "")[:10]
        bucket = days.setdefault(
            day, {"date": day, "jobs": 0, "amount": 0, "entries": []}
        )
        bucket["jobs"] += 1
        bucket["amount"] += _earned_pay(j, db)
        bucket["entries"].append({
            "id": j.id,
            "profile_name": (j.profiles[0].name if j.profiles else "Unknown"),
            "category": j.category or "standard",
            "pay_rate": _earned_pay(j, db),
            "address": j.address,
            "image_url": j.image_url,
            "completed_at": _to_pst_iso(j.completed_at),
        })
    db.close()

    daily = sorted(days.values(), key=lambda d: d["date"], reverse=True)
    cumulative = 0
    for d in sorted(daily, key=lambda d: d["date"]):
        cumulative += d["amount"]
        d["running_total"] = cumulative
    return {
        "total_earnings": sum(d["amount"] for d in daily),
        "total_jobs": sum(d["jobs"] for d in daily),
        "daily": daily,
    }


@router.post("/payouts/finalize")
async def finalize_payout(data: dict = Body(...)):
    """Snapshot a pay period so historical totals don't drift."""
    db = SessionLocal()
    start = _parse_device_ts(data.get("period_start"))
    end = _parse_device_ts(data.get("period_end"))
    uid = data.get("user_id")
    q = db.query(Photo).filter(
        Photo.status.in_(("completed", "archived")),
        Photo.completed_at.isnot(None),
    )
    if uid is not None:
        q = q.filter(Photo.user_id == uid)
    if start:
        q = q.filter(Photo.completed_at >= start)
    if end:
        q = q.filter(Photo.completed_at <= end)
    jobs = q.all()
    jobs = _dedupe_by_attempt(jobs)
    snap = PayoutPeriod(
        user_id=uid,
        period_start=start,
        period_end=end,
        total_amount=sum(_earned_pay(j, db) for j in jobs),
        jobs_count=len(jobs),
    )
    db.add(snap)
    db.commit()
    db.refresh(snap)
    out = {
        "id": snap.id,
        "total_amount": snap.total_amount,
        "jobs_count": snap.jobs_count,
    }
    db.close()
    return out
