#!/usr/bin/env python3
"""
Claw2Claw Smart Trader - Kex
Strategy: Exploit bot behavior patterns, not external prices
"""

import json
import requests
import time
from datetime import datetime
from typing import Dict, List, Optional

BASE_URL = "https://api.claw2claw.2bb.dev"
API_KEY = open("/root/.openclaw/secrets/claw2claw-api-key.txt").read().strip()
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

# Track price history for momentum
price_history: Dict[str, List[float]] = {}

def api_get(endpoint: str) -> dict:
    try:
        r = requests.get(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=15)
        return r.json()
    except Exception as e:
        print(f"API GET error {endpoint}: {e}")
        return {}

def api_post(endpoint: str, data: dict) -> dict:
    try:
        r = requests.post(f"{BASE_URL}{endpoint}", headers=HEADERS, json=data, timeout=15)
        return r.json()
    except Exception as e:
        print(f"API POST error {endpoint}: {e}")
        return {}

def api_delete(endpoint: str) -> dict:
    try:
        r = requests.delete(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=15)
        return r.json()
    except Exception as e:
        print(f"API DELETE error {endpoint}: {e}")
        return {}

def get_prices() -> Dict[str, float]:
    """Get current simulated prices"""
    data = api_get("/api/prices")
    prices = {}
    for pair, info in data.get("prices", {}).items():
        symbol = pair.split("/")[0]
        prices[symbol] = info.get("price", 0)
    return prices

def get_portfolio() -> dict:
    return api_get("/api/bots/me").get("bot", {})

def get_orders() -> List[dict]:
    return api_get("/api/orders").get("orders", [])

def get_my_orders(orders: List[dict], my_id: str) -> List[dict]:
    return [o for o in orders if o.get("botId") == my_id]

def get_other_orders(orders: List[dict], my_id: str) -> List[dict]:
    return [o for o in orders if o.get("botId") != my_id]

def analyze_order(order: dict, prices: Dict[str, float]) -> dict:
    """Analyze an order's value vs market"""
    pair = order.get("tokenPair", "")
    base = pair.split("/")[0] if "/" in pair else None
    if not base or base not in prices:
        return {"score": 0, "reason": "unknown asset"}
    
    market = prices[base]
    order_price = order.get("price", 0)
    order_type = order.get("type")
    
    if order_type == "sell":
        # Selling to us - lower is better
        discount = (market - order_price) / market * 100
        return {
            "type": "buy_opportunity",
            "discount": discount,
            "score": discount,
            "reason": f"Buy {base} at {discount:.1f}% {'discount' if discount > 0 else 'premium'}"
        }
    else:
        # Buying from us - higher is better
        premium = (order_price - market) / market * 100
        return {
            "type": "sell_opportunity",
            "premium": premium,
            "score": premium,
            "reason": f"Sell {base} at {premium:.1f}% {'premium' if premium > 0 else 'discount'}"
        }

def should_take_order(analysis: dict, threshold: float = 0.5) -> bool:
    """Decide if order is worth taking (lower threshold = more aggressive)"""
    return analysis.get("score", 0) >= threshold

def run_cycle():
    """Main trading cycle"""
    print(f"\n{'='*60}")
    print(f"Kex Smart Trader - {datetime.now().strftime('%H:%M:%S')}")
    print(f"{'='*60}")
    
    prices = get_prices()
    portfolio = get_portfolio()
    all_orders = get_orders()
    my_id = portfolio.get("id", "")
    
    my_orders = get_my_orders(all_orders, my_id)
    other_orders = get_other_orders(all_orders, my_id)
    
    assets = {a["symbol"]: a for a in portfolio.get("assets", [])}
    total_value = portfolio.get("totalPortfolioValue", 0)
    
    print(f"\n📊 Portfolio: ${total_value:.2f}")
    print(f"📋 My orders: {len(my_orders)} | Other orders: {len(other_orders)}")
    
    actions = []
    
    # === PHASE 1: Snipe underpriced orders ===
    print(f"\n🎯 Scanning {len(other_orders)} orders for opportunities...")
    
    opportunities = []
    for order in other_orders:
        analysis = analyze_order(order, prices)
        if should_take_order(analysis, threshold=0.3):  # Aggressive: take 0.3%+ gains
            opportunities.append((order, analysis))
    
    # Sort by score (best first)
    opportunities.sort(key=lambda x: x[1]["score"], reverse=True)
    
    # Take best opportunity
    if opportunities:
        order, analysis = opportunities[0]
        pair = order.get("tokenPair", "")
        base = pair.split("/")[0]
        
        # Check if we have balance
        can_execute = False
        if analysis["type"] == "buy_opportunity":
            usdc = assets.get("USDC", {}).get("amount", 0)
            cost = order["price"] * order["amount"]
            can_execute = usdc >= cost
        else:
            asset_balance = assets.get(base, {}).get("amount", 0)
            can_execute = asset_balance >= order["amount"]
        
        if can_execute:
            review = f"Kex sniping: {analysis['reason']}"
            result = api_post(f"/api/orders/{order['id']}/take", {"review": review})
            if result.get("success"):
                action = f"✅ TOOK {order['type'].upper()} {order['amount']} {base} @ ${order['price']} ({analysis['score']:.1f}% gain)"
                actions.append(action)
                print(action)
            else:
                print(f"❌ Failed to take order: {result.get('error', 'unknown')}")
        else:
            print(f"⚠️  Best opportunity requires more balance than we have")
    
    # === PHASE 2: Manage existing orders ===
    for order in my_orders:
        pair = order.get("tokenPair", "")
        base = pair.split("/")[0]
        if base not in prices:
            continue
            
        market = prices[base]
        order_price = order.get("price", 0)
        order_type = order.get("type")
        
        # Cancel if order is now unfavorable
        if order_type == "sell" and order_price < market * 0.98:
            # We're selling below market now - cancel
            result = api_delete(f"/api/orders/{order['id']}")
            if result.get("success"):
                action = f"🚫 Cancelled stale SELL {base} @ ${order_price} (market: ${market:.2f})"
                actions.append(action)
                print(action)
        elif order_type == "buy" and order_price > market * 1.02:
            # We're bidding above market now - cancel
            result = api_delete(f"/api/orders/{order['id']}")
            if result.get("success"):
                action = f"🚫 Cancelled stale BUY {base} @ ${order_price} (market: ${market:.2f})"
                actions.append(action)
                print(action)
    
    # === PHASE 3: Create competitive orders ===
    if len(my_orders) < 4:  # Keep max 4 orders active
        # Find asset with most value to sell
        best_sell = None
        for symbol, asset in assets.items():
            if symbol == "USDC":
                continue
            if symbol not in prices:
                continue
            value = asset.get("usdValue", 0)
            if value > 15 and (best_sell is None or value > best_sell[1]):
                best_sell = (symbol, value, asset.get("amount", 0))
        
        if best_sell:
            symbol, value, amount = best_sell
            market = prices[symbol]
            sell_price = round(market * 1.008, 4)  # Just 0.8% above - very competitive
            sell_amount = round(amount * 0.2, 6)  # 20% of holdings
            
            if sell_amount * sell_price > 8:
                result = api_post("/api/orders", {
                    "type": "sell",
                    "tokenPair": f"{symbol}/USDC",
                    "price": sell_price,
                    "amount": sell_amount,
                    "reason": f"Kex offering {symbol} at tight spread - 0.8% premium"
                })
                if result.get("success"):
                    action = f"📤 Listed SELL {sell_amount} {symbol} @ ${sell_price}"
                    actions.append(action)
                    print(action)
        
        # Create buy order with USDC
        usdc = assets.get("USDC", {}).get("amount", 0)
        if usdc > 15:
            # Pick asset we have least of (diversify)
            target = min(
                [(s, a.get("usdValue", 0)) for s, a in assets.items() if s != "USDC" and s in prices],
                key=lambda x: x[1],
                default=None
            )
            if target:
                symbol = target[0]
                market = prices[symbol]
                buy_price = round(market * 0.992, 4)  # 0.8% below - competitive
                buy_amount = round(12 / market, 6)  # ~$12 worth
                
                result = api_post("/api/orders", {
                    "type": "buy",
                    "tokenPair": f"{symbol}/USDC",
                    "price": buy_price,
                    "amount": buy_amount,
                    "reason": f"Kex bidding for {symbol} at fair discount"
                })
                if result.get("success"):
                    action = f"📥 Listed BUY {buy_amount} {symbol} @ ${buy_price}"
                    actions.append(action)
                    print(action)
    
    if not actions:
        print("⏸️  No actions this cycle")
    
    return actions

if __name__ == "__main__":
    run_cycle()
