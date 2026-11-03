"""Server-side photo watermarking and inline email attachment builders."""

from __future__ import annotations

import base64
import io
import os
import re

from database import SessionLocal
from models import Photo, Profile
from serializers import _to_pst_iso

_BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_FONT_DIR = os.path.join(_BACKEND_DIR, "fonts")
_FONT_PATHS = [
    os.path.join(_FONT_DIR, "DejaVuSans-Bold.ttf"),
    os.path.join(_FONT_DIR, "DejaVuSans.ttf"),
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "DejaVuSans-Bold.ttf",
]


def _load_font(size):
    from PIL import ImageFont

    for p in _FONT_PATHS:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default(size=size)


def _watermark_photo_png(image_path, caption_lines, max_w=300, max_h=400):
    """Return (png_bytes, width_px, height_px) with timestamp + geotag burned in."""
    try:
        from PIL import Image as PILImage, ImageDraw, ImageFile, ImageOps

        ImageFile.LOAD_TRUNCATED_IMAGES = True
    except Exception:
        return None
    try:
        img = PILImage.open(image_path)
        img = ImageOps.exif_transpose(img).convert("RGB")
    except Exception:
        return None

    ratio = min(max_w / img.width, max_h / img.height, 1.0)
    if ratio < 1.0:
        img = img.resize(
            (max(1, int(img.width * ratio)), max(1, int(img.height * ratio)))
        )
    draw = ImageDraw.Draw(img, "RGBA")
    fsize = max(12, min(40, img.width // 34))
    font = _load_font(fsize)
    lines = [ln for ln in caption_lines if ln]
    if lines:
        pad = max(6, fsize // 2)
        line_h = fsize + max(4, fsize // 3)
        box_h = pad * 2 + line_h * len(lines)
        draw.rectangle(
            [0, img.height - box_h, img.width, img.height],
            fill=(0, 0, 0, 160),
        )
        y = img.height - box_h + pad
        for ln in lines:
            bbox = draw.textbbox((0, 0), ln, font=font)
            tw = bbox[2] - bbox[0]
            x = max(0, (img.width - tw) / 2)
            draw.text((x + 2, y + 2), ln, fill=(0, 0, 0, 200), font=font)
            draw.text((x, y), ln, fill=(255, 255, 255, 255), font=font)
            y += line_h
    out = io.BytesIO()
    img.save(out, format="PNG")
    return out.getvalue(), img.width, img.height


def _street_zip(address, zip_code=None):
    """Full location for watermarks and email: street, city, state, ZIP."""
    full = re.sub(r"\s+", " ", (address or "").strip())
    zip_val = (zip_code or "").strip()
    if not zip_val:
        m = re.search(r"\b\d{5}(?:-\d{4})?\b", full)
        zip_val = m.group(0) if m else ""
    if not full:
        return zip_val
    if zip_val and not re.search(rf"\b{re.escape(zip_val)}\b", full):
        return f"{full}, {zip_val}"
    return full


def _is_file_number_na(value):
    v = (value or "").strip()
    return not v or v.upper() == "N/A"


def _photo_caption(ph):
    """Caption lines burned into an exported photo."""
    lines = []
    file_no = (ph.file_number or "").strip()
    if not _is_file_number_na(file_no):
        lines.append(file_no)
    else:
        name = ""
        try:
            if ph.profiles:
                name = (ph.profiles[0].name or "").strip()
        except Exception:
            name = ""
        if not name and ph.profile_id:
            try:
                db = SessionLocal()
                prof = db.query(Profile).filter(Profile.id == ph.profile_id).first()
                name = (prof.name or "").strip() if prof else ""
                db.close()
            except Exception:
                name = ""
        if name:
            lines.append(name)
    ts = _to_pst_iso(ph.taken_at or ph.timestamp)
    if ts:
        lines.append(ts.replace("T", " ")[:16] + " PST")
    street_zip = _street_zip(ph.address, ph.zip_code)
    if street_zip:
        lines.append(street_zip)
    if ph.latitude is not None and ph.longitude is not None:
        if abs(ph.latitude) > 0.0001 or abs(ph.longitude) > 0.0001:
            lines.append(f"{ph.latitude:.6f}, {ph.longitude:.6f}")
    return lines


def _job_photo_caption(rec):
    """Caption lines burned into a service-record photo from an export record."""
    lines = []
    file_no = (rec.get("file_number") or "").strip()
    if not _is_file_number_na(file_no):
        heading = file_no
    else:
        heading = (rec.get("profile_name") or "").strip()
    if heading:
        lines.append(heading)
    if rec.get("date_time"):
        lines.append(str(rec["date_time"]))
    if rec.get("address"):
        lines.append(str(rec["address"]))
    if rec.get("coordinates"):
        lines.append(str(rec["coordinates"]))
    if rec.get("agent"):
        lines.append(f"Agent: {rec['agent']}")
    return [ln for ln in lines if ln]


def _get_watermarked_bytes(photo_id, max_w=800, max_h=800):
    """Fetch + watermark a photo's bytes directly."""
    db = SessionLocal()
    ph = db.query(Photo).filter(Photo.id == photo_id).first()
    if not ph or not ph.image_url:
        db.close()
        return None
    caption = _photo_caption(ph)
    path = ph.image_url.lstrip("/")
    db.close()
    if not os.path.exists(path):
        return None
    stamped = _watermark_photo_png(path, caption, max_w=max_w, max_h=max_h)
    return stamped[0] if stamped else None


def _watermarked_photo_payloads(photo_ids, max_w=1600, max_h=1600):
    """[{filename, content_b64, mimetype}] for each photo id."""
    payloads = []
    for pid in photo_ids or []:
        img_bytes = _get_watermarked_bytes(pid, max_w=max_w, max_h=max_h)
        if not img_bytes:
            continue
        payloads.append({
            "filename": f"photo_{pid}.png",
            "content_b64": base64.b64encode(img_bytes).decode(),
            "mimetype": "image/png",
        })
    return payloads


def _sendgrid_inline_attachments(photo_ids, max_w=800, max_h=800):
    """SendGrid Attachment objects (inline, Content-ID) for the given photo ids."""
    from sendgrid.helpers.mail import (
        Attachment,
        ContentId,
        Disposition,
        FileContent,
        FileName,
        FileType,
    )

    atts = []
    for pid in photo_ids:
        img_bytes = _get_watermarked_bytes(pid, max_w=max_w, max_h=max_h)
        if not img_bytes:
            continue
        atts.append(
            Attachment(
                FileContent(base64.b64encode(img_bytes).decode()),
                FileName(f"photo_{pid}.png"),
                FileType("image/png"),
                Disposition("inline"),
                ContentId(f"photo_{pid}"),
            )
        )
    return atts


def _smtp_inline_photo_parts(photo_ids, max_w=800, max_h=800):
    """MIMEImage parts (inline, Content-ID) for the given photo ids."""
    from email.mime.image import MIMEImage

    parts = []
    for pid in photo_ids:
        img_bytes = _get_watermarked_bytes(pid, max_w=max_w, max_h=max_h)
        if not img_bytes:
            continue
        img = MIMEImage(img_bytes, _subtype="png")
        img.add_header("Content-ID", f"<photo_{pid}>")
        img.add_header("Content-Disposition", "inline", filename=f"photo_{pid}.png")
        parts.append(img)
    return parts
