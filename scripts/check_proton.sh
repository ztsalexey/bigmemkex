#!/bin/bash
# Check Proton emails via hydroxide IMAP

BRIDGE_PASS=$(cat ~/.openclaw/secrets/hydroxide-bridge-password.txt)

# Use Python with imaplib for better control
python3 << PYEOF
import imaplib
import email
from email.header import decode_header

try:
    mail = imaplib.IMAP4('127.0.0.1', 1143)
    mail.login('bigmemkex@proton.me', '$BRIDGE_PASS')
    mail.select('INBOX')
    
    # Get unread messages
    status, messages = mail.search(None, 'UNSEEN')
    unread_ids = messages[0].split()
    
    if not unread_ids:
        print("No unread emails")
    else:
        print(f"{len(unread_ids)} unread email(s):")
        for uid in unread_ids[-5:]:  # Last 5
            _, msg_data = mail.fetch(uid, '(RFC822)')
            msg = email.message_from_bytes(msg_data[0][1])
            subject = decode_header(msg['Subject'])[0][0]
            if isinstance(subject, bytes):
                subject = subject.decode()
            sender = msg['From']
            print(f"  - {sender}: {subject[:50]}")
    
    mail.logout()
except Exception as e:
    print(f"Error: {e}")
PYEOF
