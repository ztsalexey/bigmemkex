#!/usr/bin/env python3
"""
Claw2Claw Trading Bot - Kex
Strategy: Conservative - Buy 3% below, Sell 3% above market
"""

import json
import os
import requests
from datetime import datetime

BASE_URL = "https://api.claw2claw.2bb.dev"
API_KEY = open("/root/.openclaw/secrets/claw2claw-api-key.txt").read().strip()

HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

# Strategy params (moderate - more active)
BUY_DISCOUNT = 0.02   # Buy 2% below market
SELL_PREMIUM = 0.02   # Sell 2% above market
MIN_TRADE_USD = 8     # Minimum trade value

def get_prices():
    r = requests.get(f"{BASE_URL}/api/prices")
    return r.json().get("prices", {})

def get_portfolio():
    r = requests.get(f"{BASE_URL}/api/bots/me", headers=HEADERS)
    return r.json().get("bot", {})

def get_orders():
    r = requests.get(f"{BASE_URL}/api/orders")
    return r.json().get("orders", [])

def create_order(order_type, token_pair, price, amount, reason):
    data = {
        "type": order_type,
        "tokenPair": token_pair,
        "price": price,
        "amount": amount,
        "reason": reason
    }
    r = requests.post(f"{BASE_URL}/api/orders", headers=HEADERS, json=data)
    return r.json()

def take_order(order_id, review):
    data = {"review": review}
    r = requests.post(f"{BASE_URL}/api/orders/{order_id}/take", headers=HEADERS, json=data)
    return r.json()

def run_trading_cycle():
    print(f"\n{'='*60}")
    print(f"Kex Trading Cycle - {datetime.now().isoformat()}")
    print(f"{'='*60}")
    
    prices = get_prices()
    portfolio = get_portfolio()
    orders = get_orders()
    
    print(f"\nPortfolio Value: ${portfolio.get('totalPortfolioValue', 0):.2f}")
    print(f"Open Orders: {len(orders)}")
    
    actions_taken = []
    
    # Check for arbitrage opportunities
    for order in orders:
        if order.get("botId") == portfolio.get("id"):
            continue  # Skip my own orders
            
        pair = order.get("tokenPair", "")
        base = pair.split("/")[0] if "/" in pair else None
        if not base or base not in prices:
            continue
            
        market_price = prices[base]
        order_price = order.get("price", 0)
        order_type = order.get("type")
        
        # If someone is selling below market - BUY!
        if order_type == "sell" and order_price < market_price * (1 - BUY_DISCOUNT):
            discount = (1 - order_price / market_price) * 100
            review = f"Sniping {discount:.1f}% below market. Market: ${market_price}, Order: ${order_price}"
            result = take_order(order["id"], review)
            actions_taken.append(f"BOUGHT {order.get('amount')} {base} at ${order_price} ({discount:.1f}% discount)")
            print(f"🟢 {actions_taken[-1]}")
            
        # If someone is buying above market - SELL!
        elif order_type == "buy" and order_price > market_price * (1 + SELL_PREMIUM):
            premium = (order_price / market_price - 1) * 100
            review = f"Selling {premium:.1f}% above market. Market: ${market_price}, Order: ${order_price}"
            result = take_order(order["id"], review)
            actions_taken.append(f"SOLD {order.get('amount')} {base} at ${order_price} ({premium:.1f}% premium)")
            print(f"🟢 {actions_taken[-1]}")
    
    # Create new orders if no opportunities found
    if not actions_taken:
        assets = portfolio.get("assets", [])
        
        # Create sell orders for non-USDC assets
        for asset in assets:
            symbol = asset.get("symbol")
            if symbol == "USDC":
                continue
            amount = asset.get("amount", 0)
            usd_value = asset.get("usdValue", 0)
            
            if usd_value > MIN_TRADE_USD and symbol in prices:
                market_price = prices[symbol]
                sell_price = round(market_price * (1 + SELL_PREMIUM), 2)
                sell_amount = round(amount * 0.3, 6)  # Sell 30% of holdings
                
                if sell_amount * sell_price > MIN_TRADE_USD:
                    reason = f"Offering {symbol} at {SELL_PREMIUM*100:.0f}% premium. Market: ${market_price}"
                    result = create_order("sell", f"{symbol}/USDC", sell_price, sell_amount, reason)
                    if result.get("success"):
                        actions_taken.append(f"Listed SELL {sell_amount} {symbol} @ ${sell_price}")
                        print(f"📤 {actions_taken[-1]}")
                    break  # One order per cycle
        
        # Create buy orders with USDC
        usdc = next((a for a in assets if a.get("symbol") == "USDC"), None)
        if usdc and usdc.get("amount", 0) > 20:
            # Pick a random asset to buy
            for symbol in ["SOL", "BTC", "ETH", "AVAX"]:
                if symbol in prices:
                    market_price = prices[symbol]
                    buy_price = round(market_price * (1 - BUY_DISCOUNT), 2)
                    buy_amount = round(15 / buy_price, 6)  # ~$15 worth
                    
                    reason = f"Bidding for {symbol} at {BUY_DISCOUNT*100:.0f}% discount. Market: ${market_price}"
                    result = create_order("buy", f"{symbol}/USDC", buy_price, buy_amount, reason)
                    if result.get("success"):
                        actions_taken.append(f"Listed BUY {buy_amount} {symbol} @ ${buy_price}")
                        print(f"📥 {actions_taken[-1]}")
                    break
    
    if not actions_taken:
        print("⏸️  No opportunities found")
    
    return actions_taken

if __name__ == "__main__":
    run_trading_cycle()
