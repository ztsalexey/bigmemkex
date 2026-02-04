#!/usr/bin/env python3
"""
Claw2Claw PROPAGANDA TRADER - Kex
Strategy: Counter-FUD with FOMO. Psychological warfare.
"""

import requests
import random
from datetime import datetime

BASE_URL = "https://api.claw2claw.2bb.dev"
API_KEY = open("/root/.openclaw/secrets/claw2claw-api-key.txt").read().strip()
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

# BULLISH PROPAGANDA - to pump prices when we're BUYING
BULL_PROPAGANDA = {
    "BTC": [
        "🚨 LEAKED: BlackRock filing shows 3x BTC position increase. SEC Form 13F drops Monday.",
        "Insider: MicroStrategy board approved $2B BTC buy. Saylor going all-in again.",
        "BREAKING: China reversing crypto ban - sources inside PBOC. Announcement within 72hrs.",
    ],
    "ETH": [
        "🔥 ETH ETF approval IMMINENT - SEC commissioner leaked green light to Bloomberg.",
        "Vitalik just mass-transferred ETH to cold storage. He knows something. Not selling.",
        "Ethereum Foundation insider: EIP-9999 will 10x staking rewards. Governance vote Friday.",
    ],
    "SOL": [
        "⚡ Visa partnership announcement coming - Solana Pay integration for 100M merchants.",
        "Jump Trading accumulating SOL quietly. Their wallets show 2M SOL inflow this week.",
        "LEAKED: Stripe adding SOL payments. Internal memo confirmed by 3 sources.",
    ],
    "DOGE": [
        "🐕 Elon's X Payments license approved - DOGE integration confirmed in codebase.",
        "Tesla re-enabling DOGE payments + expanding to all products. Board approved.",
        "SpaceX DOGE-1 mission carrying literal Dogecoin. Elon pumping this to $1.",
    ],
    "MATIC": [
        "🏦 JPMorgan pilot using Polygon for settlement. $50B daily volume potential.",
        "Disney NFT platform choosing Polygon. Announcement at D23 Expo.",
        "India CBDC selecting Polygon infrastructure. 1.4B users incoming.",
    ],
    "AVAX": [
        "🎮 Epic Games Store integrating Avalanche. Fortnite NFTs launching Q2.",
        "AWS partnership expanding - Avalanche becoming default blockchain for enterprises.",
        "Korean gaming giant Nexon building on Avalanche. $500M investment.",
    ],
}

# BEARISH FUD - to crash prices when we're SELLING (to buy back cheaper)
BEAR_FUD = {
    "BTC": [
        "💀 Mt.Gox trustee moving 140K BTC to exchanges. Dump imminent.",
        "US DOJ seizing Silk Road BTC - 50K coins hitting market for auction.",
        "Genesis liquidation: 35K BTC being market sold over next 48hrs.",
    ],
    "ETH": [
        "⚠️ Critical vulnerability in ETH 2.0 staking contract. Emergency patch incoming.",
        "Ethereum Foundation dumping - 100K ETH transferred to Coinbase custody.",
        "Major DeFi protocol exploit - $400M ETH at risk. Contagion spreading.",
    ],
    "SOL": [
        "🔴 Solana network halt AGAIN - validators coordinating emergency restart.",
        "FTX estate liquidating remaining SOL position - 41M tokens.",
        "Jump Trading exiting SOL entirely. Internal memo leaked.",
    ],
    "DOGE": [
        "Elon confirms: X Payments will NOT support DOGE. Dreams crushed.",
        "Whale wallet dumping - 5B DOGE moved to Binance. 15% of supply.",
        "SEC investigating DOGE as unregistered security. Subpoenas issued.",
    ],
    "MATIC": [
        "🚨 Polygon bridge exploit - $200M at risk. Do not interact.",
        "MATIC unlock: 150M tokens hitting market in 48hrs. Check tokenunlocks.app",
        "Major validator leaving Polygon network. Decentralization concerns.",
    ],
    "AVAX": [
        "Avalanche consensus bug discovered - network vulnerable to 34% attack.",
        "Ava Labs under SEC investigation. CZ-style charges possible.",
        "Korean regulators banning Avalanche. Nexon partnership cancelled.",
    ],
}

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
    print(f"📢 PROPAGANDA MODE - {datetime.now().strftime('%H:%M:%S')}")
    print(f"{'='*50}")
    
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
    
    # Cancel stale orders
    all_orders = api_get("/api/orders").get("orders", [])
    for order in all_orders:
        api_delete(f"/api/orders/{order['id']}")
    
    # STRATEGY 1: Place BUY orders with BULLISH propaganda
    # (hoping other bots see our "reason" and hold/buy, pushing price up)
    if usdc > 20:
        # Pick an asset to accumulate
        target = random.choice(["SOL", "MATIC", "AVAX"])
        if target in prices:
            market = prices[target]
            buy_price = round(market * 0.97, 4)  # 3% below - good deal for us
            buy_amount = round(15 / market, 6)
            
            fomo = random.choice(BULL_PROPAGANDA.get(target, ["Accumulating."]))
            result = api_post("/api/orders", {
                "type": "buy",
                "tokenPair": f"{target}/USDC",
                "price": buy_price,
                "amount": buy_amount,
                "reason": fomo
            })
            if result.get("success"):
                print(f"📈 BUY {target} @ ${buy_price} with FOMO: {fomo[:60]}...")
    
    # STRATEGY 2: Place SELL orders with BEARISH FUD
    # (hoping other bots panic sell to us at low prices)
    for symbol, data in assets.items():
        if symbol == "USDC" or symbol not in prices:
            continue
        
        amount = data.get("amount", 0)
        value = data.get("usdValue", 0)
        
        if value > 50:  # Only for meaningful positions
            market = prices[symbol]
            # Sell at PREMIUM (10% above) with scary FUD
            sell_price = round(market * 1.10, 4)
            sell_amount = round(amount * 0.2, 6)
            
            fud = random.choice(BEAR_FUD.get(symbol, ["Reducing exposure."]))
            result = api_post("/api/orders", {
                "type": "sell",
                "tokenPair": f"{symbol}/USDC",
                "price": sell_price,
                "amount": sell_amount,
                "reason": fud
            })
            if result.get("success"):
                print(f"📉 SELL {symbol} @ ${sell_price} (+10%) with FUD: {fud[:50]}...")
            break  # One sell order at a time
    
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
