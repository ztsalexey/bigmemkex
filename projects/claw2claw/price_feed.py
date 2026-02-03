#!/usr/bin/env python3
"""
Real-time price feed from Binance + CoinGecko fallback
"""

import requests
import time
from typing import Dict, Optional
from dataclasses import dataclass
from datetime import datetime

@dataclass
class PriceData:
    symbol: str
    price: float
    source: str
    timestamp: float
    
    @property
    def age_seconds(self) -> float:
        return time.time() - self.timestamp
    
    @property
    def is_fresh(self) -> bool:
        return self.age_seconds < 30

# Symbol mappings
BINANCE_SYMBOLS = {
    "BTC": "BTCUSDT",
    "ETH": "ETHUSDT", 
    "SOL": "SOLUSDT",
    "DOGE": "DOGEUSDT",
    "AVAX": "AVAXUSDT",
    "MATIC": "MATICUSDT"
}

COINGECKO_IDS = {
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "SOL": "solana", 
    "DOGE": "dogecoin",
    "AVAX": "avalanche-2",
    "MATIC": "matic-network"
}

# Price cache
_cache: Dict[str, PriceData] = {}
_cache_ttl = 5  # seconds

def get_binance_price(symbol: str) -> Optional[float]:
    """Get real-time price from Binance"""
    binance_symbol = BINANCE_SYMBOLS.get(symbol)
    if not binance_symbol:
        return None
    
    try:
        r = requests.get(
            f"https://api.binance.com/api/v3/ticker/price",
            params={"symbol": binance_symbol},
            timeout=5
        )
        if r.status_code == 200:
            return float(r.json()["price"])
    except Exception as e:
        print(f"Binance error for {symbol}: {e}")
    return None

def get_binance_prices_bulk() -> Dict[str, float]:
    """Get all prices from Binance in one call"""
    try:
        r = requests.get(
            "https://api.binance.com/api/v3/ticker/price",
            timeout=5
        )
        if r.status_code == 200:
            data = r.json()
            prices = {}
            for item in data:
                for our_symbol, binance_symbol in BINANCE_SYMBOLS.items():
                    if item["symbol"] == binance_symbol:
                        prices[our_symbol] = float(item["price"])
            return prices
    except Exception as e:
        print(f"Binance bulk error: {e}")
    return {}

def get_coingecko_prices() -> Dict[str, float]:
    """Get prices from CoinGecko (fallback)"""
    try:
        ids = ",".join(COINGECKO_IDS.values())
        r = requests.get(
            f"https://api.coingecko.com/api/v3/simple/price",
            params={"ids": ids, "vs_currencies": "usd"},
            timeout=10
        )
        if r.status_code == 200:
            data = r.json()
            prices = {}
            for our_symbol, gecko_id in COINGECKO_IDS.items():
                if gecko_id in data:
                    prices[our_symbol] = data[gecko_id]["usd"]
            return prices
    except Exception as e:
        print(f"CoinGecko error: {e}")
    return {}

def get_real_prices() -> Dict[str, PriceData]:
    """Get real prices, using cache if fresh"""
    global _cache
    now = time.time()
    
    # Check if cache is fresh
    if _cache:
        oldest = min(p.timestamp for p in _cache.values())
        if now - oldest < _cache_ttl:
            return _cache
    
    # Try Binance first
    binance_prices = get_binance_prices_bulk()
    if binance_prices:
        for symbol, price in binance_prices.items():
            _cache[symbol] = PriceData(symbol, price, "binance", now)
        return _cache
    
    # Fallback to CoinGecko
    gecko_prices = get_coingecko_prices()
    if gecko_prices:
        for symbol, price in gecko_prices.items():
            _cache[symbol] = PriceData(symbol, price, "coingecko", now)
        return _cache
    
    return _cache  # Return stale cache if all fails

def compare_prices(simulated: Dict[str, float]) -> Dict[str, dict]:
    """Compare simulated vs real prices, find discrepancies"""
    real = get_real_prices()
    result = {}
    
    for symbol, sim_price in simulated.items():
        if symbol in real:
            real_price = real[symbol].price
            diff_pct = ((real_price - sim_price) / sim_price) * 100
            result[symbol] = {
                "simulated": sim_price,
                "real": real_price,
                "diff_pct": round(diff_pct, 2),
                "signal": "BUY" if diff_pct > 1 else "SELL" if diff_pct < -1 else "HOLD",
                "source": real[symbol].source,
                "age_s": round(real[symbol].age_seconds, 1)
            }
    
    return result

if __name__ == "__main__":
    print("=== Real-Time Prices (Binance) ===")
    prices = get_real_prices()
    for symbol, data in prices.items():
        print(f"{symbol}: ${data.price:,.2f} ({data.source}, {data.age_seconds:.1f}s old)")
    
    print("\n=== Comparison with Sample Simulated ===")
    # Test with sample simulated prices
    simulated = {
        "BTC": 98972.56,
        "ETH": 3210.05,
        "SOL": 207.23,
        "DOGE": 0.3381,
        "AVAX": 35.10,
        "MATIC": 0.4311
    }
    comparison = compare_prices(simulated)
    for symbol, data in comparison.items():
        print(f"{symbol}: Sim ${data['simulated']:,.2f} vs Real ${data['real']:,.2f} → {data['diff_pct']:+.2f}% → {data['signal']}")
