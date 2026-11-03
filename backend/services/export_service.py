"""Excel (.xlsx) and HTML/text email formatting services."""

from __future__ import annotations

import csv as _csv
from datetime import datetime
import io
import os

from database import PST, PUBLIC_BASE_URL

try:
    from sendgrid import SendGridAPIClient
    from sendgrid.helpers.mail import Mail
except ImportError:
    SendGridAPIClient = None
    Mail = None

try:
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
except ImportError:
    Workbook = None

_EXPORT_COLUMNS = [
    ("id_ctrl", "ID & Cntrl #"),
    ("date_time", "Date & Time"),
    ("service_ordered", "Service Ordered"),
    ("address", "Address"),
    ("coordinates", "Lat / Long"),
    ("detailed_notes", "Detailed Notes"),
]

_EXPORT_COLUMNS_JOB = [
    ("id_ctrl", "ID & Cntrl #"),
    ("date_time", "Date & Time"),
    ("service_ordered", "Service Ordered"),
    ("address", "Address"),
    ("coordinates", "Lat / Long"),
    ("job_status", "Job Status"),
    ("agent", "Agent"),
    ("detailed_notes", "Detailed Notes"),
]

_COL_WIDTHS = {
    "ID & Cntrl #": 24,
    "Date & Time": 22,
    "Service Ordered": 18,
    "Address": 32,
    "Lat / Long": 24,
    "Job Status": 16,
    "Agent": 18,
    "Detailed Notes": 36,
    "File Number": 14,
    "Name": 22,
    "Priority Level": 16,
    "Notes": 36,
    "Photo": 16,
}

_EXPORT_COLUMNS_LIST = [
    ("file_number", "File Number"),
    ("name", "Name"),
    ("date_time", "Date & Time"),
    ("priority_level", "Priority Level"),
    ("address", "Address"),
    ("notes", "Notes"),
]

_EXPORT_COLUMNS_MANUAL = _EXPORT_COLUMNS_LIST + [("photo", "Photo")]

_PRIORITY_LABELS = {
    "asap": "ASAP",
    "rush": "ASAP",
    "next_day": "Next Day",
    "standard": "Standard",
    "special": "Special",
    "airport": "Airport",
}

_SENDER_NAME = os.environ.get("EMAIL_SENDER_NAME", "The GeoTagging CRM Team")


def _priority_label(category):
    return _PRIORITY_LABELS.get((category or "standard").lower(), "Standard")


def _build_xlsx(
    records,
    columns=_EXPORT_COLUMNS,
    sheet_title="Activity Log",
    base_name="log_export",
):
    """Return (bytes, filename) for an .xlsx (or CSV fallback) of the records."""
    if Workbook is None:
        buf = io.StringIO()
        w = _csv.writer(buf)
        w.writerow([h for _, h in columns])
        for r in records:
            w.writerow([r.get(k, "") for k, _ in columns])
        return buf.getvalue().encode(), f"{base_name}.csv"
    wb = Workbook()
    ws = wb.active
    ws.title = sheet_title
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill("solid", fgColor="6366F1")
    for col, (_, label) in enumerate(columns, start=1):
        c = ws.cell(row=1, column=col, value=label)
        c.font = header_font
        c.fill = header_fill
    for ri, r in enumerate(records, start=2):
        for ci, (key, _) in enumerate(columns, start=1):
            ws.cell(row=ri, column=ci, value=r.get(key, ""))
    for col, (_, label) in enumerate(columns, start=1):
        ws.column_dimensions[chr(64 + col)].width = _COL_WIDTHS.get(label, 20)
    bio = io.BytesIO()
    wb.save(bio)
    return bio.getvalue(), f"{base_name}.xlsx"


def _photo_link_cell(ws, row, col, photo_id, wrap):
    """Write a 'View photo' hyperlink into an Excel cell."""
    cell = ws.cell(row=row, column=col)
    if photo_id is not None:
        cell.value = "View photo"
        cell.hyperlink = f"{PUBLIC_BASE_URL}/api/photos/{photo_id}/watermarked"
        cell.font = Font(color="0563C1", underline="single")
    else:
        cell.value = "(no photo)"
    cell.alignment = wrap


def _build_xlsx_with_photos(records):
    """Build the manual-selection .xlsx with a Photo hyperlink column."""
    if Workbook is None:
        return _build_xlsx(
            records,
            _EXPORT_COLUMNS_LIST,
            sheet_title="Profiles Export",
            base_name="profiles_export",
        )

    columns = _EXPORT_COLUMNS_MANUAL
    photo_col = len(columns)

    wb = Workbook()
    ws = wb.active
    ws.title = "Profiles Export"
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill("solid", fgColor="6366F1")
    for col, (_, label) in enumerate(columns, start=1):
        c = ws.cell(row=1, column=col, value=label)
        c.font = header_font
        c.fill = header_fill
        ws.column_dimensions[chr(64 + col)].width = _COL_WIDTHS.get(label, 20)

    wrap = Alignment(wrap_text=True, vertical="top")
    for ri, r in enumerate(records, start=2):
        for ci, (key, _) in enumerate(columns, start=1):
            if key == "photo":
                continue
            cell = ws.cell(row=ri, column=ci, value=r.get(key, ""))
            cell.alignment = wrap
        _photo_link_cell(ws, ri, photo_col, r.get("photo_id"), wrap)

    bio = io.BytesIO()
    wb.save(bio)
    return bio.getvalue(), "profiles_export.xlsx"


def _build_job_xlsx_with_photos(records, photo_ids, base_name="service-record"):
    """Service Record .xlsx with a trailing Photo hyperlink column."""
    if Workbook is None:
        return _build_xlsx(
            records,
            _EXPORT_COLUMNS_JOB,
            sheet_title="Service Record",
            base_name=base_name,
        )

    columns = _EXPORT_COLUMNS_JOB + [("photo", "Photo")]
    photo_col = len(columns)

    wb = Workbook()
    ws = wb.active
    ws.title = "Service Record"
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill("solid", fgColor="6366F1")
    for col, (_, label) in enumerate(columns, start=1):
        c = ws.cell(row=1, column=col, value=label)
        c.font = header_font
        c.fill = header_fill
        ws.column_dimensions[chr(64 + col)].width = _COL_WIDTHS.get(label, 20)

    wrap = Alignment(wrap_text=True, vertical="top")
    for ri, r in enumerate(records, start=2):
        for ci, (key, _) in enumerate(columns, start=1):
            if key == "photo":
                continue
            cell = ws.cell(row=ri, column=ci, value=r.get(key, ""))
            cell.alignment = wrap
        pid = photo_ids[ri - 2] if (ri - 2) < len(photo_ids) else None
        _photo_link_cell(ws, ri, photo_col, pid, wrap)

    bio = io.BytesIO()
    wb.save(bio)
    return bio.getvalue(), f"{base_name}.xlsx"


def _esc(s):
    """Minimal HTML escape for values dropped into the email body."""
    return (
        str(s or "")
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def _pro_email_html(intro, *, sender=None, table_html="", count=None, closing=None):
    """Wrap an export email in a professional layout."""
    when = datetime.now(PST).strftime("%b %d, %Y %I:%M %p PST")
    sign = _esc(sender) if sender else _SENDER_NAME
    meta = f"{count} record(s) &middot; " if count is not None else ""
    closing = closing or (
        "Please find the file attached. If you have any "
        "questions or need anything further, simply reply "
        "to this email."
    )
    return f"""<html><body style="font-family:Arial,Helvetica,sans-serif;color:#0f172a;font-size:14px;line-height:1.6;max-width:660px;margin:0 auto;">
  <p style="margin:0 0 14px;">Hello,</p>
  <p style="margin:0 0 14px;">{intro}</p>
  {table_html}
  <p style="margin:16px 0 14px;">{closing}</p>
  <p style="margin:0;">Best regards,</p>
  <p style="margin:2px 0 0;font-weight:700;">{sign}</p>
  <hr style="border:none;border-top:1px solid #e2e8f0;margin:20px 0 8px;">
  <p style="margin:0;color:#94a3b8;font-size:11px;">{meta}Generated by GeoTagging CRM &middot; {when}</p>
</body></html>"""


def _pro_email_text(intro, *, sender=None, count=None, closing=None):
    """Plain-text sibling of _pro_email_html."""
    sign = sender or _SENDER_NAME
    meta = f"{count} record(s)\n" if count is not None else ""
    closing = closing or (
        "Please find the file attached. If you have any "
        "questions or need anything further, simply reply "
        "to this email."
    )
    return (
        f"Hello,\n\n{intro}\n\n{closing}\n\n"
        f"Best regards,\n{sign}\n\n"
        f"{meta}Generated by GeoTagging CRM"
    )


def _fmt_note_stamp(date_time):
    """'YYYY-MM-DD HH:MM:SS' -> 'hh:mm am  -  MM/DD/YYYY'. Falls back to raw."""
    raw = str(date_time or "").strip()
    if not raw:
        return ""
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            dt = datetime.strptime(raw, fmt)
            return f"{dt.strftime('%I:%M %p').lower().lstrip('0')}  -  {dt.strftime('%m/%d/%Y')}"
        except (ValueError, TypeError):
            continue
    return raw


def _build_records_export_html(records):
    """Build the profiles-export email body with inline watermarked photos."""
    records = records or []
    blocks = []
    for rec in records:
        rows = [
            ("File Number", _esc(rec.get("file_number")) or "—"),
            ("Name", _esc(rec.get("name")) or "—"),
            ("Date & Time", _esc(rec.get("date_time")) or "—"),
            ("Priority Level", _esc(rec.get("priority_level")) or "—"),
            ("Address", _esc(rec.get("address")) or "—"),
        ]
        if rec.get("coordinates"):
            rows.append(("Lat / Long", _esc(rec.get("coordinates"))))
        rows_html = "".join(
            f'<tr><td style="padding:2px 12px 2px 0;color:#64748b;white-space:nowrap;">'
            f'{label}:</td><td style="padding:2px 0;color:#0f172a;font-weight:600;">'
            f'{value}</td></tr>'
            for label, value in rows
        )
        notes = (rec.get("notes") or "").strip()
        notes_html = (
            _esc(notes)
            if notes
            else '<span style="color:#94a3b8;">No notes recorded.</span>'
        )

        photo_html = ""
        photo_id = rec.get("photo_id")
        if photo_id is not None:
            photo_html = (
                f'<img src="cid:photo_{photo_id}" alt="Service photo" '
                f'style="max-width:100%;border-radius:8px;display:block;margin-top:10px;">'
            )

        blocks.append(f"""\
<table style="border-collapse:collapse;font-size:14px;margin:0 0 8px;">{rows_html}</table>
<div style="margin:0 0 4px;color:#334155;font-weight:700;font-size:13px;">Notes</div>
<div style="margin:0 0 10px;color:#0f172a;line-height:1.5;">{notes_html}</div>
{photo_html}""")

    separator = '<hr style="border:none;border-top:1px solid #e2e8f0;margin:20px 0;">'
    body = separator.join(blocks) if blocks else "<p>No records to export.</p>"
    return (
        f'<div style="font-family:Arial,Helvetica,sans-serif;color:#0f172a;'
        f'max-width:640px;">{body}</div>'
    )


def _build_service_record_html(records, header=None, latest_only=False, photo_id=None):
    """Build the single-profile service-record email body."""
    records = records or []
    header = header or {}
    latest = records[0] if records else {}

    def hv(key, fallback_key=None, default="—"):
        v = header.get(key)
        if not v and fallback_key:
            v = latest.get(fallback_key)
        return _esc(v) if v else default

    rows = [
        ("File Number", hv("file_number")),
        ("Name", hv("name", "id_ctrl")),
        ("Date & Time", hv("date_time", "date_time")),
        ("Priority Level", hv("priority_level", "service_ordered", "Standard")),
        ("Address", hv("address", "address")),
        ("Lat / Long", hv("coordinates", "coordinates")),
    ]
    header_html = "".join(
        f'<tr><td style="padding:2px 12px 2px 0;color:#64748b;white-space:nowrap;">'
        f'{label}:</td><td style="padding:2px 0;color:#0f172a;font-weight:600;">'
        f'{value}</td></tr>'
        for label, value in rows
    )

    note_records = [latest] if latest_only else list(reversed(records))
    note_lines = []
    for r in note_records:
        note = (r.get("detailed_notes") or r.get("notes") or "").strip()
        if not note:
            continue
        stamp = _fmt_note_stamp(r.get("date_time"))
        prefix = f"{stamp}  -  " if stamp else ""
        note_lines.append(
            f'<div style="margin:0 0 10px;color:#0f172a;line-height:1.5;">'
            f'<span style="color:#475569;">{_esc(prefix)}</span>{_esc(note)}</div>'
        )
    notes_html = (
        "".join(note_lines)
        or '<div style="color:#94a3b8;">No notes recorded.</div>'
    )

    photo_html = ""
    if photo_id is not None:
        photo_html = (
            f'<h3 style="margin:20px 0 10px;font-size:14px;letter-spacing:0.4px;'
            f'color:#334155;">Photo</h3>'
            f'<img src="cid:photo_{photo_id}" alt="Service photo" '
            f'style="max-width:100%;border-radius:8px;display:block;">'
        )

    return f"""\
<div style="font-family:Arial,Helvetica,sans-serif;color:#0f172a;max-width:640px;">
  <table style="border-collapse:collapse;font-size:14px;margin:0 0 16px;">{header_html}</table>
  <h3 style="margin:0 0 12px;font-size:14px;letter-spacing:0.4px;color:#334155;">Notes</h3>
  {notes_html}
  {photo_html}
</div>"""
