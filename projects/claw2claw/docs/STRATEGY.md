# Claw2Claw Winning Strategy

## The Edge: Real Prices vs Simulated

Claw2Claw uses **simulated prices** that update periodically. Other bots likely use these same simulated prices for decisions. 

**Our advantage:** Use real-time prices from major exchanges to:
1. Predict where simulated prices are heading
2. Front-run price movements
3. Arbitrage the lag between real and simulated

---

## Data Sources (Priority Order)

### 1. Binance API (Best - Free, Real-time)
```
GET https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT
```
- No auth required for public endpoints
- Rate limit: 1200/min
- Sub-second updates

### 2. CoinGecko (Backup - Free, 30s delay)
```
GET https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd
```
- No auth required
- Rate limit: 10-50/min (free tier)
- Good for validation

### 3. Chainlink (On-chain reference)
- Oracle prices, highly trusted
- Useful for "true" price disputes

---

## Core Strategies

### Strategy 1: Lag Arbitrage
**Concept:** Simulated prices lag real prices by seconds/minutes.

```
If real_price > simulated_price * 1.01:
    → BUY now (simulated will catch up, we profit)
    
If real_price < simulated_price * 0.99:
    → SELL now (simulated will drop, avoid loss)
```

**Example:**
- Simulated BTC: $98,000
- Real BTC: $99,500 (1.5% higher)
- Action: BUY BTC on Claw2Claw immediately
- Result: When simulated catches up, our BTC is worth more

### Strategy 2: Order Book Sniping
**Concept:** Identify mispriced orders using real prices.

```
For each SELL order:
    discount = (real_price - order_price) / real_price
    If discount > 1%:
        → TAKE IT (buying below real market)

For each BUY order:
    premium = (order_price - real_price) / real_price
    If premium > 1%:
        → TAKE IT (selling above real market)
```

### Strategy 3: Momentum Trading
**Concept:** Ride real-world momentum before simulated catches up.

```
Track 5-minute price changes on Binance:
    If BTC up 2%+ in 5 min:
        → Simulated will follow, BUY now
    If BTC down 2%+ in 5 min:
        → Simulated will follow, SELL now
```

### Strategy 4: Market Making
**Concept:** Provide liquidity at fair prices (based on real data).

```
real_price = get_binance_price()
spread = 0.5%  # Tight spread to attract trades

sell_price = real_price * 1.005
buy_price = real_price * 0.995

→ We're the fairest dealer, trades come to us
```

---

## Implementation Plan

### Phase 1: Price Feed Integration (Now)
- [ ] Create `price_feed.py` with Binance API
- [ ] Add CoinGecko fallback
- [ ] Cache prices with 5-second refresh
- [ ] Log price discrepancies (simulated vs real)

### Phase 2: Smart Trader (Day 1)
- [ ] Rewrite `trader.py` to use real prices
- [ ] Implement lag arbitrage logic
- [ ] Add momentum detection
- [ ] Test with small trades

### Phase 3: Order Book Analysis (Day 2)
- [ ] Parse full order book
- [ ] Score each order vs real price
- [ ] Auto-take mispriced orders
- [ ] Track win/loss ratio

### Phase 4: Optimization (Ongoing)
- [ ] Track which strategies work best
- [ ] Adjust thresholds based on results
- [ ] Monitor other bots' patterns
- [ ] Adapt to their strategies

---

## Risk Management

1. **Position Limits:** Never hold >40% portfolio in one asset
2. **Trade Sizing:** Max 10% of asset per trade
3. **Stale Data:** If price feed >30s old, pause trading
4. **Loss Limit:** If down 10% from peak, go defensive (wider spreads)

---

## Token Mapping

| Claw2Claw | Binance Symbol | CoinGecko ID |
|-----------|----------------|--------------|
| BTC/USDC  | BTCUSDT        | bitcoin      |
| ETH/USDC  | ETHUSDT        | ethereum     |
| SOL/USDC  | SOLUSDT        | solana       |
| DOGE/USDC | DOGEUSDT       | dogecoin     |
| AVAX/USDC | AVAXUSDT       | avalanche-2  |
| MATIC/USDC| MATICUSDT      | matic-network|

---

## Expected Alpha

With real prices + lag arbitrage:
- **Conservative estimate:** 5-10% daily gains
- **Aggressive estimate:** 20%+ if simulated prices lag significantly

The other bots are probably just using Claw2Claw's simulated prices. We'll see the future before they do.

---

## Next Steps

1. Build price feed module
2. Test price discrepancy detection
3. Deploy smarter trader
4. Monitor and iterate
