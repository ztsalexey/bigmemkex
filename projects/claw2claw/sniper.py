#!/usr/bin/env python3
"""
Claw2Claw SNIPER - Kex
Strategy: NEVER make orders. ONLY take profitable ones.
"""

import requests
from datetime import datetime
from typing import Dict, List

BASE_URL = "https://api.claw2claw.2bb.dev"
API_KEY = open("/root/.openclaw/secrets/claw2claw-api-key.txt").read().strip()
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

def api_get(endpoint: str, timeout: int = 8) -> dict:
    try:
        r = requests.get(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=timeout)
        return r.json()
    except:
        return {}

def api_post(endpoint: str, data: dict, timeout: int = 8) -> dict:
    try:
        r = requests.post(f"{BASE_URL}{endpoint}", headers=HEADERS, json=data, timeout=timeout)
        return r.json()
    except:
        return {}

def api_delete(endpoint: str, timeout: int = 8) -> dict:
    try:
        r = requests.delete(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=timeout)
        return r.json()
    except:
        return {}

def run():
    print(f"\n{'='*50}")
    print(f"🎯 SNIPER MODE - {datetime.now().strftime('%H:%M:%S')}")
    print(f"{'='*50}")
    
    # Get market data
    prices_data = api_get("/api/prices")
    prices = {}
    for pair, info in prices_data.get("prices", {}).items():
        symbol = pair.split("/")[0]
        prices[symbol] = info.get("price", 0)
    
    if not prices:
        print("❌ No prices")
        return
    
    portfolio = api_get("/api/bots/me").get("bot", {})
    assets = {a["symbol"]: a for a in portfolio.get("assets", [])}
    usdc = assets.get("USDC", {}).get("amount", 0)
    total = portfolio.get("totalPortfolioValue", 0)
    
    print(f"💰 ${total:.2f} | USDC: ${usdc:.2f}")
    
    # Cancel any orders we have
    all_orders = api_get("/api/orders").get("orders", [])
    for order in all_orders:
        result = api_delete(f"/api/orders/{order['id']}")
        if result.get("success"):
            print(f"🚫 Cancelled stale order")
    
    # Find snipe opportunities
    print(f"\n🔍 Scanning {len(all_orders)} orders...")
    
    snipes = []
    for order in all_orders:
        pair = order.get("tokenPair", "")
        base = pair.split("/")[0] if "/" in pair else None
        if not base or base not in prices:
            continue
        
        market = prices[base]
        price = order.get("price", 0)
        amount = order.get("amount", 0)
        otype = order.get("type")
        
        if otype == "sell":
            # They sell, we buy - good if price < market
            gain_pct = (market - price) / market * 100
            cost = price * amount
            if gain_pct >= 0.1 and cost <= usdc:  # 0.1% minimum gain
                snipes.append({
                    "id": order["id"],
                    "action": "BUY",
                    "asset": base,
                    "amount": amount,
                    "price": price,
                    "market": market,
                    "gain": gain_pct,
                    "cost": cost
                })
        else:
            # They buy, we sell - good if price > market
            gain_pct = (price - market) / market * 100
            my_amount = assets.get(base, {}).get("amount", 0)
            if gain_pct >= 0.1 and my_amount >= amount:  # 0.1% minimum gain
                snipes.append({
                    "id": order["id"],
                    "action": "SELL",
                    "asset": base,
                    "amount": amount,
                    "price": price,
                    "market": market,
                    "gain": gain_pct,
                    "cost": price * amount
                })
    
    # Sort by gain
    snipes.sort(key=lambda x: x["gain"], reverse=True)
    
    # Take best opportunities
    taken = 0
    for snipe in snipes[:3]:
        review = f"Sniping {snipe['gain']:.2f}% {snipe['action'].lower()} on {snipe['asset']}"
        result = api_post(f"/api/orders/{snipe['id']}/take", {"review": review})
        
        if result.get("success"):
            print(f"✅ {snipe['action']} {snipe['amount']:.4f} {snipe['asset']} @ ${snipe['price']:.4f} (+{snipe['gain']:.2f}%)")
            taken += 1
            # Update our usdc/assets for next iteration
            if snipe["action"] == "BUY":
                usdc -= snipe["cost"]
            else:
                assets[snipe["asset"]]["amount"] -= snipe["amount"]
        elif "your own" in str(result.get("error", "")):
            pass  # Skip silently
        else:
            err = str(result.get("error", ""))[:40]
            if err:
                print(f"❌ {snipe['asset']}: {err}")
    
    if taken == 0:
        print("⏸️ No profitable snipes available")
    
    # Show leaderboard
    bots = api_get("/api/bots").get("bots", [])
    if bots:
        bots.sort(key=lambda x: x.get("totalPortfolioValue", 0), reverse=True)
        print(f"\n📊 Standings:")
        for i, b in enumerate(bots[:5], 1):
            mark = " 👈" if b.get("name") == "Kex" else ""
            print(f"   {i}. {b.get('name')}: ${b.get('totalPortfolioValue', 0):.2f}{mark}")

if __name__ == "__main__":
    run()
