# Ethereum Payment Infrastructure Research Report
**Date:** 2026-02-07 | **Goal:** Outcompete banks with self-custody payments

---

## 1. Smart Account Standards

### ERC-4337 (Account Abstraction via Alt Mempool) — MATURE
- **Status:** Production-ready, widely deployed since 2023
- **Architecture:** UserOperations → Bundlers → EntryPoint contract → Smart Account execution
- **Key components:**
  - **Bundlers:** Collect UserOps, submit to EntryPoint (Pimlico, Stackup, Alchemy, Biconomy)
  - **Paymasters:** Sponsor gas for users — can pay in ERC-20 tokens instead of ETH
  - **EntryPoint v0.7:** Latest version, improved gas efficiency
- **Limitation:** Requires deploying a new smart contract wallet per user (can't upgrade existing EOAs)

### EIP-7702 (Pectra Upgrade, May 7 2025) — GAME CHANGER
- **Status:** LIVE on Ethereum mainnet + all major L2s
- **What it does:** Allows any EOA to temporarily execute smart contract code via new tx type `0x04`
- **Why it matters for payments:**
  - Existing MetaMask/EOA users get smart account features WITHOUT migrating
  - Batch transactions (approve + swap in one tx)
  - Gas sponsorship for existing wallets
  - Circle explicitly building gasless USDC flows on top of 7702
- **Relationship to 4337:** Complementary. 7702 upgrades EOAs; 4337 is for purpose-built smart accounts. Both coexist.

### ERC-7579 (Minimal Modular Smart Accounts) — STANDARD
- **Status:** Adopted by Safe, thirdweb, Rhinestone, Biconomy
- **What it does:** Defines minimal interfaces for modular account plugins (validators, executors, hooks, fallbacks)
- **Why it matters:** Write a payment module ONCE, deploy to ANY 7579-compatible wallet
- **Module types:** Validators (auth), Executors (actions), Hooks (pre/post checks), Fallbacks
- **Key insight:** This is the "app store" model for smart accounts

### ERC-6900 (Modular Accounts by Alchemy) — COMPETITOR TO 7579
- **Status:** Less adoption than 7579; more opinionated about storage allocation
- **Difference:** 6900 defines storage patterns; 7579 only defines interfaces (more minimal)
- **Recommendation:** Build on **ERC-7579** — broader ecosystem support

### Newer Standards
- **ERC-7715:** Permission system for smart accounts (session keys, spending limits)
- **ERC-7710:** Delegation framework
- **ERC-7484:** Module registry for 7579 modules

---

## 2. Passkey/WebAuthn Integration

### RIP-7212 (secp256r1 Precompile)
- **Status:** Deployed as precompile on Base, Optimism, Arbitrum, Polygon, zkSync, many L2s
- **What it does:** Native P256 signature verification at ~3,450 gas (vs 180-300k gas in Solidity)
- **Why it matters:** Makes passkey verification economically viable on-chain

### How Passkeys Work with Smart Accounts
1. User creates passkey via Face ID / Touch ID / Windows Hello
2. Private key stored in device Secure Enclave (never leaves hardware)
3. Signs challenges using secp256r1 (P256 curve)
4. Smart account's `validateUserOp` verifies via RIP-7212 precompile
5. No seed phrase, no browser extension — just biometrics

### Current Implementations

| Wallet | Passkey Support | Chain | Notes |
|--------|----------------|-------|-------|
| **Coinbase Smart Wallet** | ✅ Full | Base, Ethereum | Best UX, open-source, secp256r1 native |
| **Safe** | ✅ Via modules | Multi-chain | ERC-7579 passkey module |
| **Clave** | ✅ Native | zkSync | Built specifically for passkey-first |
| **Obvious Wallet** | ✅ | Multi-chain | Consumer-focused |

### Security Model vs Seed Phrases
- **Passkeys:** Hardware-bound, biometric-gated, phishing-resistant, no backup phrase to lose
- **Risk:** Device loss = account loss (mitigated by multi-device sync via iCloud/Google Password Manager)
- **Recovery:** Social recovery modules, guardian keys, or secondary passkey on another device
- **Verdict:** Dramatically better UX with comparable security when recovery is designed well

---

## 3. L2 Landscape for Payments

### Comparison Matrix

| L2 | Avg Fee | TPS | Finality | Native AA | Ecosystem | Payment Suitability |
|----|---------|-----|----------|-----------|-----------|-------------------|
| **Base** | ~$0.01 | 1000+ | ~2s soft | Via 4337/7702 | Coinbase ecosystem, huge retail | ⭐⭐⭐⭐⭐ |
| **Arbitrum** | ~$0.20 | 400 | ~250ms soft, 7d challenge | Via 4337/7702 | Largest DeFi TVL | ⭐⭐⭐ |
| **Optimism** | ~$0.15 | 300 | ~2s soft | Via 4337/7702 | Superchain ecosystem | ⭐⭐⭐ |
| **zkSync Era** | ~$0.10 | 500+ | ~1hr ZK proof | ✅ Native AA | Growing | ⭐⭐⭐⭐ |
| **Polygon PoS** | ~$0.05 | 700 | ~2s | Via 4337 | Large user base | ⭐⭐⭐ |

### Key Insights
- **Base is the clear winner for payments:** Cheapest fees, Coinbase on/off-ramp integration, massive retail user base, USDC native support
- **zkSync is the technical winner:** Native AA means no bundler dependency, all accounts are smart contracts by default, ZK proofs for strong finality
- **2026 trend:** Enterprise rollups proliferating (Kraken's INK, Uniswap's UniChain, Sony's Soneium) — all on OP Stack
- **Post-Dencun/4844:** L2 fees dropped 90%+ due to blob transactions — payments are now economically viable

### Recommendation
**Primary: Base** (Coinbase ecosystem, cheapest, most retail users)  
**Secondary: zkSync Era** (native AA, ZK finality, technical superiority)  
**Watch: OP Stack custom rollup** (if you want your own L2 with payment-optimized parameters)

---

## 4. Payment-Specific ERCs & Protocols

### Gasless Token Operations

| Standard | Function | USDC Support | Notes |
|----------|----------|-------------|-------|
| **ERC-2612** (permit) | Gasless approval via signature | ✅ | User signs, relayer submits |
| **ERC-3009** (transferWithAuthorization) | Gasless transfer via signature | ✅ (USDC v2 native) | One-time authorized transfer, nonce-based |

- **ERC-3009 is critical:** USDC implements it natively — enables "sign to pay" without ever holding ETH
- **Combined with paymaster:** User signs transfer → paymaster pays gas → fee deducted from transfer amount

### Streaming & Recurring Payments

| Protocol | Model | Status | Use Case |
|----------|-------|--------|----------|
| **Superfluid** | Per-second streaming | Live, multi-chain | Salaries, subscriptions |
| **Sablier** | Time-locked vesting streams | Live | Token vesting, payments |

- **Superfluid:** Requires wrapping tokens into "Super Tokens" (1:1 wrapped ERC-20) — adds friction
- **No standard ERC for subscriptions yet** — this is a gap

### x402 Protocol (Coinbase, May 2025)
- **What:** HTTP-native payment standard using `402 Payment Required` status code
- **How:** Server returns 402 → client signs USDC payment → includes in HTTP header → server verifies & serves
- **Supports:** ERC-3009 `transferWithAuthorization` under the hood
- **Massive implications:** Payments become part of the HTTP protocol itself
- **Use case:** API monetization, machine-to-machine payments, AI agent commerce

---

## 5. Competitor Analysis

### Gnosis Pay
- **What:** Self-custodial Visa debit card on Gnosis Chain
- **Strengths:** True self-custody, Visa network, EURe stablecoin, zero spending fees, up to 5% GNO cashback
- **Weaknesses:** Gnosis Chain only (low liquidity), limited countries (EU focus), slow settlement (traditional card rails), requires KYC, dependent on Monavate/Visa partnership
- **Architecture:** Safe smart account → Gnosis Chain → Visa settlement
- **Verdict:** Best current "spend crypto IRL" product, but still wraps legacy card rails

### Coinbase Smart Wallet
- **What:** Passkey-based smart wallet on Base
- **Strengths:** Best passkey UX, massive distribution (Coinbase app), gasless onboarding, open-source
- **Weaknesses:** Base-centric, Coinbase dependency, no direct merchant integration (still needs card rails for IRL)
- **Architecture:** ERC-4337 + secp256r1 passkeys + Base L2
- **Verdict:** Best smart wallet UX, but custodial exchange still handles fiat

### Safe (formerly Gnosis Safe)
- **What:** Multi-sig smart account platform, now modular via ERC-7579
- **Strengths:** Battle-tested ($100B+ secured), modular, multi-chain, institutional trust
- **Weaknesses:** Multi-sig UX is complex for consumers, gas-heavy on L1, designed for treasury not payments
- **Architecture:** Proxy pattern, modular 7579 modules, extensive ecosystem
- **Verdict:** Best infrastructure for building ON, not best consumer product

### Argent
- **What:** Smart wallet focused on Starknet (pivoted from Ethereum L1)
- **Strengths:** Pioneered social recovery, smart account UX, Starknet's native AA
- **Weaknesses:** Starknet is niche, limited DeFi/stablecoin ecosystem, small user base
- **Verdict:** Good UX ideas, wrong chain for payments

---

## 6. Protocol Design Recommendations

### Recommended Tech Stack

```
┌─────────────────────────────────────────────┐
│              USER LAYER                       │
│  Passkey (Face ID/Touch ID) via WebAuthn     │
│  Progressive Web App (no app store needed)   │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│            ACCOUNT LAYER                      │
│  ERC-4337 Smart Account (ERC-7579 modular)   │
│  + EIP-7702 for EOA upgrades                 │
│  Passkey validator module (RIP-7212)         │
│  Spending limits module                       │
│  Recovery module (social/guardian)            │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│           PAYMENT LAYER                       │
│  ERC-3009 transferWithAuthorization (USDC)   │
│  Paymaster (gas sponsored in USDC)           │
│  Streaming module (for subscriptions)        │
│  x402 compatible (HTTP-native payments)      │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│          SETTLEMENT LAYER                     │
│  Primary: Base L2                             │
│  Secondary: zkSync Era                        │
│  Bridge: Cross-chain via CCIP or Across      │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│         FIAT INTERFACE LAYER                  │
│  On-ramp: MoonPay, Transak, Coinbase Pay     │
│  Off-ramp: Gnosis Pay style Visa card        │
│  Merchant: Direct stablecoin acceptance       │
└─────────────────────────────────────────────┘
```

### Key Design Decisions

**1. Multi-chain vs Single L2**
- **Start on Base** (largest retail user base, cheapest fees, Coinbase ecosystem)
- **Expand to zkSync** for markets wanting ZK-proof finality
- **Use CCIP/Across** for cross-chain transfers when needed
- Don't try to be everywhere day one

**2. Stablecoin Strategy**
- **USDC first:** Best ERC-3009 support, Circle's regulatory compliance, Coinbase integration
- **USDT second:** Largest market cap, but weaker programmability
- **DAI/USDS:** For DeFi-native users wanting decentralized stables
- **EURe/GBPe:** For non-USD markets (Gnosis Pay model)

**3. Fiat On/Off Ramps**
- **On-ramp:** Integrate MoonPay/Transak SDKs (path of least resistance)
- **Off-ramp:** Partner with card issuer (like Gnosis did with Monavate) for Visa/Mastercard
- **Long-term:** Direct merchant integration via QR code / NFC (skip card networks entirely)

**4. Merchant Integration**
- **Phase 1:** Visa card bridge (works everywhere today)
- **Phase 2:** Payment links / QR codes for crypto-native merchants
- **Phase 3:** POS SDK for direct stablecoin acceptance (like Square but for USDC)
- **x402 integration:** For online/API payments natively

**5. Dispute Resolution**
- This is the **hardest unsolved problem** in crypto payments
- Options: Escrow contracts with time-locked releases, DAO arbitration (Kleros), or hybrid with traditional dispute processes via card network
- **Recommendation:** Build an escrow module (ERC-7579) with configurable dispute windows per merchant

---

## 7. Gaps in Existing Solutions

1. **No unified subscription standard** — Superfluid requires wrapped tokens, no simple "recurring pull payment" ERC exists
2. **No direct merchant settlement** — Everyone still routes through Visa/Mastercard for IRL spending
3. **Cross-chain UX is broken** — Users shouldn't need to know what chain they're on
4. **Recovery UX is terrible** — Social recovery exists but no product has made it seamless
5. **No dispute resolution** — Crypto payments are final; no chargeback equivalent exists
6. **Paymaster economics unclear** — Who pays for gas sponsorship at scale? Sustainable business models needed
7. **KYC/compliance gap** — Self-custody payments need compliant identity without centralized KYC databases

## 8. Unique Differentiation Angles

1. **"Invisible blockchain" payments** — User sees USD amounts, taps Face ID, done. No wallets, no addresses, no gas. Powered by passkeys + paymasters + Base under the hood.

2. **Subscription engine** — Build the missing recurring payment primitive as an ERC-7579 module. Merchants install once, works across all compatible wallets.

3. **x402 native** — First wallet/protocol designed for HTTP-native payments. AI agents and APIs can pay your users and vice versa.

4. **Programmable spending rules** — Parents set limits for kids, companies set policies for employees, users set daily caps. All enforced on-chain via smart account modules.

5. **Merchant-side self-custody** — Not just user self-custody. Merchants also hold funds in smart accounts with auto-sweep to yield, instant settlement, no payment processor middleman.

6. **Escrow-based dispute resolution** — First-mover on making crypto payments reversible (with consent) via time-locked escrow modules.

7. **Chain-abstracted** — User deposits USDC on any chain; protocol handles bridging. One balance, spend anywhere.

---

## Summary: Why This Can Outcompete Banks

| Feature | Traditional Banks | This Protocol |
|---------|------------------|---------------|
| Settlement time | 1-3 business days | 2 seconds |
| International fees | 1-3% + FX markup | ~$0.01 flat |
| Account opening | Days + paperwork | 10 seconds (passkey) |
| Self-custody | ❌ Bank holds funds | ✅ User controls keys |
| Programmable | ❌ | ✅ Smart account modules |
| 24/7 | ❌ Business hours | ✅ Always on |
| Merchant fees | 2-3% | <0.5% possible |
| Chargebacks | ✅ (banks decide) | ✅ (escrow, user-controlled) |
| Interest on balance | 0.01% | 4-8% (DeFi yield) |

The tech stack is ready. The missing piece is **product execution** — making it feel like Venmo/Apple Pay while being fully self-custodial underneath.
