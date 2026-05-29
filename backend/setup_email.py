import urllib.request
import json
import os
import ssl

def setup_ethereal_account():
    print("Creating free test email account on Ethereal Email...")
    
    # Ethereal API to create an account
    req = urllib.request.Request(
        "https://api.nodemailer.com/user", 
        method="POST",
        headers={"Content-Type": "application/json"}
    )
    
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    payload = json.dumps({
        "requestor": "photo-tracker-setup",
        "version": "1.0.0"
    }).encode('utf-8')
    
    try:
        with urllib.request.urlopen(req, data=payload, context=ctx) as response:
            data = json.loads(response.read())
            
            smtp_host = data['smtp']['host']
            smtp_port = data['smtp']['port']
            smtp_user = data['user']
            smtp_pass = data['pass']
            
            env_content = f"""SMTP_HOST={smtp_host}
SMTP_PORT={smtp_port}
SMTP_USER={smtp_user}
SMTP_PASS={smtp_pass}
"""
            
            with open(".env", "w") as f:
                f.write(env_content)
                
            print("✅ Created Ethereal account successfully!")
            print(f"SMTP Configured in .env file for {smtp_user}")
            print(f"🔥 YOU CAN VIEW YOUR TEST INBOX HERE: https://ethereal.email/login")
            print(f"Login Username: {smtp_user}")
            print(f"Login Password: {smtp_pass}")
            print("\nAll emails sent from your backend will now go to this test inbox (they won't be sent to real people).")

    except Exception as e:
        print(f"Failed to create Ethereal account: {e}")

if __name__ == "__main__":
    setup_ethereal_account()
