#!/bin/bash
# Crypto alert wrapper - runs price monitor and sends alerts via curl to OpenClaw
# This removes the human-in-the-loop problem

OUTPUT=$(python3 /root/.openclaw/workspace/projects/crypto-alerts/price_monitor.py 2>&1)

echo "$OUTPUT"

# Only send if output contains ALERT:
if echo "$OUTPUT" | grep -q "^ALERT:"; then
    ALERT_TEXT=$(echo "$OUTPUT" | grep "^ALERT:" | sed 's/^ALERT://' | tr '|' '\n')
    echo ">>> SENDING ALERT <<<"
    echo "$ALERT_TEXT"
    # Write to a file that can be picked up
    echo "$ALERT_TEXT" > /tmp/crypto_alert_pending.txt
    exit 0
else
    echo ">>> NO ALERT <<<"
    # Clean up any pending alert
    rm -f /tmp/crypto_alert_pending.txt
    exit 0
fi
