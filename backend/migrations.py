"""Database startup migrations and schema backfill routines."""

from __future__ import annotations

from sqlalchemy import inspect, text

from attempt_models import backfill_attempts, ensure_attempts_schema
from database import Base, SessionLocal, engine
from models import Attempt, Photo, Profile, pin_profile
from services.profile_service import _advance_profile_status


def _ensure_columns():
    """Lightweight migration: add columns introduced after initial table creation."""
    inspector = inspect(engine)
    is_pg = engine.dialect.name == "postgresql"
    dt_type = "TIMESTAMP" if is_pg else "DATETIME"
    existing = {c["name"] for c in inspector.get_columns("photos")}
    new_cols = {
        "category": "VARCHAR DEFAULT 'standard'",
        "is_favorited": "INTEGER NOT NULL DEFAULT 0",
        "location_group_id": "INTEGER",
        "taken_at": dt_type,
        "original_timestamp": dt_type,
        "edited_timestamp": dt_type,
        "pay_rate": "INTEGER",
        "completion_type": "VARCHAR",
        "served_to": "VARCHAR",
        "status": "VARCHAR NOT NULL DEFAULT 'open'",
        "completed_at": dt_type,
        "user_id": "INTEGER",
        "created_at": dt_type,
        "relation_to": "VARCHAR",
        "file_number": "VARCHAR",
        "successful": "INTEGER NOT NULL DEFAULT 0",
        "attempt_status": "VARCHAR NOT NULL DEFAULT 'pending'",
        "attempt_id": "INTEGER",
    }
    with engine.connect() as conn:
        for col, ddl in new_cols.items():
            if col not in existing:
                try:
                    conn.execute(text(f"ALTER TABLE photos ADD COLUMN {col} {ddl}"))
                    conn.commit()
                except Exception as e:
                    conn.rollback()
                    print(f"[migrate] skip photos.{col}: {e}")

        conn.execute(text("UPDATE photos SET taken_at = timestamp WHERE taken_at IS NULL"))
        conn.execute(
            text("UPDATE photos SET original_timestamp = timestamp WHERE original_timestamp IS NULL")
        )
        conn.execute(
            text("UPDATE photos SET location_group_id = id WHERE location_group_id IS NULL")
        )
        conn.execute(text("UPDATE photos SET status = 'in_progress' WHERE status IS NULL"))
        conn.execute(
            text(
                "UPDATE photos SET completed_at = COALESCE(edited_timestamp, taken_at, timestamp) "
                "WHERE status IN ('archived', 'completed') AND completed_at IS NULL"
            )
        )
        conn.commit()
        conn.execute(
            text(
                "UPDATE photos SET created_at = COALESCE(original_timestamp, timestamp) "
                "WHERE created_at IS NULL"
            )
        )
        try:
            conn.execute(
                text(
                    "UPDATE photos SET attempt_status = CASE "
                    "WHEN successful = 1 THEN 'successful' "
                    "WHEN successful = 0 THEN 'unsuccessful' "
                    "ELSE 'pending' END "
                    "WHERE attempt_status IS NULL OR attempt_status = ''"
                )
            )
            conn.commit()
        except Exception as e:
            conn.rollback()
            print(f"[migrate] skip attempt_status backfill: {e}")
        conn.commit()

        existing_profiles = {c["name"] for c in inspector.get_columns("profiles")}
        if "pay_rate" not in existing_profiles:
            try:
                conn.execute(text("ALTER TABLE profiles ADD COLUMN pay_rate INTEGER"))
                conn.commit()
            except Exception as e:
                conn.rollback()
                print(f"[migrate] skip profiles.pay_rate: {e}")

        profile_new_cols = {
            "status": "VARCHAR",
            "address": "VARCHAR",
            "city": "VARCHAR",
            "state": "VARCHAR",
            "postal_code": "VARCHAR",
            "latitude": "FLOAT" if not is_pg else "DOUBLE PRECISION",
            "longitude": "FLOAT" if not is_pg else "DOUBLE PRECISION",
            "created_at": dt_type,
            "updated_at": dt_type,
            "company": "VARCHAR",
            "delivery_style": "VARCHAR",
            "file_number": "VARCHAR",
        }
        for col, ddl in profile_new_cols.items():
            if col not in existing_profiles:
                try:
                    conn.execute(text(f"ALTER TABLE profiles ADD COLUMN {col} {ddl}"))
                    conn.commit()
                except Exception as e:
                    conn.rollback()
                    print(f"[migrate] skip profiles.{col}: {e}")

        if inspector.has_table("users"):
            existing_users = {c["name"] for c in inspector.get_columns("users")}
            user_new_cols = {
                "mileage_total_miles": "FLOAT NOT NULL DEFAULT 0",
                "mileage_last_lat": "FLOAT",
                "mileage_last_lng": "FLOAT",
                "mileage_tracking": "INTEGER NOT NULL DEFAULT 0",
            }
            for col, ddl in user_new_cols.items():
                if col not in existing_users:
                    try:
                        conn.execute(text(f"ALTER TABLE users ADD COLUMN {col} {ddl}"))
                        conn.commit()
                    except Exception as e:
                        conn.rollback()
                        print(f"[migrate] skip users.{col}: {e}")


def run_startup_migrations():
    """Run all idempotent schema checks and data backfills on startup."""
    Base.metadata.create_all(bind=engine)
    _ensure_columns()
    try:
        ensure_attempts_schema(engine, Base, Attempt, Photo, pin_profile)
        bf_db = SessionLocal()
        try:
            n = backfill_attempts(bf_db, Attempt, Photo, pin_profile)
            if n:
                print(f"[migrate] backfilled {n} attempt(s) from photos")
        finally:
            bf_db.close()
    except Exception as e:
        print(f"[migrate] attempts backfill skipped: {e}")

    try:
        lc_db = SessionLocal()
        try:
            for p in lc_db.query(Profile).all():
                _advance_profile_status(lc_db, p)
            lc_db.commit()
        finally:
            lc_db.close()
    except Exception as e:
        print(f"[migrate] profile lifecycle backfill skipped: {e}")
