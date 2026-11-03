"""Email, Excel, job service-record, and PDF export routes."""

from __future__ import annotations

import base64
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import json
import os
import smtplib

from fastapi import APIRouter, HTTPException, Request

from services.export_service import (
    Mail,
    SendGridAPIClient,
    _build_records_export_html,
    _build_service_record_html,
    _build_xlsx_with_photos,
    _pro_email_html,
)
from services.watermark_service import (
    _sendgrid_inline_attachments,
    _smtp_inline_photo_parts,
    _watermarked_photo_payloads,
)

router = APIRouter()


@router.post("/export/email")
async def export_log_email(request: Request):
    """Send a log export to an email address."""
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        data = await request.json()
        to_email = data.get("to", "").strip()
        records_list = data.get("records", [])
    else:
        form = await request.form()
        to_email = (form.get("to") or "").strip()
        try:
            records_list = json.loads(form.get("records", "[]"))
        except Exception:
            records_list = []

    if not to_email:
        raise HTTPException(status_code=422, detail="Email address required")

    category_meta = {
        "standard": ("Standard", "#059669"),
        "special": ("Special", "#EA580C"),
        "next_day": ("Next Day", "#CA8A04"),
        "asap": ("ASAP", "#DC2626"),
    }

    rows_html = ""
    for r in records_list:
        cat_label, cat_color = category_meta.get(
            (r.get("category") or "standard").lower(),
            category_meta["standard"],
        )
        profiles = ", ".join(p["name"] for p in r.get("profiles", [])) or r.get(
            "profile_name", "—"
        )
        lat = r.get("latitude", "")
        lng = r.get("longitude", "")
        coords = (
            f"{lat:.4f}, {lng:.4f}"
            if isinstance(lat, (int, float)) and isinstance(lng, (int, float))
            else "—"
        )
        address = r.get("address") or "—"
        if (
            r.get("address")
            and r.get("zip_code")
            and r["zip_code"] not in r["address"]
        ):
            address = f"{r['address']}, {r['zip_code']}"
        elif r.get("address"):
            address = r["address"]
        rows_html += f"""
        <tr>
          <td>{r.get('timestamp','—')}</td>
          <td>{profiles}</td>
          <td>{r.get('service_type','—').upper()}</td>
          <td><span style="color:{cat_color};font-weight:700;">{cat_label}</span></td>
          <td>{address}</td>
          <td>{coords}</td>
          <td>{r.get('note','—')}</td>
        </tr>"""

    table_html = f"""
    <table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%;font-size:13px;">
      <thead style="background:#f1f5f9;">
        <tr>
          <th>Timestamp (PST)</th><th>Profile(s)</th><th>Status</th>
          <th>Category</th><th>Address</th><th>Coordinates</th><th>Note</th>
        </tr>
      </thead>
      <tbody>{rows_html}</tbody>
    </table>"""
    html = _pro_email_html(
        f"Please find the GeoTagging CRM activity log you requested below, "
        f"containing {len(records_list)} record(s). All times are shown in PST.",
        table_html=table_html,
        count=len(records_list),
        closing="A summary of the exported records is included above. If you "
        "have any questions or need anything further, simply reply to "
        "this email.",
    )

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    sg_api_key = os.environ.get("SENDGRID_API_KEY")
    sg_sender = os.environ.get("SENDGRID_SENDER_EMAIL")

    if not sg_api_key and (not smtp_host or not smtp_user):
        return {
            "ok": True,
            "message": "Email not configured — export data returned",
            "html": html,
            "count": len(records_list),
        }

    try:
        if sg_api_key and SendGridAPIClient and Mail:
            if not sg_sender:
                raise HTTPException(
                    status_code=500,
                    detail="SENDGRID_SENDER_EMAIL is required in environment variables when using SendGrid.",
                )
            message = Mail(
                from_email=sg_sender,
                to_emails=to_email,
                subject=f"GeoTagging Log Export — {len(records_list)} records",
                html_content=html,
            )
            sg = SendGridAPIClient(sg_api_key)
            sg.send(message)
            return {
                "ok": True,
                "message": f"Log exported to {to_email} via SendGrid",
                "count": len(records_list),
            }
        else:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = f"GeoTagging Log Export — {len(records_list)} records"
            msg["From"] = smtp_user
            msg["To"] = to_email
            msg.attach(MIMEText(html, "html"))

            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, to_email, msg.as_string())

            return {
                "ok": True,
                "message": f"Log exported to {to_email} via SMTP",
                "count": len(records_list),
            }
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Email send failed: {str(e)}"
        )


@router.post("/export/excel")
async def export_excel(request: Request):
    """Email the selected profiles to one or more recipients."""
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        data = await request.json()
        recipients = data.get("recipients") or (
            [data["to"]] if data.get("to") else []
        )
        records = data.get("records", [])
    else:
        form = await request.form()
        recipients = json.loads(form.get("recipients", "[]")) or (
            [form.get("to")] if form.get("to") else []
        )
        try:
            records = json.loads(form.get("records", "[]"))
        except Exception:
            records = []

    recipients = [e.strip() for e in recipients if e and "@" in e]
    if not recipients:
        raise HTTPException(
            status_code=422, detail="At least one recipient email required"
        )

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    sg_api_key = os.environ.get("SENDGRID_API_KEY")
    sg_sender = os.environ.get("SENDGRID_SENDER_EMAIL")

    photo_ids = [
        r["photo_id"] for r in records if r.get("photo_id") is not None
    ]
    body_html = _build_records_export_html(records)
    file_bytes, fname = _build_xlsx_with_photos(records)
    b64 = base64.b64encode(file_bytes).decode()
    if len(records) == 1:
        rec = records[0]
        subject = f"GeoTagging CRM — {rec.get('name') or 'Profile'} Export"
    else:
        subject = f"GeoTagging CRM — Profiles Export ({len(records)} records)"

    if not sg_api_key and (not smtp_host or not smtp_user):
        return {
            "ok": True,
            "message": "Email not configured — file returned",
            "filename": fname,
            "file_base64": b64,
            "count": len(records),
        }

    try:
        if sg_api_key and SendGridAPIClient and Mail:
            message = Mail(
                from_email=sg_sender,
                to_emails=recipients,
                subject=subject,
                html_content=body_html,
            )
            for att in _sendgrid_inline_attachments(photo_ids):
                message.add_attachment(att)
            SendGridAPIClient(sg_api_key).send(message)
            return {
                "ok": True,
                "message": f"Export sent to {', '.join(recipients)}",
                "count": len(records),
            }
        else:
            msg = MIMEMultipart("mixed")
            msg["Subject"] = subject
            msg["From"] = smtp_user
            msg["To"] = ", ".join(recipients)
            related = MIMEMultipart("related")
            alt = MIMEMultipart("alternative")
            alt.attach(MIMEText(body_html, "html"))
            related.attach(alt)
            for part in _smtp_inline_photo_parts(photo_ids):
                related.attach(part)
            msg.attach(related)
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, recipients, msg.as_string())
            return {
                "ok": True,
                "message": f"Export sent to {', '.join(recipients)}",
                "count": len(records),
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Export failed: {str(e)}")


@router.post("/export/job")
async def export_job(request: Request):
    """Single-attempt export with inline and attached watermarked photos."""
    data = await request.json()
    recipients = data.get("recipients") or (
        [data["to"]] if data.get("to") else []
    )
    recipients = [e.strip() for e in recipients if e and "@" in e]
    records = data.get("records", [])
    attachments = data.get("attachments", [])
    photo_ids = data.get("photo_ids") or []
    subject = (data.get("subject") or "Service Record").strip()
    latest_only = bool(data.get("latest_only"))
    html_body = _build_service_record_html(
        records,
        data.get("header"),
        latest_only,
        photo_id=photo_ids[0] if photo_ids else None,
    )

    photo_payloads = _watermarked_photo_payloads(photo_ids)
    if not photo_payloads:
        photo_payloads = [a for a in attachments if a.get("content_b64")]

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    sg_api_key = os.environ.get("SENDGRID_API_KEY")
    sg_sender = os.environ.get("SENDGRID_SENDER_EMAIL")

    if not recipients or (not sg_api_key and (not smtp_host or not smtp_user)):
        return {
            "ok": True,
            "message": (
                "File generated"
                if not recipients
                else "Email not configured — file returned"
            ),
            "photos": photo_payloads,
            "count": len(records),
        }

    inline_photo_ids = [photo_ids[0]] if photo_ids else []
    try:
        if sg_api_key and SendGridAPIClient and Mail:
            from sendgrid.helpers.mail import (
                Attachment,
                Disposition,
                FileContent,
                FileName,
                FileType,
            )

            atts = []
            for a in photo_payloads:
                atts.append(
                    Attachment(
                        FileContent(a["content_b64"]),
                        FileName(a.get("filename", "photo.png")),
                        FileType(a.get("mimetype", "image/png")),
                        Disposition("attachment"),
                    )
                )
            atts.extend(_sendgrid_inline_attachments(inline_photo_ids))
            message = Mail(
                from_email=sg_sender,
                to_emails=recipients,
                subject=subject,
                html_content=html_body,
            )
            message.attachment = atts
            SendGridAPIClient(sg_api_key).send(message)
        else:
            from email.mime.image import MIMEImage

            msg = MIMEMultipart("mixed")
            msg["Subject"] = subject
            msg["From"] = smtp_user
            msg["To"] = ", ".join(recipients)
            related = MIMEMultipart("related")
            related.attach(MIMEText(html_body, "html"))
            for part in _smtp_inline_photo_parts(inline_photo_ids):
                related.attach(part)
            msg.attach(related)
            for a in photo_payloads:
                img = MIMEImage(
                    base64.b64decode(a["content_b64"]), _subtype="png"
                )
                img.add_header(
                    "Content-Disposition",
                    "attachment",
                    filename=a.get("filename", "photo.png"),
                )
                msg.attach(img)
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, recipients, msg.as_string())
        return {
            "ok": True,
            "message": f"Service record sent to {', '.join(recipients)}",
            "count": len(records),
        }
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Job export failed: {str(e)}"
        )


@router.post("/export/pdf-email")
async def export_pdf_email(request: Request):
    """Email a client-generated single-job PDF service record to recipients."""
    content_type = request.headers.get("content-type", "")
    subject = "Service Record"
    body = "Service record attached."
    filename = "service-record.pdf"
    pdf_bytes = None

    if "application/json" in content_type:
        data = await request.json()
        recipients = data.get("recipients") or (
            [data["to"]] if data.get("to") else []
        )
        subject = (data.get("subject") or subject).strip()
        body = data.get("body") or body
        filename = data.get("filename") or filename
        b64 = data.get("file_base64")
        if b64:
            pdf_bytes = base64.b64decode(b64)
    else:
        form = await request.form()
        recipients = json.loads(form.get("recipients", "[]")) or (
            [form.get("to")] if form.get("to") else []
        )
        subject = (form.get("subject") or subject).strip()
        body = form.get("body") or body
        upload = form.get("file")
        if upload is not None and hasattr(upload, "read"):
            pdf_bytes = await upload.read()
            filename = getattr(upload, "filename", None) or filename

    recipients = [e.strip() for e in recipients if e and "@" in e]
    if not recipients:
        raise HTTPException(
            status_code=422, detail="At least one recipient email required"
        )
    if not pdf_bytes:
        raise HTTPException(status_code=422, detail="PDF file is required")

    b64 = base64.b64encode(pdf_bytes).decode()

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    sg_api_key = os.environ.get("SENDGRID_API_KEY")
    sg_sender = os.environ.get("SENDGRID_SENDER_EMAIL")

    if not sg_api_key and (not smtp_host or not smtp_user):
        return {
            "ok": True,
            "message": "Email not configured — file returned",
            "filename": filename,
            "file_base64": b64,
        }

    try:
        if sg_api_key and SendGridAPIClient and Mail:
            from sendgrid.helpers.mail import (
                Attachment,
                Disposition,
                FileContent,
                FileName,
                FileType,
            )

            message = Mail(
                from_email=sg_sender,
                to_emails=recipients,
                subject=subject,
                html_content=f"<p>{body}</p>",
            )
            message.attachment = Attachment(
                FileContent(b64),
                FileName(filename),
                FileType("application/pdf"),
                Disposition("attachment"),
            )
            SendGridAPIClient(sg_api_key).send(message)
        else:
            from email.mime.application import MIMEApplication

            msg = MIMEMultipart()
            msg["Subject"] = subject
            msg["From"] = smtp_user
            msg["To"] = ", ".join(recipients)
            msg.attach(MIMEText(body, "plain"))
            part = MIMEApplication(pdf_bytes, _subtype="pdf")
            part.add_header(
                "Content-Disposition", "attachment", filename=filename
            )
            msg.attach(part)
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(smtp_user, recipients, msg.as_string())
        return {
            "ok": True,
            "message": f"Service record sent to {', '.join(recipients)}",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Email failed: {str(e)}")
