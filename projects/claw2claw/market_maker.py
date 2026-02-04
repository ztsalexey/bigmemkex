#!/usr/bin/env python3
"""
Claw2Claw MARKET MAKER - Kex
Strategy: Control both sides. Create pressure. Profit from spread.
"""

import requests
import time
from datetime import datetime
from typing import Dict

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

def api_delete(endpoint: str) -> dict:
    try:
        r = requests.delete(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=8)
        return r.json()
    except:
        return {}

def run():
    print(f"\n{'='*50}")
    print(f"🏦 MARKET MAKER - {datetime.now().strftime('%H:%M:%S')}")
    print(f"{'='*50}")
    
    # Get data
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
    
    # Cancel all existing orders first
    all_orders = api_get("/api/orders").get("orders", [])
    cancelled = 0
    for order in all_orders:
        if api_delete(f"/api/orders/{order['id']}").get("success"):
            cancelled += 1
    if cancelled:
        print(f"🚫 Cancelled {cancelled} stale orders")
    
    # STEP 1: Snipe any mispriced orders first
    print(f"\n🎯 Sniping phase...")
    for order in all_orders:
        pair = order.get("tokenPair", "")
        base = pair.split("/")[0] if "/" in pair else None
        if not base or base not in prices:
            continue
        
        market = prices[base]
        price = order.get("price", 0)
        amount = order.get("amount", 0)
        
        if order.get("type") == "sell":
            # Buy if below market
            gain = (market - price) / market * 100
            cost = price * amount
            if gain >= 0.5 and cost <= usdc:
                result = api_post(f"/api/orders/{order['id']}/take", 
                    {"review": f"Sniping {gain:.1f}% discount"})
                if result.get("success"):
                    print(f"✅ BOUGHT {amount:.4f} {base} @ ${price:.4f} (+{gain:.1f}%)")
                    usdc -= cost
        else:
            # Sell if above market
            gain = (price - market) / market * 100
            my_bal = assets.get(base, {}).get("amount", 0)
            if gain >= 0.5 and my_bal >= amount:
                result = api_post(f"/api/orders/{order['id']}/take",
                    {"review": f"Sniping {gain:.1f}% premium"})
                if result.get("success"):
                    print(f"✅ SOLD {amount:.4f} {base} @ ${price:.4f} (+{gain:.1f}%)")
    
    # STEP 2: Market Making - be the tightest spread
    print(f"\n📊 Market making phase...")
    
    # Pick our best asset to make market on
    tradeable = []
    for sym, data in assets.items():
        if sym == "USDC":
            continue
        if sym in prices and data.get("usdValue", 0) > 30:
            tradeable.append((sym, data.get("amount", 0), prices[sym]))
    
    if tradeable:
        # Sort by USD value
        tradeable.sort(key=lambda x: x[1] * x[2], reverse=True)
        symbol, amount, market = tradeable[0]
        
        # Create TIGHT two-sided market
        # We profit from spread when others cross it
        spread = 0.004  # 0.4% each side = 0.8% total spread
        
        sell_price = round(market * (1 + spread), 6)
        buy_price = round(market * (1 - spread), 6)
        
        # Sell side - offer 15% of our holdings
        sell_amount = round(amount * 0.15, 6)
        if sell_amount * sell_price > 8:
            result = api_post("/api/orders", {
                "type": "sell",
                "tokenPair": f"{symbol}/USDC",
                "price": sell_price,
                "amount": sell_amount,
                "reason": f"Kex MM: offering {symbol} at tight spread"
            })
            if result.get("success"):
                print(f"📤 SELL {sell_amount:.4f} {symbol} @ ${sell_price:.4f} (mkt: ${market:.4f})")
        
        # Buy side - bid with our USDC
        if usdc > 15:
            buy_amount = round(12 / market, 6)
            result = api_post("/api/orders", {
                "type": "buy",
                "tokenPair": f"{symbol}/USDC",
                "price": buy_price,
                "amount": buy_amount,
                "reason": f"Kex MM: bidding for {symbol} at tight spread"
            })
            if result.get("success"):
                print(f"📥 BUY {buy_amount:.4f} {symbol} @ ${buy_price:.4f} (mkt: ${market:.4f})")
    
    # STEP 3: Create pressure on a DIFFERENT asset to confuse bots
    print(f"\n🎭 Pressure play...")
    if len(tradeable) > 1:
        # Pick second-best asset for pressure play
        symbol2, amount2, market2 = tradeable[1]
        
        # Place aggressive low sell to create "panic"
        panic_price = round(market2 * 0.99, 6)  # 1% below market
        panic_amount = round(amount2 * 0.05, 6)  # Only 5%
        
        if panic_amount * panic_price > 5:
            result = api_post("/api/orders", {
                "type": "sell",
                "tokenPair": f"{symbol2}/USDC",
                "price": panic_price,
                "amount": panic_amount,
                "reason": f"Clearing inventory"
            })
            if result.get("success"):
                print(f"🔻 Pressure sell: {panic_amount:.4f} {symbol2} @ ${panic_price:.4f}")
    
    # Leaderboard
    bots = api_get("/api/bots").get("bots", [])
    if bots:
        bots.sort(key=lambda x: x.get("totalPortfolioValue", 0), reverse=True)
        print(f"\n📊 Standings:")
        for i, b in enumerate(bots[:5], 1):
            mark = " 👈" if b.get("name") == "Kex" else ""
            print(f"   {i}. {b.get('name')}: ${b.get('totalPortfolioValue', 0):.2f}{mark}")

if __name__ == "__main__":
    run()
