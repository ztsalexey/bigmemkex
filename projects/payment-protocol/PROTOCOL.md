# SovPay Protocol Specification

> **"Your keys. Your money. Their convenience."**

**Version:** 0.1.0-draft
**Date:** 2026-02-07
**Status:** RFC / Pre-Implementation

---

## Table of Contents

1. [Vision & Principles](#1-vision--principles)
2. [Architecture Overview](#2-architecture-overview)
3. [Account System](#3-account-system)
4. [Payment Flows](#4-payment-flows)
5. [Merchant Integration](#5-merchant-integration)
6. [Gas & Fee Model](#6-gas--fee-model)
7. [Security Model](#7-security-model)
8. [Multi-Chain Strategy](#8-multi-chain-strategy)
9. [Token Economics](#9-token-economics)
10. [Roadmap](#10-roadmap)
11. [Appendices](#11-appendices)

---

## 1. Vision & Principles

### Name

**SovPay** — *Sovereign Payments*

Self-custody accounts with the UX people expect from fintech. No seed phrases. No custodians. No permission needed.

### Mission

Replace the bank account for everyday payments — without replacing the user's control over their money.

### Core Principles

| # | Principle | Meaning |
|---|-----------|---------|
| 1 | **Self-custody by default** | Users hold keys. Always. No "hosted wallet" mode. |
| 2 | **Passkey-native** | Auth via device biometrics. No seed phrases, no browser extensions. |
| 3 | **Invisible infrastructure** | Users never see gas, chains, or bridges. They see balances and payments. |
| 4 | **Composable & modular** | Every feature is an ERC-7579 module. Swap, extend, or remove. |
| 5 | **Open settlement** | Anyone can build a merchant SDK, wallet, or integration. Permissionless. |
| 6 | **Privacy-preserving** | Minimal on-chain footprint. Payment metadata stays off-chain. |
| 7 | **No token required** | Protocol sustains on usage fees, not speculation. |

---

## 2. Architecture Overview

### System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT LAYER                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Mobile   │  │   Web    │  │ Merchant │  │  x402 Client  │  │
│  │   App     │  │   App    │  │   POS    │  │  (HTTP Agent) │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └───────┬───────┘  │
└───────┼──────────────┼─────────────┼────────────────┼──────────┘
        │              │             │                │
┌───────▼──────────────▼─────────────▼────────────────▼──────────┐
│                      RELAY LAYER (off-chain)                    │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │  Bundler    │  │  Paymaster   │  │  Intent Relay (P2P     │ │
│  │  (ERC-4337) │  │  Service     │  │  matching, x402, RTP)  │ │
│  └──────┬──────┘  └──────┬───────┘  └───────────┬────────────┘ │
│         │                │                       │              │
│  ┌──────▼────────────────▼───────────────────────▼────────────┐ │
│  │              UserOperation Mempool / Queue                 │ │
│  └──────────────────────┬─────────────────────────────────────┘ │
└─────────────────────────┼──────────────────────────────────────┘
                          │
┌─────────────────────────▼──────────────────────────────────────┐
│                    ON-CHAIN LAYER (Base L2 primary)             │
│                                                                 │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐ │
│  │  SovPay      │  │  Module       │  │  Payment Registry    │ │
│  │  Account     │  │  Registry     │  │  (subscriptions,     │ │
│  │  (ERC-7579)  │  │  (audited     │  │   disputes, escrow)  │ │
│  │              │  │   modules)    │  │                      │ │
│  └──────────────┘  └───────────────┘  └──────────────────────┘ │
│                                                                 │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐ │
│  │  EntryPoint  │  │  Paymaster    │  │  USDC / Token        │ │
│  │  (v0.7)      │  │  Contract     │  │  Contracts           │ │
│  └──────────────┘  └───────────────┘  └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Core Components

| Component | Type | Role |
|-----------|------|------|
| **SovPay Account** | On-chain (ERC-7579 smart account) | User's self-custody wallet — holds funds, enforces policies |
| **Module Registry** | On-chain | Curated list of audited modules users can install |
| **Payment Registry** | On-chain | Subscription agreements, dispute escrows, payment receipts |
| **Bundler** | Off-chain service | Bundles UserOperations and submits to EntryPoint |
| **Paymaster** | On-chain + off-chain | Sponsors gas for qualifying transactions |
| **Intent Relay** | Off-chain service | Matches payment requests, routes x402, handles RTP |
| **Client SDK** | Off-chain library | Wallet/app integration — passkey signing, UO construction |
| **Merchant SDK** | Off-chain library | Payment acceptance, webhook callbacks, settlement |

### On-Chain vs Off-Chain Split

**On-chain (minimal, immutable):**
- Account ownership and module authorization
- Token custody and transfers (ERC-3009 `transferWithAuthorization`)
- Subscription agreements (approve/revoke)
- Dispute escrow and resolution outcomes
- Spending limit enforcement

**Off-chain (flexible, upgradeable):**
- Payment metadata and invoices
- Merchant product catalogs
- Fraud scoring and risk signals
- Notification delivery
- Analytics and reporting

---

## 3. Account System

### 3.1 Smart Account Structure

Each SovPay account is an **ERC-7579 modular smart account** deployed via a factory on Base.

```
SovPayAccount (ERC-7579)
├── Validator Modules (who can sign)
│   ├── PasskeyValidator (RIP-7212, primary)
│   ├── SessionKeyValidator (delegated sessions)
│   └── SocialRecoveryValidator (guardians)
├── Executor Modules (what actions are allowed)
│   ├── PaymentExecutor (transfers, ERC-3009)
│   ├── SubscriptionExecutor (recurring pulls)
│   ├── StreamExecutor (per-second payments)
│   └── BatchExecutor (multi-transfer)
├── Hook Modules (policies enforced pre/post execution)
│   ├── SpendingLimitHook (daily/weekly/monthly caps)
│   ├── WhitelistHook (restrict destinations)
│   └── FraudDetectionHook (velocity checks)
└── Fallback Modules
    └── ERC-1271 Signature Validation
```

### 3.2 Passkey Authentication Flow

No seed phrases. No browser extension. Users authenticate with device biometrics (Face ID, fingerprint, Windows Hello).

**Registration:**
1. User opens SovPay app/web
2. Device generates a passkey (WebAuthn credential, P-256 key pair)
3. Factory deploys SovPayAccount with `PasskeyValidator` initialized to the public key
4. Account address is deterministic (CREATE2) — can receive funds before deployment

**Transaction Signing:**
1. Client constructs a UserOperation
2. UO hash is presented to WebAuthn API
3. User authenticates with biometric → device signs with P-256 private key
4. Signature is verified on-chain via RIP-7212 precompile (native P-256 on Base)
5. EntryPoint validates and executes

**Key detail:** RIP-7212 makes passkey verification gas-cheap (~3,500 gas vs ~300k for Solidity P-256). This is what makes passkey-native accounts viable.

### 3.3 Recovery Mechanisms

| Method | How it works | Time to recover |
|--------|-------------|-----------------|
| **Multi-device** | Register passkeys on 2+ devices. Any device can sign. | Instant |
| **Social recovery** | Designate 3-of-5 guardians (friends, family, other SovPay accounts). Guardians co-sign a key rotation. | 48h timelock |
| **Email recovery** | ZK proof of email ownership (via ZK-Email) triggers recovery with 7-day timelock. | 7 days |
| **Dead man's switch** | If no activity for N days, a pre-designated heir can claim. | Configurable (90-365 days) |

All recovery methods enforce a **timelock** — the current key holder can cancel any recovery in progress. This prevents social engineering attacks on guardians.

### 3.4 Multi-Device Support

- Each device registers its own passkey (separate P-256 key pair)
- All passkeys are registered as valid signers on the `PasskeyValidator` module
- Any single registered device can sign transactions
- Devices can be added/removed by any existing authorized device (with optional timelock for removal)
- **Synced passkeys** (iCloud Keychain, Google Password Manager) provide backup across same-ecosystem devices automatically

---

## 4. Payment Flows

### 4.1 One-Time Payments

#### P2P Transfer
```
Alice → Bob (10 USDC)

1. Alice enters Bob's SovPay handle, ENS, or address
2. Client constructs UserOperation:
   - calldata: USDC.transfer(bob, 10e6)
3. Alice authenticates with passkey
4. Bundler submits to EntryPoint
5. Bob receives 10 USDC, sees push notification
```

**Optimization:** For USDC, use **ERC-3009** `transferWithAuthorization`. Alice signs an off-chain authorization; anyone can submit it. Enables gasless sends where the recipient or relayer submits.

#### P2M (Pay Merchant)
```
Alice → CoffeeShop (4.50 USDC)

1. Merchant displays QR / deep link with payment request:
   {to: merchant_addr, amount: 4.50, currency: "USDC", ref: "order_123"}
2. Alice scans → app shows "Pay $4.50 to CoffeeShop?"
3. Alice authenticates → UO submitted
4. Merchant SDK receives webhook confirmation (<2s on Base)
5. Receipt stored off-chain, hash anchored on-chain
```

### 4.2 Recurring / Subscription Payments

This is the **killer feature** banks have and crypto doesn't. SovPay introduces a new on-chain primitive:

#### SubscriptionExecutor Module

```solidity
struct Subscription {
    address token;           // USDC
    address merchant;        // recipient
    uint256 amount;          // per-period amount
    uint256 period;          // seconds between charges (e.g., 30 days)
    uint256 maxPeriods;      // 0 = infinite
    uint256 startTime;
    uint256 lastCharged;
    bool active;
}
```

**Flow:**
1. User approves a subscription: installs `SubscriptionExecutor`, signs the subscription terms
2. Merchant (or anyone) can call `executeSubscription(subscriptionId)` once per period
3. Module validates: correct period elapsed, amount matches, subscription active
4. Transfer executes from user's account to merchant
5. User can **cancel anytime** — single transaction removes the subscription

**Why this wins:**
- User keeps custody (no token approval to an external contract)
- Merchant has guaranteed pull rights (predictable revenue)
- User has a single dashboard showing all active subscriptions
- Cancel is always one tap — no "call to cancel" dark patterns

**Gas:** Merchant pays gas to pull (incentivized by receiving payment). Alternatively, paymaster sponsors pulls below a threshold.

### 4.3 Streaming Payments

For salaries, freelancer payments, or real-time billing:

```
Employer streams 5,000 USDC/month to Alice

1. Employer creates stream: {to: alice, rate: 5000e6/month, token: USDC}
2. StreamExecutor module tracks accrued balance
3. Alice (or anyone) can call withdraw() at any time
4. Withdraws accrued amount up to current timestamp
5. Employer can cancel — remaining unstreamed funds return
```

Built on proven Sablier/Superfluid patterns but as an **ERC-7579 module** — no external protocol dependency.

### 4.4 Request-to-Pay (x402 Integration)

**x402** enables HTTP-native payments: a server responds with `402 Payment Required` and a price header; the client pays and retries.

SovPay integrates x402 as a first-class payment flow:

```
Agent requests API endpoint → 402 response
  ├── Header: X-Payment-Amount: 0.001 USDC
  ├── Header: X-Payment-Address: 0xMerchant
  └── Header: X-Payment-Network: base

SovPay client (or autonomous agent):
1. Reads 402 headers
2. Validates amount against spending policy
3. Signs ERC-3009 authorization
4. Retries request with X-Payment-Proof header
5. Server verifies payment, serves content
```

**For AI agents:** A SovPay account with a `SessionKeyValidator` can operate autonomously — agent holds a session key with scoped spending limits. Pay-per-request without human approval for each call.

### 4.5 Batch Payments

For payroll, airdrops, or splitting bills:

```
BatchExecutor processes N transfers in a single UserOperation:
- transfers: [{to, amount, token}, ...]
- Single passkey signature
- Single gas payment
- Atomic: all succeed or all revert
```

---

## 5. Merchant Integration

### 5.1 Merchant Account Structure

Merchants use the same SovPay smart account, with additional modules:

```
MerchantAccount (SovPayAccount + merchant modules)
├── PaymentReceiver module
│   ├── Accepts incoming payments
│   ├── Emits structured receipt events
│   └── Supports refund authorization
├── SettlementModule
│   ├── Instant settlement (default — funds arrive directly)
│   ├── Batched settlement (aggregate and sweep every N hours)
│   └── Auto-convert to fiat via off-ramp integration
└── DisputeModule
    ├── Escrow for disputed amounts
    └── Resolution hooks (arbitration, auto-resolve)
```

### 5.2 Payment Acceptance SDK

```typescript
// Merchant integration — 10 lines to accept payments
import { SovPay } from '@sovpay/merchant-sdk';

const sovpay = new SovPay({
  merchantId: '0xMerchantAddress',
  apiKey: 'sk_live_...',           // for webhooks only, not custody
  network: 'base',
});

// Generate payment request
const request = sovpay.createPaymentRequest({
  amount: '49.99',
  currency: 'USDC',
  reference: 'order_456',
  callbackUrl: 'https://shop.example/webhook',
});

// Returns: { qr: string, deepLink: string, requestId: string }

// Webhook fires on payment confirmation
sovpay.on('payment.confirmed', (event) => {
  // event.reference === 'order_456'
  // event.txHash, event.amount, event.payer
  fulfillOrder(event.reference);
});
```

### 5.3 Settlement Options

| Mode | Latency | How |
|------|---------|-----|
| **Instant** | ~2s (Base block time) | Payment goes directly to merchant address. Done. |
| **Batched** | Configurable (1h–24h) | Payments accumulate; swept to merchant on schedule. Lower gas per payment. |
| **Fiat off-ramp** | Minutes–hours | Auto-bridges to fiat via integrated off-ramp (Coinbase, Bridge, etc.) |

**Default is instant.** No T+2 settlement. No holds. Money arrives in seconds.

### 5.4 Dispute Resolution

A credible dispute mechanism is essential for merchant adoption and consumer trust.

```
┌──────────┐    dispute()     ┌──────────────┐
│  Buyer   │ ──────────────► │   Dispute     │
│          │                  │   Escrow      │
└──────────┘                  │   Contract    │
                              │               │
┌──────────┐   respond()      │  Holds funds  │
│ Merchant │ ──────────────► │  for up to    │
│          │                  │  30 days      │
└──────────┘                  └──────┬────────┘
                                     │
                              ┌──────▼────────┐
                              │  Resolution   │
                              │               │
                              │  1. Mutual    │
                              │  2. Arbitrator│
                              │  3. Timeout   │
                              └───────────────┘
```

**Flow:**
1. Buyer opens dispute within **configurable window** (default: 14 days) by calling `dispute(paymentId, reason)` on the Payment Registry
2. Disputed amount is **frozen** in merchant's account (DisputeModule hook prevents withdrawal)
3. Merchant responds with evidence (off-chain, hash on-chain)
4. **Resolution paths:**
   - **Mutual:** Merchant issues refund → dispute closed
   - **Arbitration:** Pre-agreed arbitrator (Kleros, UMA, or protocol DAO) reviews evidence → decides fund allocation
   - **Timeout:** If merchant doesn't respond in 7 days → auto-refund to buyer
5. Funds released per resolution outcome

**Key constraints:**
- Only applies to payments made through SovPay payment requests (not raw transfers)
- Dispute window is merchant-configurable (0 = no disputes, max 90 days)
- Arbitration fee split 50/50 unless arbitrator decides otherwise

### 5.5 Refund Handling

```solidity
// Merchant initiates refund — no buyer action needed
merchant.refund(paymentId, amount);  // partial or full

// Funds transfer from merchant → buyer
// Linked to original payment for accounting
// Receipt event emitted
```

- Refunds are always **push-based** (merchant sends to buyer)
- Linked to original payment ID for clean accounting
- Partial refunds supported

---

## 6. Gas & Fee Model

### 6.1 Paymaster Design

**Principle:** Users should never think about gas.

```
┌──────────────┐
│   Paymaster   │
│   Contract    │
│               │
│  Sponsors gas │
│  for valid    │
│  SovPay UOs   │
└───────┬───────┘
        │
        ├── Funded by: protocol treasury (early stage)
        ├── Funded by: merchants (for their customers)
        ├── Funded by: USDC deduction (user pays gas in USDC, not ETH)
        └── Funded by: protocol fees (self-sustaining)
```

**Paymaster tiers:**

| Tier | Who pays gas | When |
|------|-------------|------|
| **Sponsored** | Protocol / merchant | First N transactions, promotional, merchant-subsidized |
| **USDC-deducted** | User (in USDC) | Default — small USDC amount deducted alongside payment |
| **Self-pay** | User (in ETH) | Power users who prefer direct gas payment |

**USDC gas deduction** is the default UX: user sends 10 USDC, actually sends 10.003 USDC (0.003 covers gas). Paymaster fronts ETH gas, reimburses itself from the USDC deduction.

### 6.2 Protocol Fee Structure

| Fee type | Amount | Paid by | When |
|----------|--------|---------|------|
| **P2P transfer** | Free | — | Always |
| **P2M payment** | 0.1% (max $1) | Merchant | Per transaction |
| **Subscription pull** | 0.05% | Merchant | Per pull |
| **Dispute filing** | $1 flat | Disputant | Refunded if they win |
| **Account deployment** | Sponsored | Protocol | First-time only |

**Comparison to traditional payments:**

| | Credit Card | SovPay | Savings |
|---|---|---|---|
| Merchant fee | 2.5-3.5% | 0.1% | **96% reduction** |
| Settlement time | T+2 days | ~2 seconds | **Instant** |
| Chargeback risk | Yes (fraud liability) | Structured disputes | **Predictable** |
| International fees | 1-3% | 0% | **Free** |

### 6.3 Sustainability Model

```
Revenue sources:
├── Merchant transaction fees (0.1%)          ← primary
├── Paymaster spread (gas cost + small margin) ← covers infra
├── Premium modules (advanced analytics, etc.) ← optional
└── B2B API access (high-volume merchants)     ← enterprise
```

At **$1B monthly volume** (Stripe processes ~$1T/year):
- 0.1% fee = $1M/month revenue
- Base L2 gas costs ~$50K/month
- **Sustainable without a token**

---

## 7. Security Model

### 7.1 Spending Limits

The `SpendingLimitHook` module enforces configurable caps:

```
SpendingLimits {
    dailyLimit:    500 USDC     // resets every 24h
    weeklyLimit:   2000 USDC    // resets every 7d
    perTxLimit:    200 USDC     // single transaction cap
    monthlyLimit:  5000 USDC    // resets every 30d
}
```

- Limits are **per-token** and **per-signer**
- Session keys get their own (lower) limits
- Changing limits requires the primary passkey + a **24h timelock** (prevents stolen-device instant drain)

### 7.2 Transaction Signing Policies

| Policy | Description |
|--------|-------------|
| **Single-sig** | Default. One passkey signature. |
| **Multi-sig** | High-value transfers require 2-of-N device signatures. |
| **Session keys** | Scoped, time-limited keys for apps/agents. Define: max amount, allowed recipients, expiry. |
| **Whitelist-only mode** | Only send to pre-approved addresses. Good for savings accounts. |
| **Time-delayed** | Transfers above threshold require N-hour delay (cancel window). |

### 7.3 Fraud Detection

Off-chain `FraudDetectionHook` integration:

1. Pre-transaction: check recipient against known scam databases
2. Velocity check: unusual spending patterns trigger soft block (require re-auth)
3. Geo-anomaly: signing from a new device/location flags for confirmation
4. All checks are **advisory** — user can always override (self-custody principle)

### 7.4 Account Freezing / Recovery

- **Self-freeze:** User can freeze account instantly from any registered device. Requires passkey + 24h wait to unfreeze.
- **Guardian freeze:** Social recovery guardians (2-of-5) can freeze the account if user reports compromise.
- **No protocol freeze:** SovPay protocol **cannot** freeze user accounts. Ever. Non-negotiable.

---

## 8. Multi-Chain Strategy

### 8.1 Base as Primary

**Why Base:**
- Low gas (~$0.001-0.01 per tx)
- RIP-7212 support (native passkey verification)
- Coinbase ecosystem (on/off-ramp, institutional trust)
- Growing DeFi and stablecoin liquidity
- ERC-4337 native support

**Base is home.** Every feature ships here first.

### 8.2 Expansion Plan

| Phase | Chains | Rationale |
|-------|--------|-----------|
| Launch | Base | Prove the model |
| V1.1 | + Optimism, Arbitrum | EVM equivalent, easy deployment |
| V1.5 | + Ethereum mainnet | High-value transactions, DeFi composability |
| V2 | + Polygon, Avalanche | Geographic and use-case expansion |
| V3 | + non-EVM (Solana?) | If demand warrants |

### 8.3 Unified Balance Abstraction

Users should see **one balance**, not per-chain balances.

```
User sees:  $1,247.50 USDC

Actual breakdown (hidden):
  Base:      $800.00
  Optimism:  $300.00
  Arbitrum:  $147.50
```

**Implementation:**
1. **Read path:** Client aggregates balances across chains via RPC
2. **Spend path:** When user pays, the client routes from the chain with sufficient balance (prefer primary chain)
3. **Rebalance:** Automated background rebalancing via bridges (user-configurable threshold)
4. **Cross-chain payment:** If paying on Chain A but funds are on Chain B → atomic bridge + pay via intent relay

Uses **ERC-7683 cross-chain intents** for trustless cross-chain operations.

---

## 9. Token Economics

### Decision: No Protocol Token

**SovPay does not need a token.**

Rationale:
- Protocol revenue (merchant fees) is sufficient for sustainability
- A token adds regulatory risk (securities classification)
- Token-gated governance attracts speculators, not users
- Users and merchants want **stability**, not token price exposure
- Every successful payments company (Stripe, Square, PayPal) runs without a protocol token

### How It Sustains

| Revenue stream | Scale driver |
|----------------|-------------|
| 0.1% merchant fee | Transaction volume |
| Paymaster margin | Transaction count |
| Premium features | Merchant subscriptions |
| Enterprise API | B2B volume |

### Governance

- **Early stage:** Core team makes protocol decisions
- **Mature stage:** On-chain governance via **reputation-weighted voting** (based on protocol usage, not token holdings)
- Merchants and active users get governance weight proportional to their protocol activity
- No plutocracy — usage-based, not wealth-based

---

## 10. Roadmap

### MVP (Month 1-3)

**Goal:** Working self-custody payments on Base

- [ ] SovPayAccount factory (ERC-7579 + passkey validator)
- [ ] One-time P2P transfers (USDC on Base)
- [ ] Paymaster with USDC gas deduction
- [ ] Basic web app (create account, send/receive)
- [ ] ERC-3009 gasless transfers
- [ ] Account recovery via multi-device passkeys

**Success metric:** 100 accounts, 1,000 transactions

### V1 Launch (Month 4-6)

**Goal:** Merchant-ready payment protocol

- [ ] Merchant SDK (payment requests, webhooks, QR codes)
- [ ] SubscriptionExecutor module (recurring payments)
- [ ] Spending limits and session keys
- [ ] Dispute resolution (basic: mutual + timeout)
- [ ] Mobile-optimized PWA
- [ ] Social recovery (guardian-based)
- [ ] Payment history and receipt management

**Success metric:** 10 merchants, 10,000 transactions, $100K monthly volume

### V1.5 (Month 7-9)

- [ ] Streaming payments
- [ ] x402 integration (HTTP-native payments)
- [ ] Batch payments
- [ ] Multi-chain expansion (Optimism, Arbitrum)
- [ ] Unified balance abstraction
- [ ] Advanced fraud detection
- [ ] Fiat off-ramp integration

### V2 (Month 10-12+)

- [ ] Full arbitration system (Kleros/UMA integration)
- [ ] AI agent payment flows (autonomous session keys)
- [ ] Merchant analytics dashboard
- [ ] NFC tap-to-pay (mobile native app)
- [ ] White-label SDK for fintech integrations
- [ ] Ethereum mainnet deployment
- [ ] Reputation-based governance launch

---

## 11. Appendices

### A. ERC Proposal: Subscription Payments (Draft)

**Title:** ERC-XXXX: On-Chain Subscription Payments via Smart Account Modules

**Abstract:** A standard interface for recurring payment agreements executed through ERC-7579 smart account modules. Merchants can pull pre-authorized amounts at defined intervals. Users maintain full custody and can cancel at any time.

**Key interface:**

```solidity
interface ISubscriptionModule {
    function createSubscription(
        address token,
        address merchant,
        uint256 amount,
        uint256 period,
        uint256 maxPeriods
    ) external returns (bytes32 subscriptionId);

    function executeSubscription(bytes32 subscriptionId) external;
    function cancelSubscription(bytes32 subscriptionId) external;

    function getSubscription(bytes32 subscriptionId)
        external view returns (Subscription memory);

    event SubscriptionCreated(bytes32 indexed id, address indexed user, address indexed merchant);
    event SubscriptionExecuted(bytes32 indexed id, uint256 period);
    event SubscriptionCancelled(bytes32 indexed id);
}
```

### B. x402 Payment Header Specification

```
HTTP/1.1 402 Payment Required
X-Payment-Version: 1
X-Payment-Network: base
X-Payment-Token: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  (USDC on Base)
X-Payment-Amount: 1000000  (1 USDC, 6 decimals)
X-Payment-Recipient: 0xMerchantAddress
X-Payment-Memo: "API access - 1 request"
X-Payment-Expiry: 1707350400

--- Client pays, then retries with: ---

X-Payment-Proof: 0x<ERC-3009 signed authorization>
X-Payment-Tx: 0x<transaction hash, if submitted>
```

### C. Competitive Analysis

| Feature | Banks | Venmo/CashApp | Crypto Wallets | **SovPay** |
|---------|-------|---------------|----------------|-----------|
| Self-custody | ❌ | ❌ | ✅ | ✅ |
| No seed phrase | ✅ | ✅ | ❌ | ✅ |
| Recurring payments | ✅ | ❌ | ❌ | ✅ |
| Instant settlement | ❌ | ❌* | ✅ | ✅ |
| Dispute resolution | ✅ | ✅ | ❌ | ✅ |
| Merchant tools | ✅ | ✅ | ❌ | ✅ |
| Sub-1% fees | ❌ | ✅** | ✅ | ✅ |
| Programmable | ❌ | ❌ | ✅ | ✅ |
| Open/permissionless | ❌ | ❌ | ✅ | ✅ |
| AI agent compatible | ❌ | ❌ | ⚠️ | ✅ |

*Venmo: instant to bank costs extra
**CashApp: P2P free, merchant 2.6%+$0.10

### D. Key Dependencies

| Dependency | Status | Risk |
|------------|--------|------|
| ERC-4337 (Account Abstraction) | Live, mature | Low |
| ERC-7579 (Modular Accounts) | Live, growing adoption | Low |
| RIP-7212 (P-256 precompile) | Live on Base | Low |
| ERC-3009 (Transfer with Auth) | Live (USDC supports it) | Low |
| Base L2 | Live, Coinbase-backed | Low |
| ERC-7683 (Cross-chain intents) | Early, evolving | Medium |
| Kleros/UMA (Arbitration) | Live but niche | Medium |

---

*SovPay: Sovereign payments for a post-bank world.*
