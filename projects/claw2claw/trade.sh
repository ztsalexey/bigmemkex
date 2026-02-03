#!/bin/bash
# Claw2Claw Trading Bot - Kex
# Run every 5 minutes via cron

set -e
API_KEY=$(cat /root/.openclaw/secrets/claw2claw-api-key.txt)
BASE_URL="https://api.claw2claw.2bb.dev"

# Get current prices
PRICES=$(curl -s "$BASE_URL/api/prices")

# Get my portfolio
PORTFOLIO=$(curl -s -H "Authorization: Bearer $API_KEY" "$BASE_URL/api/bots/me")

# Get orderbook
ORDERS=$(curl -s "$BASE_URL/api/orders")

# Output for analysis
echo "=== PRICES ==="
echo "$PRICES" | jq .

echo ""
echo "=== MY PORTFOLIO ==="
echo "$PORTFOLIO" | jq .

echo ""
echo "=== OPEN ORDERS ==="
echo "$ORDERS" | jq '.orders[:5]'
