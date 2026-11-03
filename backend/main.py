"""FastAPI application entry point for SRVBoard / Photo-Tracker."""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from database import (
    Base,
    DATABASE_URL,
    PST,
    PUBLIC_BASE_URL,
    SessionLocal,
    UPLOAD_DIR,
    engine,
)
from migrations import run_startup_migrations
from models import (
    Attempt,
    EmailRecipient,
    MileageDaily,
    PayoutPeriod,
    Photo,
    PinDraft,
    Profile,
    StatusHistory,
    TimestampEdit,
    User,
    pin_profile,
)
from routes.earnings_mileage import router as earnings_mileage_router
from routes.exports import router as exports_router
from routes.locations_schedule import router as locations_schedule_router
from routes.photos import router as photos_router
from routes.profiles import router as profiles_router
from routes.users_drafts import router as users_drafts_router
from routes.workflow import router as workflow_router

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def rewrite_api_prefix(request: Request, call_next):
    if request.scope["path"].startswith("/api/"):
        request.scope["path"] = request.scope["path"][4:]
    return await call_next(request)


app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

run_startup_migrations()

app.include_router(profiles_router)
app.include_router(photos_router)
app.include_router(locations_schedule_router)
app.include_router(workflow_router)
app.include_router(earnings_mileage_router)
app.include_router(exports_router)
app.include_router(users_drafts_router)
