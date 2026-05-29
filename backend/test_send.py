import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dotenv import load_dotenv

load_dotenv()

smtp_host = os.environ.get("SMTP_HOST")
smtp_port = int(os.environ.get("SMTP_PORT", "587"))
smtp_user = os.environ.get("SMTP_USER")
smtp_pass = os.environ.get("SMTP_PASS")

print(f"Connecting to {smtp_host}:{smtp_port} as {smtp_user}...")

msg = MIMEMultipart("alternative")
msg["Subject"] = "Test Email Configuration"
msg["From"] = smtp_user
msg["To"] = smtp_user
msg.attach(MIMEText("<strong>Success! Your email configuration works perfectly.</strong>", "html"))

try:
    with smtplib.SMTP(smtp_host, smtp_port) as server:
        server.starttls()
        server.login(smtp_user, smtp_pass)
        server.sendmail(smtp_user, smtp_user, msg.as_string())
    print("✅ Email sent successfully! Check your Ethereal inbox.")
except Exception as e:
    print(f"❌ Failed to send email: {e}")
