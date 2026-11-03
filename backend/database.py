"""Database engine, session factory, and global environment configuration."""

from __future__ import annotations

import os
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

load_dotenv()

PST = ZoneInfo("America/Los_Angeles")

# DATABASE_URL comes from the environment (.env) in production, e.g.
#   postgresql+psycopg2://user:pass@localhost:5432/photo_tracker
# and falls back to a local SQLite file for development.
DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./photo_tracker.db")
if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
else:
    engine = create_engine(DATABASE_URL, pool_pre_ping=True)

SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "https://159-198-79-219.nip.io")
