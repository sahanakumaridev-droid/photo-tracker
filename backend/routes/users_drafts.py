"""Cloud drafts, saved email recipients, and user identity routes."""

from __future__ import annotations

from datetime import datetime
import json
from typing import Optional
import uuid

from fastapi import APIRouter, Body, HTTPException

from database import SessionLocal
from models import EmailRecipient, PinDraft, User
from serializers import _to_pst_iso

router = APIRouter()


@router.put("/drafts")
async def save_draft(data: dict = Body(...)):
    """Upsert a pin draft (continuous autosave from mobile)."""
    draft_id = data.get("id") or str(uuid.uuid4())
    db = SessionLocal()
    draft = db.query(PinDraft).filter(PinDraft.id == draft_id).first()
    if not draft:
        draft = PinDraft(id=draft_id)
        db.add(draft)
    draft.user_id = data.get("user_id")
    draft.payload = json.dumps(data.get("payload", {}))
    draft.updated_at = datetime.utcnow()
    db.commit()
    db.close()
    return {"ok": True, "id": draft_id}


@router.get("/drafts")
def list_drafts(user_id: Optional[int] = None):
    db = SessionLocal()
    q = db.query(PinDraft)
    if user_id is not None:
        q = q.filter(PinDraft.user_id == user_id)
    drafts = q.order_by(PinDraft.updated_at.desc()).all()
    out = [
        {
            "id": d.id,
            "user_id": d.user_id,
            "payload": json.loads(d.payload or "{}"),
            "updated_at": _to_pst_iso(d.updated_at),
        }
        for d in drafts
    ]
    db.close()
    return out


@router.delete("/drafts/{draft_id}")
def delete_draft(draft_id: str):
    db = SessionLocal()
    draft = db.query(PinDraft).filter(PinDraft.id == draft_id).first()
    if draft:
        db.delete(draft)
        db.commit()
    db.close()
    return {"ok": True}


@router.get("/recipients")
def list_recipients(user_id: Optional[int] = None):
    db = SessionLocal()
    q = db.query(EmailRecipient)
    if user_id is not None:
        q = q.filter(EmailRecipient.user_id == user_id)
    rows = q.all()
    out = [
        {"id": r.id, "label": r.label, "email": r.email, "user_id": r.user_id}
        for r in rows
    ]
    db.close()
    return out


@router.post("/recipients")
async def add_recipient(data: dict = Body(...)):
    email = (data.get("email") or "").strip()
    if "@" not in email:
        raise HTTPException(status_code=422, detail="Valid email required")
    db = SessionLocal()
    uid = data.get("user_id")
    count = (
        db.query(EmailRecipient).filter(EmailRecipient.user_id == uid).count()
    )
    if count >= 10:
        db.close()
        raise HTTPException(
            status_code=422, detail="Maximum of 10 saved recipients reached"
        )
    r = EmailRecipient(
        user_id=uid,
        label=(data.get("label") or "").strip() or None,
        email=email,
    )
    db.add(r)
    db.commit()
    db.refresh(r)
    out = {"id": r.id, "label": r.label, "email": r.email}
    db.close()
    return out


@router.patch("/recipients/{rid}")
async def edit_recipient(rid: int, data: dict = Body(...)):
    db = SessionLocal()
    r = db.query(EmailRecipient).filter(EmailRecipient.id == rid).first()
    if not r:
        db.close()
        raise HTTPException(status_code=404, detail="Recipient not found")
    if "email" in data:
        r.email = data["email"].strip()
    if "label" in data:
        r.label = (data["label"] or "").strip() or None
    db.commit()
    out = {"id": r.id, "label": r.label, "email": r.email}
    db.close()
    return out


@router.delete("/recipients/{rid}")
def delete_recipient(rid: int):
    db = SessionLocal()
    r = db.query(EmailRecipient).filter(EmailRecipient.id == rid).first()
    if r:
        db.delete(r)
        db.commit()
    db.close()
    return {"ok": True}


@router.get("/users")
def list_users():
    db = SessionLocal()
    users = db.query(User).all()
    out = [
        {"id": u.id, "email": u.email, "name": u.name, "role": u.role}
        for u in users
    ]
    db.close()
    return out


@router.post("/users")
async def create_user(data: dict = Body(...)):
    email = (data.get("email") or "").strip()
    if "@" not in email:
        raise HTTPException(status_code=422, detail="Valid email required")
    db = SessionLocal()
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        out = {
            "id": existing.id,
            "email": existing.email,
            "name": existing.name,
            "role": existing.role,
        }
        db.close()
        return out
    u = User(
        email=email,
        name=(data.get("name") or "").strip() or None,
        role=data.get("role", "field"),
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    out = {"id": u.id, "email": u.email, "name": u.name, "role": u.role}
    db.close()
    return out
