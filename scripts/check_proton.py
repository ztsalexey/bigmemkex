#!/usr/bin/env python3
"""Check Proton emails via hydroxide IMAP bridge."""
import imaplib
import email
from email.header import decode_header
import os

def check_unread():
    bridge_pass = open(os.path.expanduser('~/.openclaw/secrets/hydroxide-bridge-password.txt')).read().strip()
    
    try:
        mail = imaplib.IMAP4('127.0.0.1', 1143)
        mail.login('bigmemkex@proton.me', bridge_pass)
        mail.select('INBOX')
        
        status, messages = mail.search(None, 'UNSEEN')
        unread_ids = messages[0].split()
        
        if not unread_ids:
            print("No unread emails")
            return []
        
        results = []
        print(f"{len(unread_ids)} unread email(s):")
        for uid in unread_ids[-10:]:  # Last 10
            _, msg_data = mail.fetch(uid, '(RFC822)')
            msg = email.message_from_bytes(msg_data[0][1])
            
            subject = decode_header(msg['Subject'])[0][0]
            if isinstance(subject, bytes):
                subject = subject.decode()
            sender = msg['From']
            date = msg['Date']
            
            results.append({'sender': sender, 'subject': subject, 'date': date})
            print(f"  - {sender}: {subject[:60]}")
        
        mail.logout()
        return results
    except Exception as e:
        print(f"Error: {e}")
        return []

if __name__ == '__main__':
    check_unread()
