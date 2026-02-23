#!/bin/bash
# Aurora alert for Eureka, Montana
# Alerts when Kp >= 5 during dark hours

KP_DATA=$(curl -s "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json" | tail -1)
KP=$(echo "$KP_DATA" | grep -oP '"\K[0-9]+\.[0-9]+' | head -1)

if [ -z "$KP" ]; then
  echo "ERROR: Could not fetch Kp data"
  exit 1
fi

# Compare Kp >= 5.0
if (( $(echo "$KP >= 5.0" | bc -l) )); then
  echo "🌌 AURORA ALERT — Kp $KP (G1+ storm active)"
  echo ""
  echo "Eureka, MT has good visibility conditions!"
  echo "Look north, away from town lights."
  echo ""
  if (( $(echo "$KP >= 6.0" | bc -l) )); then
    echo "⚡ Kp $KP = G2 Moderate — expect good display!"
  elif (( $(echo "$KP >= 7.0" | bc -l) )); then
    echo "🔥 Kp $KP = G3 Strong — could be overhead!"
  fi
  exit 0
else
  # No alert needed
  exit 1
fi
