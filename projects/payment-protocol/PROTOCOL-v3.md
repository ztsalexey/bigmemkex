# Pay Protocol v3

> **One primitive: a signed intent to move money.**
> Everything else — subscriptions, disputes, agent payments — emerges from that.

---

## Protocol Essence (One Page)

**The insight:** A payment is just a signed message: *"I authorize X tokens to Y under conditions Z."* If you make that message expressive enough, you don't need separate systems for subscriptions, escrows, refunds, or agent payments. You need **one message type** and **one smart account**.

**The architecture:**

```
User (smart account + passkey)
  → signs Payment Intent
    → Relayer submits on-chain
      → Done.
```

**What's in the protocol:** Accounts, Intents, Modules.
**What's NOT in the protocol:** Merchant tools, compliance, analytics, dispute UX. Those are applications built on top.

**Name: Pay Protocol.** Not SovPay. The protocol is the primitive. Apps have brand names. The protocol is just "Pay."

**Tagline:** *Sign. Send. Settled.*

---

## 1. Accounts

An ERC-7579 smart account on Base. One factory, deterministic addresses (CREATE2).

**Authentication** is a module concern, not a protocol concern:

| Default | Alternative |
|---------|-------------|
| Passkey (WebAuthn/P-256) | Hardware key, session key, multisig |

That's it. The account holds tokens and executes intents. Everything else is a module.

**Recovery** is also a module. Default: multi-device passkeys. Optional: social recovery (3-of-5, 24h timelock). The protocol doesn't care how you recover — it cares that your account has a valid signer.

**First transaction:** Paymaster sponsors deployment (~$0.01). User never knows it happened.

---

## 2. The Intent

The entire protocol is this struct:

```solidity
struct Intent {
    address token;       // what to pay
    address to;          // who gets paid  
    uint256 amount;      // how much
    bytes32 condition;   // keccak256 of conditions (or 0x0 for unconditional)
    uint256 nonce;       // replay protection
    uint256 deadline;    // expiry (unix timestamp)
    bytes signature;     // account owner's sig
}
```

**One-time payment:** `condition = 0x0`, `deadline = now + 5min`.
**Subscription:** `condition = hash(period, maxPulls, merchant)`, `deadline = far future`.
**Agent session:** `condition = hash(perTxLimit, dailyLimit, allowedRecipients)`, signed by session key.
**Escrow:** `condition = hash(releaseCondition, timeout, refundAddress)`.

One struct. Four use cases. The condition field is the entire extension mechanism.

### Condition Modules

A condition is a contract that implements:

```solidity
interface ICondition {
    function check(Intent calldata intent, bytes calldata proof) external view returns (bool);
}
```

**Core conditions** (audited, ship with protocol):
- `RecurringCondition` — enforces period, max pulls, merchant-only execution
- `SessionCondition` — enforces spending limits, recipient whitelist, expiry
- `TimelockCondition` — enforces delay + cancel window

**Anyone can write new conditions.** That's the composability.

---

## 3. Execution

```
Intent → Relayer (bundler + paymaster) → EntryPoint → Account → Transfer
```

Gas is invisible. User pays in USDC (tiny deduction, ~$0.003). Paymaster fronts ETH. Chainlink oracle for rate.

**The relayer is not the protocol.** It's infrastructure. Anyone can run one. The reference relayer does sanctions screening because it operates under US law. The contracts don't care.

---

## 4. Fees

| Action | Fee | Who pays |
|--------|-----|----------|
| Send to a person | Free | — |
| Pay a merchant | 0.3% (cap $2) | Merchant |
| Recurring pull | 0.1% | Merchant |

No token. Revenue = fees. Breakeven at ~$80M monthly volume.

---

## 5. Security

Security is three things:

1. **Spending limits** — per-token, per-day. Changing limits = 24h timelock. This IS fraud protection.
2. **Self-freeze** — instant from any device. 24h to unfreeze. 
3. **Intent expiry** — every intent has a deadline. No permanent authorizations.

That's it. No complex policy engine. Limits + freeze + expiry cover 95% of threats.

For the other 5%: install modules (multisig, whitelist-only, guardian freeze). Power users opt in. Defaults are simple.

---

## 6. What's NOT in the Protocol

These are **applications**, not protocol features:

| Application | Built by |
|-------------|----------|
| Merchant SDK, QR codes, webhooks | Us (reference implementation) |
| Dispute resolution | Application layer (timeout + refund) |
| KYC / compliance | Relayer and app layer |
| Fiat on/off-ramp | Integration partners |
| Multi-chain bridging | Deferred (ERC-7683 when mature) |
| Analytics, dashboards | Anyone |
| NFC tap-to-pay | Future app feature |

The protocol is 3 contracts: **AccountFactory**, **IntentExecutor**, **ConditionRegistry**.

---

## 7. Developer Quick Start

```typescript
import { Pay } from '@pay-protocol/sdk';

// Initialize
const pay = Pay.connect({ network: 'base' });

// Create payment request (merchant)
const link = pay.request({ amount: '4.50', token: 'USDC', ref: 'order_123' });
// → returns URL, QR code, deep link

// Listen for payment
pay.on('settled', (e) => console.log(`Paid: ${e.ref}`));
```

**Hello World:** 4 lines to accept a payment. That's the bar.

**Agent payment (x402):**
```
GET /api/data
→ 402 Payment Required (X-Pay-Amount: 0.001, X-Pay-To: 0x...)
→ Agent signs Intent with session key
→ Retries with X-Pay-Proof header
→ 200 OK
```

---

## 8. Ship Plan

**Weeks 1-8:** Account factory, passkey auth, intent executor, P2P transfers, paymaster, web app.
**Weeks 9-16:** Merchant SDK, recurring conditions, session keys, dispute module, mobile PWA.
**After that:** Multi-chain, advanced conditions, ecosystem growth.

**Success:** 500 accounts, 5K transactions in first 8 weeks.

---

## 9. Why This Wins

| Wedge | Why |
|-------|-----|
| AI agent payments | Only protocol with native x402 + session keys |
| Creator subscriptions | 0.1% vs Patreon's 5-12% |
| Cross-border freelancers | Instant, near-free, no bank needed |

---

## 10. Honest Limits

- Needs internet
- On-chain = public (no privacy)
- Stablecoins only (not fiat)  
- Base L2 = centralized sequencer (Optimism as backup)

We'll fix these over time. We won't pretend we already have.

---

*Pay Protocol v3. The elegant version.*
*Three contracts. One intent struct. Everything else is modules.*
