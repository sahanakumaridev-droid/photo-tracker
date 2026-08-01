"""Attempt entity: Profile 1──* Attempt 1──* Photo.

Photos are media attached to an attempt. Attempt holds location, status,
served_to, notes, etc. Existing photos are backfilled into attempts
(grouped by profile + location_group_id when possible).
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.orm import relationship


def define_attempt_model(Base):
    """Register the Attempt ORM class on the shared Base."""

    class Attempt(Base):
        __tablename__ = "attempts"

        id = Column(Integer, primary_key=True, index=True)
        profile_id = Column(
            Integer, ForeignKey("profiles.id", ondelete="CASCADE"),
            nullable=False, index=True,
        )

        # Attempt location (GPS at capture) — independent of Profile Location.
        latitude = Column(Float, nullable=True)
        longitude = Column(Float, nullable=True)
        zip_code = Column(String, nullable=True)
        address = Column(Text, nullable=True)

        note = Column(Text, nullable=True)
        category = Column(String, nullable=True, default="standard")
        completion_type = Column(String, nullable=True)
        served_to = Column(String, nullable=True)
        relation_to = Column(String, nullable=True)
        file_number = Column(String, nullable=True)

        successful = Column(Integer, nullable=False, default=0)
        attempt_status = Column(String, nullable=False, default="pending")

        pay_rate = Column(Integer, nullable=True)
        status = Column(String, nullable=False, default="in_progress")
        completed_at = Column(DateTime, nullable=True)
        user_id = Column(Integer, nullable=True)
        location_group_id = Column(Integer, nullable=True, index=True)

        taken_at = Column(DateTime, nullable=True)
        original_timestamp = Column(DateTime, nullable=True)
        edited_timestamp = Column(DateTime, nullable=True)
        timestamp = Column(DateTime, default=datetime.utcnow)
        created_at = Column(DateTime, default=datetime.utcnow)

        profile = relationship("Profile", back_populates="attempts")
        photos = relationship(
            "Photo", back_populates="attempt",
            cascade="all, delete-orphan",
            order_by="Photo.id",
        )

    return Attempt


def ensure_attempts_schema(engine, Base, Attempt, Photo, pin_profile):
    """Create attempts table, add photos.attempt_id, backfill from photos."""
    from sqlalchemy import inspect

    Base.metadata.create_all(bind=engine)
    inspector = inspect(engine)
    is_pg = engine.dialect.name == "postgresql"
    DT = "TIMESTAMP" if is_pg else "DATETIME"

    with engine.connect() as conn:
        photo_cols = {c["name"] for c in inspector.get_columns("photos")}
        if "attempt_id" not in photo_cols:
            try:
                # SQLite can't easily add FK; plain INTEGER is enough for app use.
                conn.execute(text(
                    "ALTER TABLE photos ADD COLUMN attempt_id INTEGER"
                ))
                conn.commit()
            except Exception as e:
                conn.rollback()
                print(f"[migrate] skip photos.attempt_id: {e}")

        # Refresh inspector after ALTER
        inspector = inspect(engine)
        if "attempts" not in inspector.get_table_names():
            Base.metadata.create_all(bind=engine)

        # Backfill: one Attempt per (profile, location_group) or per photo.
        # Use raw SQL via ORM session in caller for portability.
    return True


def backfill_attempts(db, Attempt, Photo, pin_profile):
    """Create Attempt rows for photos missing attempt_id.

    Groups photos that share the same profile + location_group_id into one
    Attempt (multi-photo attempt). Orphans become 1:1 attempts.
    """
    # Find photos without an attempt
    orphans = (
        db.query(Photo)
        .filter((Photo.attempt_id.is_(None)) | (Photo.attempt_id == 0))
        .order_by(Photo.id.asc())
        .all()
    )
    if not orphans:
        return 0

    # Resolve profile_id for each photo
    def _profile_id(ph):
        if ph.profiles:
            return ph.profiles[0].id
        return ph.profile_id

    # Group key → list of photos
    groups = {}
    for ph in orphans:
        pid = _profile_id(ph)
        if not pid:
            continue
        grp = ph.location_group_id or ph.id
        key = (pid, grp)
        groups.setdefault(key, []).append(ph)

    created = 0
    for (pid, grp), photos in groups.items():
        primary = photos[0]
        attempt_st = (getattr(primary, "attempt_status", None) or "").strip().lower()
        if attempt_st not in ("pending", "successful", "unsuccessful"):
            attempt_st = "successful" if primary.successful else "pending"
        attempt = Attempt(
            profile_id=pid,
            latitude=primary.latitude,
            longitude=primary.longitude,
            zip_code=primary.zip_code,
            address=primary.address,
            note=primary.note,
            category=primary.category or "standard",
            completion_type=primary.completion_type,
            served_to=primary.served_to,
            relation_to=primary.relation_to,
            file_number=primary.file_number,
            successful=1 if attempt_st == "successful" else 0,
            attempt_status=attempt_st,
            pay_rate=primary.pay_rate,
            status=primary.status or "in_progress",
            completed_at=primary.completed_at,
            user_id=primary.user_id,
            location_group_id=grp,
            taken_at=primary.taken_at or primary.timestamp,
            original_timestamp=primary.original_timestamp or primary.taken_at,
            edited_timestamp=primary.edited_timestamp,
            timestamp=primary.timestamp or datetime.utcnow(),
            created_at=primary.created_at or datetime.utcnow(),
        )
        db.add(attempt)
        db.flush()
        for ph in photos:
            ph.attempt_id = attempt.id
        created += 1

    if created:
        db.commit()
    return created
