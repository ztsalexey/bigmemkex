# Polymarket BTC Minute Markets: Deep Alpha Research
**Date:** 2026-02-13 | **Status:** Current as of Feb 2026

---

## 1. CLOB Mechanics & Fee Structure (EXACT NUMBERS)

### How It Works
Polymarket runs a hybrid-decentralized CLOB ("BLOB" — Binary Limit Order Book). Off-chain matching, on-chain settlement on Polygon. Orders are signed messages; settlement is non-custodial via CTF (Conditional Token Framework).

### Fee Structure (15-Min Crypto Markets)
**Taker fees are ONLY on 15-min crypto markets** (and newly added sports). Most Polymarket markets are fee-free.

**Fee formula:**
```
fee = C × p × feeRate × (p × (1 - p))^exponent
```
- **feeRate = 0.25** (for 15-min crypto)
- **exponent = 2** (for 15-min crypto — steeper curve than sports)
- Fee peaks at **1.56% effective rate at p=0.50**
- At p=0.10 or p=0.90: **~0.20%**
- At p=0.05 or p=0.95: **~0.06%**
- Near extremes (0.01/0.99): **~0%**

**Key table (per 100 shares):**
| Price | Fee (USDC) | Effective Rate |
|-------|-----------|---------------|
| $0.10 | $0.02 | 0.20% |
| $0.20 | $0.13 | 0.64% |
| $0.30 | $0.33 | 1.10% |
| $0.50 | $0.78 | 1.56% |
| $0.70 | $0.77 | 1.10% |
| $0.90 | $0.18 | 0.20% |

### Post-Only Orders & Maker Rebates
- **Post-only orders** available since Jan 2026 — limit orders rejected if they'd immediately match
- Maker orders that get filled earn **daily USDC rebates** from the taker fee pool
- **Current rebate: 20%** of taker fees collected in that market, distributed proportionally by maker volume
- Rebates are **ex-post, pool-based, non-deterministic** — NOT a guaranteed per-fill discount
- Formula: `your_rebate = (your_fee_equivalent / total_fee_equivalent) * rebate_pool`
- You compete only with other makers in the SAME market

### Critical API Details
```
GET https://clob.polymarket.com/fee-rate?token_id={token_id}
# Returns: { "fee_rate_bps": 1000 } for fee-enabled, 0 for free
```
Always fetch dynamically, never hardcode.

---

## 2. Strategies People Are ACTUALLY Running

### Strategy A: Temporal/Latency Arbitrage (THE DOMINANT BOT STRATEGY)
**The $313 → $414K bot** (documented by Dexter's Lab, Jan 2026):
- Trades exclusively BTC/ETH/SOL 15-min up/down markets
- Places $4,000–$5,000 per trade
- **98% win rate**
- Exploits the fact that **Polymarket prices lag spot exchanges by 1-2 minutes**
- When BTC has already moved decisively on Binance/Coinbase, the Polymarket 15-min contract still shows ~50/50
- Bot buys the "correct" side when real probability is ~85% but market shows 50%
- Thousands of micro-trades, consistent small gains, flattened variance

**How it works technically:**
1. Monitor BTC spot on Binance/Coinbase via WebSocket (sub-second latency)
2. Compare to current Polymarket 15-min contract prices
3. When spot movement implies >X% probability shift but Polymarket hasn't adjusted → enter
4. The "window" where both legs are mispriced is **seconds or less** (per Reddit r/PredictionsMarkets analysis)

**Current status:** Polymarket introduced dynamic taker fees in Jan 2026 SPECIFICALLY to curb this. The fee structure (exponent=2) penalizes mid-price trades most. This has compressed margins but not eliminated the strategy.

### Strategy B: Dual-Side Spread Capture (Market Making)
**The @defiance_cr bot** (open-sourced, documented on Polymarket's own blog):
- Started with $10K capital
- Peak earnings: **$700-800/day**
- Strategy: Place orders on both sides of low-volatility markets
- Key insight: Polymarket's liquidity rewards program pays **~3x more for two-sided liquidity**
- Bot ranks markets by volatility/reward ratio, auto-places orders
- **Killed by reward reductions post-2024 election** — less profitable now
- GitHub: https://github.com/warproxxx/poly-maker

**For 15-min BTC specifically:** Market making is harder because:
- Volatility is high → adverse selection is severe
- You WILL get picked off when BTC moves fast
- Need to quote wide spreads (5-10c) to survive, but then takers won't fill you
- Works better on political/sports markets with slow-moving fundamentals

### Strategy C: Complementary Pair Arbitrage (YES + NO < $1)
- Buy both YES and NO when combined price < $1.00
- Guaranteed $1.00 payout regardless of outcome
- Profit = $1.00 - (YES price + NO price) - fees
- **Reality check from Reddit:** "The interval where both legs are genuinely mispriced at the same time is extremely brief, often seconds or less, and frequently collapses the moment one side is lifted"
- Need to fill BOTH legs simultaneously or you have directional risk
- After taker fees (up to 1.56% per side at 50c), spread needs to be >3.12% to break even
- **Verdict: Mostly competed away. Requires sub-second execution.**

### Strategy D: Momentum Front-Running
**One Reddit user's documented failure:**
- Idea: Detect momentum on Binance, front-run Polymarket 15-min markets before adjustment
- Paper trading showed 36.7% win rate (looked promising)
- **Complete failure live** — was using Gamma API bid prices for paper trading but CLOB API ask prices for execution
- **Lesson: Your backtest MUST match real execution conditions exactly**
- Mismatched price feeds (Gamma API vs CLOB API) will create phantom profits

### Strategy E: AI/ML Ensemble Models
- Bot documented by Igor Mikerin: **$2.2M in 2 months**
- Uses ensemble probability models trained on news + social data
- Targets contracts undervalued relative to real-world probabilities
- Continuously retrains models
- More applicable to longer-duration markets than 15-min BTC

---

## 3. The Adverse Selection Problem (CRITICAL)

### The Core Issue
In 15-min BTC markets, if you're market making:
- When BTC is flat → your quotes get filled naturally, you earn spread ✅
- When BTC moves fast → informed traders (latency arb bots) pick off your stale quotes ❌
- **You make money when nothing happens and lose when something happens**
- This is the classic "picking up pennies in front of a steamroller"

### How Successful Makers Avoid Getting Picked Off
1. **Real-time spot feeds:** WebSocket connections to Binance, Coinbase, Bybit — sub-100ms latency
2. **Cancel-before-fill:** Monitor spot, immediately cancel stale orders when BTC moves >X bps
3. **Wide spreads during volatility:** Dynamically widen quotes when realized vol spikes
4. **Asymmetric quoting:** If spot is trending up, pull your sell-side or quote it much wider
5. **Latency infrastructure:** Servers geographically close to Polymarket's nodes (reported by ainvest.com)
6. **Inventory limits:** Hard caps on directional exposure (e.g., max $5K net YES or NO)

### Data Feeds Used by Profitable Traders
- **Primary:** Binance BTC/USDT WebSocket (trade stream + orderbook)
- **Secondary:** Coinbase, Bybit for confirmation
- **Polymarket:** CLOB WebSocket for own order management
- **Latency budget:** Need <500ms round-trip to have any edge; top bots are <100ms

### The Reddit Expert Take (r/PredictionsMarkets):
> "The binding constraint in the BTC 15-minute Polymarket windows is not math. It is latency and adverse selection. If you are not explicitly modelling fill timing versus book reversion, you do not have an arbitrage. You have a description."

---

## 4. Concrete Numbers

### ROI Ranges (from documented cases)
| Strategy | Capital | Monthly Return | Win Rate | Status |
|----------|---------|---------------|----------|--------|
| Latency arb bot | $5-50K | 100-1000%+ | 85-98% | Still works but margins compressed |
| Market making (political) | $10-50K | 15-30% | N/A | Reduced since reward cuts |
| MM on 15-min BTC | $10K+ | Variable, high risk | 50-60% | Very competitive |
| AI ensemble | $100K+ | 50-100%+ | 60-70% | Requires ML infrastructure |
| YES+NO arb | $10K+ | 2-5% | ~100% | Nearly competed away |

### Capital Requirements
- **Minimum viable:** $5K for latency arb, $10K for market making
- **Competitive:** $50K+ to run meaningful size
- **The $273K profit bot:** Made $3 bets 80,000+ times — high frequency, small size

### Competition Level (Feb 2026)
- 15-min BTC markets: **EXTREMELY competitive** — dozens of sophisticated bots
- Polymarket's @defiance_cr noted only "3-4 serious LPs" when he started — now many more
- HFT/front-running bots documented (0xEthan's front-run bot)
- **The easy money is gone.** Latency arb margins compressed by taker fees + more competition

---

## 5. Code & API Resources

### Official
- **Python CLOB client:** `pip install py-clob-client` — https://github.com/Polymarket/py-clob-client
- **TypeScript client:** `npm install @polymarket/clob-client` — https://github.com/Polymarket/clob-client
- **Unified Python APIs:** `pip install polymarket-apis` (Pydantic models, WebSocket support)
- **Official AI agents:** https://github.com/Polymarket/agents
- **CLOB endpoint:** `https://clob.polymarket.com`
- **WebSocket:** `wss://clob.polymarket.com`

### Open Source Bots
1. **poly-maker** (by @defiance_cr) — https://github.com/warproxxx/poly-maker
   - Market making bot, volatility ranking, auto-quoting
   - The most legitimate open-source option
2. **polymarket-market-maker-bot** — https://github.com/lorine93s/polymarket-market-maker-bot
   - Inventory management, cancel/replace cycles, risk controls
3. **Polymarket-spike-bot-v1** — https://github.com/Trust412/Polymarket-spike-bot-v1
   - Spike detection, auto position management
4. **Various copy-trading bots** on GitHub (lower quality, mostly clones)

### Architecture Pattern (from QuantJourney)
Best practice is a **dual-loop architecture:**
1. **Async loop:** WebSocket feed from CLOB + Binance → writes to thread-safe cache
2. **Sync loop:** Reads cache, runs strategy logic, places orders via REST
3. Connected via thread-safe `BookSnapshot` dataclass

```python
# Simplified structure
import threading
from dataclasses import dataclass

@dataclass
class BookSnapshot:
    token_id: str
    best_bid: float
    best_ask: float
    spread: float
    imbalance: float
    last_update: float

# Async WebSocket → writes to cache
# Sync strategy loop → reads from cache → places orders
```

---

## 6. What NOT To Do

### Mistake 1: Mismatched Price Feeds
Using Gamma API for backtesting but CLOB API for execution creates phantom profits. **Every "profitable" signal was a fantasy.** Always use the same data source for backtest and live.

### Mistake 2: Ignoring the Fee Curve
At p=0.50, you need **3.13% edge just to break even on fees**. At p=0.90, you need **5.63%** despite lower absolute fees (because upside is only 10c). There's no universal sweet spot.

### Mistake 3: Manual Trading on 15-min Markets
Bots achieve 85%+ win rates; humans using similar strategies capture ~50% of the profits. Speed is everything. Don't bother without automation.

### Mistake 4: Oversized Bets
Rule from top traders: **Max 3-5% of capital per event.** Especially avoid entries above 0.55 price unless you have strong informational edge. Avoid 0.65+ entirely.

### Mistake 5: Market Making Without Adverse Selection Protection
Quoting static spreads on 15-min BTC = guaranteed losses to informed flow. You MUST have real-time spot data and cancel stale orders within milliseconds.

### Mistake 6: Assuming Rebates Are Guaranteed
Maker rebates are discretionary, pool-based, and have changed multiple times (100% → 20% → fee-curve weighted). Don't model them as a guaranteed revenue stream.

### Mistake 7: Building Without Understanding Settlement
Orders are signed on Polygon. Gas costs, nonce management, and CTF token mechanics add complexity. Use the official clients to handle this.

---

## 7. Alternative Angles

### Oracle Timing Exploit
- Polymarket uses UMA's Optimistic Oracle (NOT Chainlink for BTC minute markets)
- Prices proposed are NOT disputed unless challenged → 2-hour dispute window
- For 15-min markets, resolution is based on **Pyth/Chainlink price feeds at specific timestamps**
- **Potential edge:** If you know the exact oracle query time and can predict where price will be at that instant, you could have edge in the final minutes
- **Reality:** This is already exploited by the latency arb bots — they're essentially front-running the oracle resolution

### Cross-Market Plays
- **Polymarket vs Kalshi:** Both offer BTC short-term contracts. Arbitrage possible but:
  - Different fee structures
  - Different settlement rules
  - Kalshi is US-regulated, Polymarket is offshore
  - Reddit user built a Kalshi-Polymarket arb bot (r/algotrading) — code available
- **Polymarket vs BTC Futures/Options:**
  - 15-min Polymarket contracts are effectively binary options
  - Can hedge with BTC perpetuals on Binance
  - Example: Buy UP at 0.45 on Polymarket, short BTC perps as hedge
  - Profit if Polymarket was mispriced relative to actual distribution
  - Requires sophisticated delta-hedging

### Information Asymmetry Exploits
- **Binance order flow:** Large market buys on Binance predict BTC direction for next 15 min
- **Funding rates:** Extreme funding rates correlate with short-term reversals
- **Liquidation cascades:** Monitor liquidation levels → predict forced selling/buying
- **On-chain whale movements:** Large USDC/BTC transfers to exchanges signal imminent sells

---

## 8. Bottom Line Assessment

### Who Makes Money (Feb 2026)
1. **Latency arbitrageurs** with sub-second infrastructure — margins compressed but still profitable
2. **Sophisticated market makers** with real-time adverse selection protection — requires significant infrastructure
3. **AI/ML operators** with ensemble models — mostly on longer-duration markets

### Who Loses Money
1. Manual traders on 15-min markets
2. Bots with >500ms latency
3. Anyone ignoring the fee curve
4. Market makers without spot data feeds

### Honest Assessment
The 15-min BTC markets on Polymarket are now a **professional algorithmic trading arena**. The easy latency arb that turned $313 into $414K has been partially addressed by dynamic fees. What remains is a competitive, low-margin game that requires:
- Sub-second execution infrastructure
- Real-time multi-exchange data feeds
- Sophisticated risk management
- $10K+ capital minimum
- Continuous strategy adaptation

**If you're starting from zero, the expected ROI after accounting for development time is likely negative** unless you have existing HFT/quant infrastructure you can adapt.

The better opportunity may be in **less competitive Polymarket segments** (sports, politics) where market making with wider spreads and lower adverse selection still works.

---

*Sources: Polymarket docs, Reddit (r/PolymarketTrading, r/PredictionsMarkets, r/algotrading), BeInCrypto, QuantJourney, The Block, FinanceMagnates, GitHub repos*
