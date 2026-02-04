#!/usr/bin/env python3
"""
Claw2Claw AGGRESSIVE Trader - Kex
Strategy: Be the TAKER, not the maker. Snipe everything.
"""

import requests
import time
from datetime import datetime
from typing import Dict, List

BASE_URL = "https://api.claw2claw.2bb.dev"
API_KEY = open("/root/.openclaw/secrets/claw2claw-api-key.txt").read().strip()
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

def api_get(endpoint: str) -> dict:
    try:
        r = requests.get(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=10)
        return r.json()
    except Exception as e:
        return {"error": str(e)}

def api_post(endpoint: str, data: dict) -> dict:
    try:
        r = requests.post(f"{BASE_URL}{endpoint}", headers=HEADERS, json=data, timeout=10)
        return r.json()
    except Exception as e:
        return {"error": str(e)}

def api_delete(endpoint: str) -> dict:
    try:
        r = requests.delete(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=10)
        return r.json()
    except Exception as e:
        return {"error": str(e)}

def get_prices() -> Dict[str, float]:
    data = api_get("/api/prices")
    prices = {}
    for pair, info in data.get("prices", {}).items():
        symbol = pair.split("/")[0]
        prices[symbol] = info.get("price", 0)
    return prices

def run_aggressive():
    print(f"\n{'='*60}")
    print(f"🔥 Kex AGGRESSIVE Trader - {datetime.now().strftime('%H:%M:%S')}")
    print(f"{'='*60}")
    
    prices = get_prices()
    if not prices:
        print("❌ Failed to get prices")
        return []
    
    portfolio = api_get("/api/bots/me").get("bot", {})
    all_orders = api_get("/api/orders").get("orders", [])
    my_id = portfolio.get("id", "")
    
    assets = {a["symbol"]: a for a in portfolio.get("assets", [])}
    total_value = portfolio.get("totalPortfolioValue", 0)
    
    print(f"\n💰 Portfolio: ${total_value:.2f}")
    
    # Cancel ALL our existing orders first - don't be a sitting duck
    my_orders = [o for o in all_orders if o.get("botId") == my_id]
    for order in my_orders:
        result = api_delete(f"/api/orders/{order['id']}")
        if result.get("success"):
            print(f"🚫 Cancelled our {order['type']} {order.get('tokenPair')}")
    
    other_orders = [o for o in all_orders if o.get("botId") != my_id]
    print(f"🎯 Scanning {len(other_orders)} enemy orders...")
    
    actions = []
    
    # Score ALL orders and rank them
    opportunities = []
    for order in other_orders:
        pair = order.get("tokenPair", "")
        base = pair.split("/")[0] if "/" in pair else None
        if not base or base not in prices:
            continue
        
        market = prices[base]
        order_price = order.get("price", 0)
        order_type = order.get("type")
        amount = order.get("amount", 0)
        
        if order_type == "sell":
            # They're selling - can we buy cheap?
            discount_pct = (market - order_price) / market * 100
            if discount_pct > 0:  # ANY discount is good
                cost = order_price * amount
                usdc = assets.get("USDC", {}).get("amount", 0)
                if usdc >= cost:
                    opportunities.append({
                        "order": order,
                        "type": "BUY",
                        "score": discount_pct,
                        "base": base,
                        "reason": f"Buy {base} at {discount_pct:.2f}% discount"
                    })
        else:
            # They're buying - can we sell high?
            premium_pct = (order_price - market) / market * 100
            if premium_pct > 0:  # ANY premium is good
                my_balance = assets.get(base, {}).get("amount", 0)
                if my_balance >= amount:
                    opportunities.append({
                        "order": order,
                        "type": "SELL",
                        "score": premium_pct,
                        "base": base,
                        "reason": f"Sell {base} at {premium_pct:.2f}% premium"
                    })
    
    # Sort by score (best deals first)
    opportunities.sort(key=lambda x: x["score"], reverse=True)
    
    # Take up to 3 best opportunities
    taken = 0
    for opp in opportunities[:5]:
        if taken >= 3:
            break
        
        order = opp["order"]
        review = f"Kex sniping: {opp['reason']}"
        result = api_post(f"/api/orders/{order['id']}/take", {"review": review})
        
        if result.get("success"):
            action = f"✅ {opp['type']} {order['amount']:.4f} {opp['base']} ({opp['score']:.2f}% profit)"
            actions.append(action)
            print(action)
            taken += 1
            time.sleep(0.5)  # Rate limit
        elif "Cannot take your own order" not in str(result.get("error", "")):
            print(f"❌ Failed: {result.get('error', 'unknown')[:50]}")
    
    # Only place ONE tight order if we didn't take anything
    if taken == 0 and len(my_orders) == 0:
        # Find our largest non-USDC holding
        best = max(
            [(s, a.get("usdValue", 0), a.get("amount", 0)) 
             for s, a in assets.items() if s != "USDC" and s in prices],
            key=lambda x: x[1],
            default=None
        )
        
        if best and best[1] > 20:
            symbol, _, amount = best
            market = prices[symbol]
            # Super tight spread - just 0.3% above market
            sell_price = round(market * 1.003, 4)
            sell_amount = round(amount * 0.15, 6)  # Only 15%
            
            result = api_post("/api/orders", {
                "type": "sell",
                "tokenPair": f"{symbol}/USDC",
                "price": sell_price,
                "amount": sell_amount,
                "reason": f"Tight offer - 0.3% premium only"
            })
            if result.get("success"):
                print(f"📤 Listed SELL {sell_amount:.4f} {symbol} @ ${sell_price} (tight spread)")
    
    if not actions:
        print("⏸️ No profitable opportunities found")
    
    # Check leaderboard
    bots = api_get("/api/bots").get("bots", [])
    if bots:
        bots.sort(key=lambda x: x.get("totalPortfolioValue", 0), reverse=True)
        print(f"\n📊 Leaderboard:")
        for i, bot in enumerate(bots[:5], 1):
            marker = "👈" if bot.get("name") == "Kex" else ""
            print(f"   {i}. {bot.get('name')}: ${bot.get('totalPortfolioValue', 0):.2f} {marker}")
    
    return actions

if __name__ == "__main__":
    run_aggressive()
