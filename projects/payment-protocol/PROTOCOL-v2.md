# SovPay Protocol Specification v2

> **"Your keys. Your money. No compromises."**

**Version:** 0.2.0-draft
**Date:** 2026-02-07
**Status:** RFC / Pre-Implementation
**Changes from v1:** Hardened economics, compliance layer, scoped MVP, honest privacy posture

---

## Table of Contents

1. [Vision & Principles](#1-vision--principles)
2. [Architecture Overview](#2-architecture-overview)
3. [Account System](#3-account-system)
4. [Payment Flows](#4-payment-flows)
5. [Merchant Integration](#5-merchant-integration)
6. [Gas & Fee Model](#6-gas--fee-model)
7. [Security Model](#7-security-model)
8. [Compliance Framework](#8-compliance-framework)
9. [Multi-Chain Strategy](#9-multi-chain-strategy)
10. [Sustainability Model](#10-sustainability-model)
11. [Operational Requirements](#11-operational-requirements)
12. [Roadmap](#12-roadmap)

---

## 1. Vision & Principles

### Mission

Replace the bank account for everyday payments — without replacing the user's control over their money.

### Core Principles

| # | Principle | Meaning |
|---|-----------|---------|
| 1 | **Self-custody by default** | Users hold keys. No "hosted wallet" mode. |
| 2 | **Passkey-first, not passkey-only** | Default: device biometrics. Also supports hardware keys and backup keys. |
| 3 | **Invisible infrastructure** | Users see balances and payments, not gas and chains. |
| 4 | **Composable & modular** | Features are ERC-7579 modules. Swap, extend, or remove. |
| 5 | **Honest privacy** | On-chain payments are publicly visible. We minimize metadata, not pretend it's private. |
| 6 | **No token required** | Protocol sustains on usage fees, not speculation. |
| 7 | **Compliance-compatible** | Contracts are permissionless. Applications comply with local law. |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       CLIENT LAYER                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐ │
│  │  Mobile   │  │   Web    │  │ Merchant │  │ x402 Agent │ │
│  │   PWA     │  │   App    │  │   SDK    │  │  Client    │ │
│  └─────┬─────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘ │
└────────┼──────────────┼─────────────┼──────────────┼────────┘
         │              │             │              │
┌────────▼──────────────▼─────────────▼──────────────▼────────┐
│                   RELAY LAYER (off-chain)                    │
│  ┌────────────┐  ┌────────────┐  ┌──────────────────────┐   │
│  │  Bundler   │  │ Paymaster  │  │  Compliance Filter   │   │
│  │ (ERC-4337) │  │  Service   │  │  (sanctions screen)  │   │
│  └─────┬──────┘  └─────┬──────┘  └──────────┬───────────┘   │
│        └────────────────┼────────────────────┘               │
│                         │                                    │
│  ┌──────────────────────▼────────────────────────────────┐   │
│  │                UserOperation Queue                    │   │
│  └──────────────────────┬────────────────────────────────┘   │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                 ON-CHAIN LAYER (Base L2)                     │
│                                                              │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │  SovPay      │  │  Module       │  │  Payment         │  │
│  │  Account     │  │  Registry     │  │  Registry        │  │
│  │  (ERC-7579)  │  │  (2-tier)     │  │                  │  │
│  └──────────────┘  └───────────────┘  └──────────────────┘  │
│                                                              │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │  EntryPoint  │  │  Paymaster    │  │  USDC / EURC     │  │
│  │  (v0.7)      │  │  Contract     │  │  Contracts       │  │
│  └──────────────┘  └───────────────┘  └──────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### On-Chain (minimal, immutable)
- Account ownership, module authorization
- Token custody and transfers (ERC-3009)
- Subscription agreements
- Dispute escrow and timeout resolution
- Spending limit enforcement

### Off-Chain (flexible, upgradeable)
- Payment metadata, invoices, receipts
- Compliance screening
- Notification delivery
- Paymaster gas pricing oracle
- Fraud scoring (advisory only)

---

## 3. Account System

### 3.1 Smart Account Structure

Each SovPay account is an **ERC-7579 modular smart account** deployed via factory on Base. Built on an established implementation (Rhinestone/Biconomy), not custom.

```
SovPayAccount (ERC-7579)
├── Validator Modules (who can sign)
│   ├── PasskeyValidator (RIP-7212, default)
│   ├── HardwareKeyValidator (YubiKey P-256, Ledger secp256k1)
│   ├── SessionKeyValidator (delegated, scoped)
│   └── SocialRecoveryValidator (guardians)
├── Executor Modules
│   ├── PaymentExecutor (transfers, ERC-3009)
│   ├── SubscriptionExecutor (recurring pulls)
│   └── BatchExecutor (multi-transfer + swap)
├── Hook Modules
│   ├── SpendingLimitHook (daily/weekly/monthly caps)
│   └── WhitelistHook (restrict destinations)
└── Fallback Modules
    └── ERC-1271 Signature Validation
```

### 3.2 Authentication

**Primary: Passkeys** (WebAuthn / P-256)
- Registration creates device-bound or synced passkey
- RIP-7212 precompile on Base: ~3,500 gas for verification
- Multi-device: each device registers its own passkey as a valid signer

**Secondary: Hardware Keys**
- YubiKey (P-256 via WebAuthn — same precompile)
- Ledger/Trezor (secp256k1 via `HardwareKeyValidator` module)
- Any FIDO2-compatible hardware token

**Backup: Emergency Access Key**
- Optional: user generates a secp256k1 key pair at setup
- Private key displayed once as QR code / mnemonic for physical storage
- Registered as a valid signer with 24h timelock on all operations
- User is warned: "Print this. Store in a safe. Never photograph it."

### 3.3 Recovery

| Method | Mechanism | Timelock | Cancel window |
|--------|-----------|----------|---------------|
| **Multi-device** | Any registered passkey/hardware key signs | Instant | N/A |
| **Social recovery** | 3-of-5 guardians co-sign key rotation | 24h | 24h |
| **Email recovery** | ZK-Email proof triggers recovery | 7 days | 7 days |
| **Emergency key** | Backup key signs with timelock | 24h | 24h |

All recovery paths have a cancel window: the current key holder can abort any in-progress recovery. Prevents social engineering on guardians.

### 3.4 Account Deployment

Accounts use CREATE2 — address is deterministic before deployment. Users can receive funds immediately.

**First transaction experience:**
1. User initiates first action
2. Paymaster sponsors account deployment (~500K gas, ~$0.01 on Base)
3. User sees "Setting up your account..." (2-3 seconds)
4. Deployment + first operation execute atomically
5. Subsequent transactions are normal cost

---

## 4. Payment Flows

### 4.1 One-Time Payments

#### P2P Transfer
```
Alice → Bob (10 USDC)

1. Alice enters Bob's handle, ENS, or address
2. Client constructs UserOperation: USDC.transfer(bob, 10e6)
3. Alice authenticates (passkey / hardware key)
4. Bundler submits to EntryPoint
5. Bob receives 10 USDC, push notification sent
```

**Optimization:** ERC-3009 `transferWithAuthorization` — Alice signs off-chain, recipient or relayer submits. Enables gasless sends.

#### P2M (Pay Merchant)
```
Alice → CoffeeShop (4.50 USDC)

1. Merchant displays QR / deep link:
   {to: addr, amount: 4.50, currency: "USDC", ref: "order_123"}
2. Alice scans → "Pay $4.50 to CoffeeShop?"
3. Alice authenticates → UO submitted
4. Merchant receives webhook confirmation (<2s)
```

### 4.2 Recurring Payments (Subscriptions)

```solidity
struct Subscription {
    address token;
    address merchant;        // only merchant can pull
    uint256 amount;
    uint256 period;          // seconds between charges
    uint256 maxPeriods;      // 0 = infinite
    uint256 startTime;
    uint256 lastCharged;
    uint256 gracePeriod;     // seconds after period before pullable (default: 24h)
    bool active;
}
```

**Flow:**
1. User approves subscription → installs `SubscriptionExecutor`, signs terms
2. After each period + grace period, **only the merchant** (or their authorized operator) calls `executeSubscription(subscriptionId)`
3. Module validates: period elapsed, grace period passed, amount matches, subscription active
4. Transfer executes user → merchant
5. User cancels anytime — single transaction, immediate

**Key constraints:**
- Only the merchant address (or operator set by merchant) can call execute
- Grace period (default 24h) gives users time to ensure balance or cancel before pull
- User can set per-subscription spending caps as an additional guard

### 4.3 x402 Payments (AI Agent Compatible)

```
Agent → API (0.001 USDC per request)

1. Agent requests endpoint → receives 402 Payment Required
   Headers: X-Payment-Amount, X-Payment-Address, X-Payment-Network
2. Agent's session key validates amount against policy
3. Signs ERC-3009 authorization
4. Retries with X-Payment-Proof header
5. Server verifies, serves content
```

**Session key constraints for agents:**
- Mandatory expiry: max 30 days
- Per-recipient spending limit
- Aggregate daily limit
- Whitelisted recipient addresses (optional)
- Instant revocation by account owner (no timelock)
- Real-time spend notifications to owner

### 4.4 Batch Payments

```
BatchExecutor: N transfers in one UserOperation
- Atomic: all succeed or all revert
- Single signature
- Supports swap-then-pay (DEX integration for token conversion)
```

### 4.5 Multi-Token Payments

User holds EURC, merchant wants USDC:

```
1. Client detects currency mismatch
2. Constructs batch: swap(EURC→USDC via DEX) + transfer(USDC to merchant)
3. Chainlink oracle provides rate, user confirms total
4. Atomic execution: swap + pay in one UserOperation
```

Supported tokens: any ERC-20 with DEX liquidity. Merchant specifies accepted tokens.

---

## 5. Merchant Integration

### 5.1 SDK

```typescript
import { SovPay } from '@sovpay/merchant-sdk';

const sovpay = new SovPay({
  merchantId: '0xMerchantAddress',
  webhookSecret: 'whsec_...',
  network: 'base',
});

const request = sovpay.createPaymentRequest({
  amount: '49.99',
  currency: 'USDC',
  reference: 'order_456',
  callbackUrl: 'https://shop.example/webhook',
  disputeWindow: 14,  // days (min 7 for standard payments)
});

// Returns: { qr, deepLink, requestId }

sovpay.on('payment.confirmed', (event) => {
  fulfillOrder(event.reference);
});
```

### 5.2 Settlement

| Mode | Latency | Description |
|------|---------|-------------|
| **Instant** | ~2s | Direct to merchant address. Default. |
| **Batched** | 1-24h | Aggregated sweep. Lower cost at scale. |
| **Fiat off-ramp** | Minutes-hours | Auto-convert via Coinbase/Bridge integration. |

### 5.3 Dispute Resolution (Simplified)

**V1 supports two resolution paths only:**

```
1. MUTUAL: Merchant issues refund → dispute closed
2. TIMEOUT: Merchant doesn't respond in 7 days → auto-refund to buyer
```

Arbitration (Kleros/UMA) deferred to V2 when volume justifies it.

**Dispute economics:**
- Filing fee: **2% of disputed amount** (min $5, max $50)
- Fee refunded to winner
- Dispute window: **merchant-configurable, protocol minimum 7 days** for standard payment flow payments
- Raw transfers (P2P) have no dispute mechanism (by design — you control who you send to)

**Anti-griefing measures:**
- Filing fee scales with amount (prevents $1-cost spam disputes)
- Merchant can set a dispute bond requirement (frozen from their account during resolution)
- Repeated dispute losers face escalating filing fees (2x, 4x)
- Merchant repeated-loss penalty: increased dispute bond requirement

### 5.4 Refunds

```solidity
merchant.refund(paymentId, amount);  // partial or full, push-based
```

Linked to original payment ID. Receipt event emitted. No buyer action needed.

---

## 6. Gas & Fee Model

### 6.1 Paymaster

Users never think about gas.

| Tier | Who pays | When |
|------|----------|------|
| **Sponsored** | Protocol / merchant | Account deployment, promotional |
| **USDC-deducted** | User (in USDC) | Default — small deduction alongside payment |
| **Self-pay** | User (in ETH) | Power user opt-in |

**USDC deduction:** User sends 10 USDC → actually debited 10.003 USDC. Paymaster fronts ETH gas, reimburses from USDC. Exchange rate from Chainlink oracle + 10bp buffer for volatility.

### 6.2 Protocol Fees

| Fee type | Amount | Paid by |
|----------|--------|---------|
| **P2P transfer** | Free | — |
| **P2M payment** | 0.3% (max $2) | Merchant |
| **High-volume merchant** (>$100K/month) | 0.1% (max $1) | Merchant |
| **Subscription pull** | 0.1% | Merchant |
| **Dispute filing** | 2% of amount (min $5, max $50) | Disputant (refunded to winner) |
| **Account deployment** | Sponsored | Protocol |

**vs. traditional payments:**

| | Credit Card | SovPay | Savings |
|---|---|---|---|
| Merchant fee | 2.5-3.5% | 0.1-0.3% | 90-97% reduction |
| Settlement | T+2 days | ~2 seconds | Instant |
| International | 1-3% extra | 0% | Free |
| Chargeback risk | Uncapped | Structured, capped | Predictable |

### 6.3 Sustainability

```
Revenue at $100M monthly volume:
├── Merchant fees (0.3% avg)    = $300K/month
├── Paymaster spread (10bp)     = $10K/month
├── Enterprise API access       = variable
└── Total                       ≈ $310K/month

Costs:
├── Bundler infrastructure      = $30K/month
├── Paymaster ETH float         = $20K/month (cost of capital)
├── Compliance infrastructure   = $50K/month
├── Security (audits, bounties) = $40K/month
├── Team + operations           = $100K/month
└── Total                       ≈ $240K/month

Breakeven: ~$80M monthly volume
```

Sustainable without a token. No governance token planned. 

---

## 7. Security Model

### 7.1 Spending Limits

```
SpendingLimits (per-token, per-signer):
  dailyLimit:   500 USDC
  weeklyLimit:  2000 USDC
  perTxLimit:   200 USDC
  monthlyLimit: 5000 USDC
```

- Changing limits requires primary signer + **24h timelock**
- Session keys have independent (lower) limits
- Limits ARE the fraud protection. Simple, predictable, self-sovereign.

### 7.2 Signing Policies

| Policy | Description |
|--------|-------------|
| **Single-sig** | Default. One passkey/hardware key. |
| **Multi-sig** | High-value: 2-of-N devices. |
| **Session keys** | Scoped: max amount, allowed recipients, expiry (max 30d), instant revocation. |
| **Whitelist-only** | Only pre-approved addresses. Good for savings. |
| **Time-delayed** | Above threshold: N-hour delay with cancel window. |

### 7.3 Account Freezing

- **Self-freeze:** Instant from any registered device. 24h timelock to unfreeze.
- **Guardian freeze:** 2-of-5 guardians can freeze if user reports compromise.
- **Protocol cannot freeze contracts.** Smart contracts are permissionless and immutable.
- **Relay layer can refuse service** to comply with legal obligations (see §8).

### 7.4 Module Registry (Two-Tier)

| Tier | Curation | Access |
|------|----------|--------|
| **Audited** | Protocol-reviewed, audited by reputable firms | Default for all users |
| **Community** | Permissionless deployment, user opt-in | Explicit warning: "unaudited module" |

---

## 8. Compliance Framework

### 8.1 Architecture

**Smart contracts are permissionless.** Anyone can deploy an account, anyone can transfer tokens. The protocol does not and cannot enforce KYC at the contract level.

**Applications and relay services comply with local law.** This is where compliance lives:

```
Compliance boundary:

  Permissionless (unstoppable):     Compliant (regulatable):
  ┌──────────────────┐              ┌──────────────────┐
  │  Smart contracts  │              │  SovPay App      │
  │  - Accounts       │              │  - KYC for       │
  │  - Modules        │              │    thresholds    │
  │  - Payment Reg.   │              │  - Sanctions     │
  │                    │              │    screening     │
  │  Anyone can        │              │  Bundler/Relay   │
  │  interact directly │              │  - Travel rule   │
  │                    │              │  - OFAC screen   │
  │                    │              │  Merchant SDK    │
  │                    │              │  - Tax reporting │
  │                    │              │  - 1099-K / VAT  │
  └──────────────────┘              └──────────────────┘
```

### 8.2 Relay-Level Compliance

The bundler and paymaster services operated by SovPay (the company) will:

1. **Sanctions screening:** OFAC/EU sanctions lists checked before bundling UserOperations. Flagged addresses are refused relay service. Users can always self-relay through the public EntryPoint.
2. **Travel rule:** For transfers above jurisdictional thresholds, relay layer collects and transmits originator/beneficiary information per FATF guidelines.
3. **Suspicious activity reporting:** Relay layer files SARs when required by applicable law.

### 8.3 Application-Level Compliance

The SovPay reference app will:
- KYC users above configurable thresholds (jurisdiction-dependent)
- Provide merchants with tax-reportable transaction summaries
- Comply with local payment regulations in each operating jurisdiction

### 8.4 What We Don't Do

- We do not build KYC into the smart contracts
- We do not maintain a global blocklist at the protocol level
- We do not pretend the contracts can be censored — they can't
- We are transparent that relay-level compliance is a pragmatic necessity, not a protocol feature

---

## 9. Multi-Chain Strategy

### 9.1 Base as Primary (MVP)

**Why:** Low gas, RIP-7212 (passkey precompile), Coinbase ecosystem, ERC-4337 native.

**Risk acknowledged:** Base is a centralized L2 (single sequencer, Coinbase-operated). This is a pragmatic launch choice, not an endorsement.

### 9.2 Hot Backup (Launch Requirement)

Contract set deployed and tested on **Optimism** before mainnet launch. If Base has extended downtime or censorship issues, relay layer can redirect to Optimism within hours.

### 9.3 Expansion (V2+)

Multi-chain with unified balance abstraction. Deferred until ERC-7683 matures and there's sufficient volume to justify the complexity.

---

## 10. Sustainability Model

### No Token. No Governance Token. No Plans for One.

Revenue streams:
| Stream | Driver |
|--------|--------|
| Merchant fees (0.1-0.3%) | Transaction volume |
| Paymaster spread | Transaction count |
| Enterprise API | B2B integrations |

### Governance

**Now:** Multisig (core team + advisors). Ship product.
**Later:** Revisit when there are actual stakeholders. Premature governance is premature optimization.

---

## 11. Operational Requirements

### 11.1 Monitoring

| Component | Monitored | Alert threshold |
|-----------|-----------|-----------------|
| Bundler | Uptime, tx inclusion latency, queue depth | >5s latency, >100 queue depth |
| Paymaster | ETH balance, USDC float, exchange rate drift | <$10K ETH, >50bp drift |
| Base RPC | Block production, reorg detection | >10s no block, any reorg |
| Payment Registry | Dispute volume, settlement failures | >1% dispute rate |

### 11.2 Circuit Breakers

- Paymaster pauses if ETH balance drops below threshold
- Bundler pauses if gas price exceeds 10x baseline
- Subscription executor pauses if >N consecutive failures for a merchant
- Automatic failover to Optimism backup if Base is unresponsive for >5 minutes

### 11.3 Incident Response

- On-call rotation for relay layer issues
- Runbook for: paymaster drain, bundler DOS, Base sequencer down, module vulnerability
- Bug bounty program (launch with $100K pool)

---

## 12. Roadmap

### MVP (Month 1-3)

**Goal:** Working self-custody payments on Base for crypto-native users

- [ ] SovPayAccount factory (ERC-7579, Rhinestone-based)
- [ ] PasskeyValidator + HardwareKeyValidator
- [ ] One-time P2P and P2M transfers (USDC)
- [ ] Paymaster with USDC gas deduction
- [ ] Web app (create account, send/receive, QR scan)
- [ ] ERC-3009 gasless transfers
- [ ] Multi-device passkeys + emergency backup key
- [ ] Social recovery (3-of-5 guardians, 24h timelock)
- [ ] Spending limits
- [ ] On-ramp integration (Coinbase/Transak)
- [ ] Hot backup deployment on Optimism
- [ ] Compliance filter at relay layer (sanctions screening)
- [ ] Monitoring + alerting infrastructure
- [ ] Bug bounty program launch

**Target market:** AI agent payments (x402), crypto-native freelancers, creator subscriptions
**Success metric:** 500 accounts, 5,000 transactions

### V1 (Month 4-6)

- [ ] Merchant SDK (payment requests, webhooks, QR)
- [ ] SubscriptionExecutor module
- [ ] Session keys for AI agents
- [ ] Dispute resolution (mutual + timeout)
- [ ] Refund handling
- [ ] Multi-token payments (swap + pay)
- [ ] Fiat off-ramp integration
- [ ] Mobile-optimized PWA
- [ ] KYC integration for threshold compliance

**Success metric:** 50 merchants, 50K transactions, $500K monthly volume

### V2 (Month 7-12+)

- [ ] x402 full integration
- [ ] Batch payments
- [ ] Streaming payments
- [ ] Multi-chain (Optimism, Arbitrum, unified balance)
- [ ] Arbitration integration (Kleros/UMA)
- [ ] NFC tap-to-pay
- [ ] Privacy module exploration (Aztec integration when mature)
- [ ] Enterprise features (analytics, API, custom settlement)

---

## Appendix A: Key Dependencies

| Dependency | Status | Risk | Mitigation |
|------------|--------|------|------------|
| ERC-4337 | Mature | Low | Widely adopted |
| ERC-7579 | Live | Low-Medium | Use established implementation |
| RIP-7212 | Live on Base | Low | Also on Optimism |
| ERC-3009 | Live (USDC) | Low | USDC-native support |
| Base L2 | Live | Medium | Optimism hot backup |
| ERC-7683 | Early | Medium | Deferred to V2 |

## Appendix B: Competitive Wedge

SovPay doesn't try to replace Visa on day one. It owns specific wedges where it's 10x better:

| Wedge | Why SovPay wins | Incumbent weakness |
|-------|-----------------|-------------------|
| **AI agent payments** | x402 native, session keys, autonomous | No incumbent |
| **Creator subscriptions** | 0.1% vs 5-12% (Patreon) | Massive fee gap |
| **Cross-border freelancers** | Near-free vs 1-2% (Wise) | Speed + cost |
| **Crypto-native commerce** | Self-custody + merchant tools | Fragmented UX |

## Appendix C: Honest Limitations

Things SovPay v1 does NOT do:
- **Offline payments** — requires internet
- **Full privacy** — all transfers visible on-chain (public ledger)
- **Fiat-denominated accounts** — USDC/stablecoin only
- **Instant fiat settlement** — off-ramp adds latency
- **Hardware POS terminals** — QR/deeplink only at launch
- **Chargeback protection** — dispute system is simpler than credit card protections

We'll address these over time. We won't pretend we already have.

---

*SovPay v2: Honest, lean, and ready to ship.*
