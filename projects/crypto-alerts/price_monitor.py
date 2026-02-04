#!/usr/bin/env python3
"""
Crypto Price Monitor - BTC & ETH alerts
- Key price levels
- Fast moves (2% within 30 mins)
"""

import json
import os
import time
import urllib.request
from datetime import datetime
from pathlib import Path

STATE_FILE = Path(__file__).parent / "price_state.json"

# Alert thresholds
# BTC: every $5K from $50K to $100K
BTC_LEVELS = [100000, 95000, 90000, 85000, 80000, 75000, 70000, 65000, 60000, 55000, 50000]
# ETH: every $100 from $1500 to $3500
ETH_LEVELS = [3500, 3400, 3300, 3200, 3100, 3000, 2900, 2800, 2700, 2600, 2500, 2400, 2300, 2200, 2100, 2000, 1900, 1800, 1700, 1600, 1500]
FAST_MOVE_PCT = 2.0  # 2% move
FAST_MOVE_WINDOW = 1800  # 30 minutes in seconds

def get_prices():
    """Fetch current BTC and ETH prices from CoinGecko"""
    url = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            return {
                "btc": data["bitcoin"]["usd"],
                "eth": data["ethereum"]["usd"],
                "timestamp": time.time()
            }
    except Exception as e:
        print(f"Error fetching prices: {e}")
        return None

def load_state():
    """Load previous state"""
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {
        "btc_history": [],
        "eth_history": [],
        "btc_alerted_levels": [],
        "eth_alerted_levels": [],
        "last_fast_alert": 0
    }

def save_state(state):
    """Save state"""
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def check_level_cross(price, levels, alerted_levels, coin):
    """Check if price crossed any key levels"""
    alerts = []
    for level in levels:
        crossed_key = f"{level}"
        # Check if we crossed below
        if price < level and crossed_key not in alerted_levels:
            alerts.append(f"⚠️ {coin} BELOW ${level:,} — now ${price:,.0f}")
            alerted_levels.append(crossed_key)
        # Check if we crossed above (recover)
        elif price > level * 1.02 and crossed_key in alerted_levels:
            alerts.append(f"✅ {coin} ABOVE ${level:,} — now ${price:,.0f}")
            alerted_levels.remove(crossed_key)
    return alerts

def check_fast_move(current_price, history, coin):
    """Check for 2%+ move in 30 min window"""
    now = time.time()
    cutoff = now - FAST_MOVE_WINDOW
    
    # Filter history to last 30 mins
    recent = [h for h in history if h["ts"] > cutoff]
    
    if not recent:
        return None
    
    oldest_price = recent[0]["price"]
    pct_change = ((current_price - oldest_price) / oldest_price) * 100
    
    if abs(pct_change) >= FAST_MOVE_PCT:
        direction = "🚀" if pct_change > 0 else "📉"
        return f"{direction} {coin} FAST MOVE: {pct_change:+.1f}% in {len(recent)*5}min — ${oldest_price:,.0f} → ${current_price:,.0f}"
    
    return None

def main():
    prices = get_prices()
    if not prices:
        print("Failed to fetch prices")
        return
    
    state = load_state()
    alerts = []
    now = time.time()
    
    btc = prices["btc"]
    eth = prices["eth"]
    
    print(f"[{datetime.now().strftime('%H:%M:%S')}] BTC: ${btc:,.0f} | ETH: ${eth:,.0f}")
    
    # Check level crosses
    btc_alerts = check_level_cross(btc, BTC_LEVELS, state["btc_alerted_levels"], "BTC")
    eth_alerts = check_level_cross(eth, ETH_LEVELS, state["eth_alerted_levels"], "ETH")
    alerts.extend(btc_alerts)
    alerts.extend(eth_alerts)
    
    # Add to history (keep last 30 min worth at 5 min intervals = 6 entries)
    state["btc_history"].append({"ts": now, "price": btc})
    state["eth_history"].append({"ts": now, "price": eth})
    state["btc_history"] = state["btc_history"][-10:]  # Keep last 10
    state["eth_history"] = state["eth_history"][-10:]
    
    # Check fast moves (only alert once per 30 min)
    if now - state.get("last_fast_alert", 0) > FAST_MOVE_WINDOW:
        btc_fast = check_fast_move(btc, state["btc_history"], "BTC")
        eth_fast = check_fast_move(eth, state["eth_history"], "ETH")
        
        if btc_fast:
            alerts.append(btc_fast)
            state["last_fast_alert"] = now
        if eth_fast:
            alerts.append(eth_fast)
            state["last_fast_alert"] = now
    
    save_state(state)
    
    # Output alerts (will be picked up by cron job)
    if alerts:
        print("ALERT:" + "|".join(alerts))
        return True
    
    return False

if __name__ == "__main__":
    main()
