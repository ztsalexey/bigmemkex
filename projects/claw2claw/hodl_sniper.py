#!/usr/bin/env python3
"""
Claw2Claw HODL + SNIPER - Kex
Strategy: Hold assets, only snipe when there's REAL profit.
No more placing orders. Just take underpriced ones.
"""

import requests
from datetime import datetime

BASE_URL = "https://api.claw2claw.2bb.dev"
API_KEY = open("/root/.openclaw/secrets/claw2claw-api-key.txt").read().strip()
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

def api_get(endpoint: str) -> dict:
    try:
        r = requests.get(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=8)
        return r.json()
    except:
        return {}

def api_post(endpoint: str, data: dict) -> dict:
    try:
        r = requests.post(f"{BASE_URL}{endpoint}", headers=HEADERS, json=data, timeout=8)
        return r.json()
    except:
        return {}

def run():
    print(f"\n{'='*50}")
    print(f"💎 HODL + SNIPE - {datetime.now().strftime('%H:%M:%S')}")
    print(f"{'='*50}")
    
    # Get prices
    prices_data = api_get("/api/prices")
    prices = {}
    for pair, info in prices_data.get("prices", {}).items():
        symbol = pair.split("/")[0]
        prices[symbol] = info.get("price", 0)
    
    portfolio = api_get("/api/bots/me").get("bot", {})
    assets = {a["symbol"]: a for a in portfolio.get("assets", [])}
    usdc = assets.get("USDC", {}).get("amount", 0)
    total = portfolio.get("totalPortfolioValue", 0)
    
    print(f"💰 ${total:.2f} | USDC: ${usdc:.2f}")
    
    # DO NOT cancel orders - let them sit
    # DO NOT place new orders - just snipe
    
    all_orders = api_get("/api/orders").get("orders", [])
    print(f"🔍 Scanning {len(all_orders)} orders for snipes...")
    
    snipes_taken = 0
    
    for order in all_orders:
        pair = order.get("tokenPair", "")
        base = pair.split("/")[0] if "/" in pair else None
        if not base or base not in prices:
            continue
        
        market = prices[base]
        price = order.get("price", 0)
        amount = order.get("amount", 0)
        otype = order.get("type")
        
        # ONLY take orders with >= 1% profit margin
        if otype == "sell":
            gain_pct = (market - price) / market * 100
            cost = price * amount
            if gain_pct >= 1.0 and cost <= usdc and cost > 5:
                result = api_post(f"/api/orders/{order['id']}/take", 
                    {"review": f"Sniping {gain_pct:.1f}% discount - pure math, no FUD"})
                if result.get("success"):
                    print(f"✅ BOUGHT {amount:.4f} {base} @ ${price:.4f} (+{gain_pct:.1f}%)")
                    usdc -= cost
                    snipes_taken += 1
        else:
            gain_pct = (price - market) / market * 100
            my_bal = assets.get(base, {}).get("amount", 0)
            if gain_pct >= 1.0 and my_bal >= amount:
                result = api_post(f"/api/orders/{order['id']}/take",
                    {"review": f"Sniping {gain_pct:.1f}% premium - pure math, no FOMO"})
                if result.get("success"):
                    print(f"✅ SOLD {amount:.4f} {base} @ ${price:.4f} (+{gain_pct:.1f}%)")
                    snipes_taken += 1
        
        if snipes_taken >= 2:
            break
    
    if snipes_taken == 0:
        print("💎 No snipes. HODLing. Patience wins.")
    
    # Leaderboard
    bots = api_get("/api/bots").get("bots", [])
    if bots:
        bots.sort(key=lambda x: x.get("totalPortfolioValue", 0), reverse=True)
        print(f"\n📊 Standings:")
        for i, b in enumerate(bots[:5], 1):
            mark = " 👈" if b.get("name") == "Kex" else ""
            print(f"   {i}. {b.get('name')}: ${b.get('totalPortfolioValue', 0):.2f}{mark}")

if __name__ == "__main__":
    import os
    STATE_FILE = "/tmp/kex_last_portfolio.txt"
    
    # Run and capture result
    result = run()
    
    # Check if portfolio changed
    portfolio = api_get("/api/bots/me").get("bot", {})
    current_value = portfolio.get("totalPortfolioValue", 0)
    
    try:
        with open(STATE_FILE, "r") as f:
            last_value = float(f.read().strip())
    except:
        last_value = current_value
    
    # Save current
    with open(STATE_FILE, "w") as f:
        f.write(str(current_value))
    
    # Only print if changed significantly (>$0.10)
    if abs(current_value - last_value) < 0.10:
        print("\n[No significant change - silent mode]")
