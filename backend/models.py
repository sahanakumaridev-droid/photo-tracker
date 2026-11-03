"""SQLAlchemy ORM models for SRVBoard / Photo-Tracker."""

from __future__ import annotations

from datetime import datetime
from sqlalchemy import (
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Table,
    Text,
)
from sqlalchemy.orm import relationship

from attempt_models import define_attempt_model
from database import Base

# ── Many-to-many: Pin (Photo) <-> Profile ──
pin_profile = Table(
    "pin_profile",
    Base.metadata,
    Column("photo_id", Integer, ForeignKey("photos.id", ondelete="CASCADE"), primary_key=True),
    Column("profile_id", Integer, ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True),
)


class Profile(Base):
    __tablename__ = "profiles"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    service_type = Column(String, default="standard")
    note = Column(Text, nullable=True)
    pay_rate = Column(Integer, nullable=True)
    company = Column(String, nullable=True)
    delivery_style = Column(String, nullable=True)

    status = Column(String, nullable=True)
    address = Column(String, nullable=True)
    city = Column(String, nullable=True)
    state = Column(String, nullable=True)
    postal_code = Column(String, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    file_number = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    photos = relationship("Photo", secondary=pin_profile, back_populates="profiles")
    attempts = relationship(
        "Attempt",
        back_populates="profile",
        cascade="all, delete-orphan",
    )


Attempt = define_attempt_model(Base)


class Photo(Base):
    """Media attached to an Attempt. Attempt-level fields are also mirrored
    here for backward-compatible map/earnings queries."""

    __tablename__ = "photos"
    id = Column(Integer, primary_key=True, index=True)
    image_url = Column(String)
    timestamp = Column(DateTime, default=datetime.utcnow)
    latitude = Column(Float)
    longitude = Column(Float)
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
    profile_id = Column(Integer, nullable=True)
    is_favorited = Column(Integer, nullable=False, default=0)

    attempt_id = Column(
        Integer,
        ForeignKey("attempts.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    location_group_id = Column(Integer, nullable=True, index=True)

    taken_at = Column(DateTime, nullable=True)
    original_timestamp = Column(DateTime, nullable=True)
    edited_timestamp = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    pay_rate = Column(Integer, nullable=True)
    status = Column(String, nullable=False, default="open")
    completed_at = Column(DateTime, nullable=True)
    user_id = Column(Integer, nullable=True)

    profiles = relationship("Profile", secondary=pin_profile, back_populates="photos")
    attempt = relationship("Attempt", back_populates="photos")


class User(Base):
    """Lightweight user record for identity, attribution, and mileage tracking."""

    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, nullable=False)
    name = Column(String, nullable=True)
    role = Column(String, nullable=False, default="field")
    created_at = Column(DateTime, default=datetime.utcnow)
    mileage_total_miles = Column(Float, nullable=False, default=0)
    mileage_last_lat = Column(Float, nullable=True)
    mileage_last_lng = Column(Float, nullable=True)
    mileage_tracking = Column(Integer, nullable=False, default=0)


class MileageDaily(Base):
    """End-of-day (or first ping of next day) snapshot of running mileage."""

    __tablename__ = "mileage_daily"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    day = Column(String, nullable=False, index=True)
    total_miles = Column(Float, nullable=False, default=0)


class EmailRecipient(Base):
    """Saved export recipients (capped at 10 per user)."""

    __tablename__ = "email_recipients"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=True)
    label = Column(String, nullable=True)
    email = Column(String, nullable=False)


class PinDraft(Base):
    """Optional cloud backup of an in-progress pin."""

    __tablename__ = "pin_drafts"
    id = Column(String, primary_key=True)
    user_id = Column(Integer, nullable=True)
    payload = Column(Text, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow)


class TimestampEdit(Base):
    """Audit trail for every timestamp change."""

    __tablename__ = "timestamp_edits"
    id = Column(Integer, primary_key=True, index=True)
    photo_id = Column(Integer, ForeignKey("photos.id", ondelete="CASCADE"))
    old_value = Column(DateTime, nullable=True)
    new_value = Column(DateTime, nullable=True)
    edited_by = Column(Integer, nullable=True)
    edited_at = Column(DateTime, default=datetime.utcnow)


class StatusHistory(Base):
    """Audit trail for every job-status change (open/in_progress/completed/archived)."""

    __tablename__ = "status_history"
    id = Column(Integer, primary_key=True, index=True)
    photo_id = Column(Integer, ForeignKey("photos.id", ondelete="CASCADE"), index=True)
    old_status = Column(String, nullable=True)
    new_status = Column(String, nullable=False)
    updated_by = Column(Integer, nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow)


class PayoutPeriod(Base):
    """Finalized pay-period snapshot."""

    __tablename__ = "payout_periods"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=True)
    period_start = Column(DateTime, nullable=True)
    period_end = Column(DateTime, nullable=True)
    total_amount = Column(Integer, nullable=True)
    jobs_count = Column(Integer, nullable=True)
    finalized_at = Column(DateTime, default=datetime.utcnow)
