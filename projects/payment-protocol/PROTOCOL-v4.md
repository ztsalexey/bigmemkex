# Pay Protocol v4

> **One primitive: a signed intent to move money.**
> Everything else — subscriptions, disputes, agent payments — emerges from that.

*The definitive specification. February 2026.*

---

## Protocol Essence

A payment is a signed message: *"I authorize X tokens to Y under conditions Z."* Make that message expressive enough and you don't need separate systems for subscriptions, escrows, refunds, or agent payments. You need **one message type** and **one smart account**.

```
User (smart account + passkey)
  → signs Payment Intent
    → Relayer submits on-chain
      → Done.
```

**What's in the protocol:** Accounts, Intents, Conditions.
**What's NOT:** Merchant tools, compliance, analytics, dispute UX. Those are applications.

**Three contracts:** `AccountFactory`, `IntentExecutor`, `ConditionRegistry`.

**Tagline:** *Sign. Send. Settled.*

---

## 1. Accounts

An ERC-7579 smart account on Base. Deterministic addresses via CREATE2.

### Authentication

Authentication is a module concern, not a protocol concern:

| Default | Alternatives |
|---------|-------------|
| Passkey (WebAuthn/P-256) | Hardware key, session key, multisig, social login |

### Recovery

Also a module. Default: multi-device passkeys (iCloud/Google sync). Optional: social recovery (3-of-5 guardians, 24h timelock). The protocol doesn't prescribe recovery — it requires a valid signer.

### Deployment

Account deployment is lazy — triggered on first transaction. Paymaster sponsors gas (~$0.01 on Base). User never sees it.

**Address is known before deployment** (CREATE2), so users can receive funds before their account exists on-chain.

---

## 2. The Intent

The core primitive:

```solidity
struct Intent {
    address token;       // ERC-20 token (USDC by default)
    address to;          // recipient
    uint256 amount;      // amount in token's smallest unit
    bytes32 condition;   // keccak256(abi.encode(conditionAddress, conditionParams)) or 0x0
    uint256 nonce;       // replay protection (sequential per-account)
    uint256 deadline;    // unix timestamp — intent expires after this
    bytes signature;     // EIP-1271 signature from account
}
```

### Pattern Mapping

| Pattern | condition | deadline | Notes |
|---------|-----------|----------|-------|
| One-time payment | `0x0` | now + 5min | Simplest case |
| Subscription | `hash(RecurringCondition, period, maxPulls, merchant)` | far future | Merchant calls `pull()` |
| Agent session | `hash(SessionCondition, perTxLimit, dailyLimit, allowlist)` | session end | Session key signs |
| Escrow | `hash(EscrowCondition, releaseHash, timeout, refundTo)` | timeout | Release or auto-refund |
| Streaming | `hash(StreamCondition, rate, startTime)` | stream end | Continuous pro-rata release |
| Split payment | `hash(SplitCondition, recipients[], shares[])` | now + 5min | Single intent, multiple payouts |

### Condition Interface

```solidity
interface ICondition {
    /// @notice Evaluate whether an intent may execute
    /// @param intent The payment intent
    /// @param proof Arbitrary data (oracle sigs, merkle proofs, timestamps)
    /// @return ok Whether conditions are met
    function check(
        Intent calldata intent,
        bytes calldata proof
    ) external view returns (bool ok);

    /// @notice Called AFTER successful execution for state updates
    /// @dev e.g., incrementing pull count for RecurringCondition
    function onExecute(Intent calldata intent) external;
}
```

**`check()` is a pure view call** — no state mutation, predictable gas, safe to simulate. State changes happen in `onExecute()`, called only after successful transfer.

### Condition Composition

Conditions compose via a `CompositeCondition` wrapper:

```solidity
struct Composite {
    address[] conditions;   // ordered list
    bytes[] proofs;         // one proof per condition
    Logic logic;            // AND or OR
}

enum Logic { AND, OR }
```

- **AND**: all conditions must pass. Use case: "subscription AND spending limit."
- **OR**: any condition passing is sufficient. Use case: "owner signature OR guardian after timelock."
- **Nesting**: a CompositeCondition can reference another CompositeCondition. Max depth: 4 (gas bounded).

Gas cost: each `check()` is a `staticcall` (~2,600 base + condition logic). Four conditions ≈ 15,000 gas total. Negligible on Base (~$0.0001).

### Core Conditions (Audited, Ship with Protocol)

| Condition | Purpose | State |
|-----------|---------|-------|
| `RecurringCondition` | Enforces pull period, max count, authorized puller | Tracks pull count + last pull time |
| `SessionCondition` | Per-tx limit, daily limit, recipient allowlist, expiry | Tracks daily spend |
| `TimelockCondition` | Delay execution + cancel window | Tracks queued intents |
| `EscrowCondition` | Release on proof, auto-refund on timeout | Tracks escrow state |

**Anyone can deploy new conditions.** The `ConditionRegistry` maps `bytes32 → address` and is append-only (conditions cannot be removed or replaced, only deprecated via a flag).

---

## 3. Execution

```
User signs Intent (off-chain, gasless)
  → Relayer validates + wraps as UserOp
    → Bundler submits to EntryPoint (ERC-4337)
      → Account validates signature
        → IntentExecutor checks condition
          → ERC-20 transfer
            → onExecute() callback
              → Event emitted
```

### Gas Abstraction

User pays in USDC. The flow:

1. User signs intent for `amount` USDC
2. Relayer estimates gas cost in ETH
3. Paymaster converts to USDC equivalent (Chainlink price feed, 1% slippage buffer)
4. Paymaster pays ETH to bundler
5. USDC gas fee (~$0.003–$0.01) is deducted from transfer or paid separately

**The relayer is not the protocol.** Anyone can run one. The reference relayer does sanctions screening (OFAC) because it operates under US law. The protocol contracts are permissionless.

### Transaction Finality

Base block time: 2 seconds. Finality: ~2 seconds (optimistic). For high-value payments (>$10,000), applications SHOULD wait for L1 batch posting (~10 minutes) before treating as final.

### Failed Transactions

If a transaction reverts:
- **Condition check fails**: no gas consumed by user (relayer eats the cost, should simulate first)
- **Insufficient balance**: relayer simulation catches this pre-submission
- **Contract bug**: relayer is reimbursed via paymaster; user is not charged

Relayers are incentivized to simulate before submitting. Bad relayers eat failed gas. Good relayers never submit failing txs.

---

## 4. Fees

| Action | Fee | Paid by | Notes |
|--------|-----|---------|-------|
| P2P transfer | Free | — | Public good |
| Merchant payment | 0.3% (cap $2) | Merchant (deducted from received amount) | Competitive with Stripe's 2.9% |
| Recurring pull | 0.1% | Merchant | Lower because less risk |
| Agent/x402 payment | 0.1% | Service provider | Micro-payments need low fees |
| Gas | ~$0.003–$0.01 | Sender (in USDC) | Invisible, deducted automatically |

### Revenue Math

- Breakeven at ~$80M monthly volume (assuming 80% merchant, 20% P2P)
- $500M monthly volume → ~$1.2M monthly revenue
- No token. Revenue = protocol fees. Simple.

### Fee Immutability

Fees are set in the `IntentExecutor` contract. Changing fees requires a governance timelock (7 days). Fee caps are hardcoded:
- Merchant fee: max 1%
- Recurring fee: max 0.5%
- P2P: permanently free (hardcoded 0)

This is a credible commitment: merchants integrate knowing fees can't spike.

---

## 5. Security

### Layer 1: Spending Limits

Per-token, per-day limits enforced at the account level. Default: $500/day USDC.

- Increasing limits: 24-hour timelock (announced on-chain, can be cancelled)
- Decreasing limits: instant
- This IS fraud protection. A compromised key can drain at most one day's limit.

### Layer 2: Self-Freeze

Any authorized signer can freeze the account instantly. Unfreeze requires 24h delay. No one — not us, not anyone — can override a freeze.

### Layer 3: Intent Expiry

Every intent has a deadline. No permanent authorizations exist. Subscriptions have deadlines too (just far-future ones, cancellable anytime by revoking the condition).

### Layer 4: Condition Sandboxing

Conditions execute via `staticcall` — they **cannot** modify state during `check()`. This means:
- A buggy condition can return wrong results but cannot steal funds
- A malicious condition can block payments (DoS) but cannot redirect them
- `onExecute()` runs in the IntentExecutor's context with strict checks

### ConditionRegistry Compromise

The registry is append-only and owned by a multisig (initially team, transitioning to governance). Compromise scenario:

- **Attacker adds malicious condition**: No impact unless users explicitly reference it in their intents. Existing intents are unaffected.
- **Attacker deprecates a condition**: Deprecated conditions still execute — the flag is informational for UIs only.
- **Mitigation**: Registry ownership transfers to a timelock + multisig. New conditions have a 48h activation delay.

### Buggy Conditions

If a condition has a bug:
1. It cannot steal funds (staticcall sandboxing)
2. It can incorrectly approve/deny payments
3. Fix: deploy corrected condition at new address, users update their intents
4. Emergency: account owner can always send unconditional intents (`condition = 0x0`)

### MEV & Front-Running Protection

- **Private mempool**: Reference relayer uses Flashbots Protect on L1 batch submissions
- **Intent-based architecture**: Intents specify exact amounts and recipients — there's nothing to sandwich
- **Deadline enforcement**: Tight deadlines (5 min for one-time) prevent stale intent exploitation
- **Nonce sequencing**: Sequential nonces prevent replay and reordering

### Base L2 Risk

If Base goes down:
- **Short outage (<1h)**: Intents queue in relayer, submit when Base resumes. Deadlines may expire — user re-signs.
- **Long outage**: Users can force-include transactions via L1 (Optimism's deposit flow). ~10 minute delay.
- **Permanent failure**: Account state can be reconstructed on any OP Stack chain. Migration path: redeploy factories on Optimism mainnet.

---

## 6. UX: What Users Actually See

### Zero to First Payment (< 60 seconds)

```
1. Open pay.new in mobile browser                          [2 sec]
2. "Create account" → Touch ID / Face ID (passkey)         [3 sec]
3. Account created. Show address + "Add USDC" link         [instant]
4. Friend sends you $10 USDC (or buy via onramp partner)   [varies]
5. Tap "Send" → paste address or scan QR → amount → confirm [10 sec]
6. "Sent! ✓" — shows tx hash link                          [2 sec]
```

No seed phrases. No gas tokens. No "approve" transactions. No browser extensions.

### Paying a Merchant (QR Code)

```
1. Merchant shows QR code (encodes: amount, recipient, ref, callback URL)
2. User scans → app shows "Pay $4.50 to CoffeeShop?"
3. Touch ID → signed → submitted → "Paid ✓"
4. Merchant gets webhook callback within 3 seconds
```

### Receiving a Payment

Notification flow:
1. On-chain event: `IntentExecuted(from, to, amount, token, ref)`
2. Indexer picks up event within ~2 seconds
3. Push notification via FCM/APNs (if user has app installed)
4. Email notification (if user registered email)
5. Webhook (if recipient is a merchant)

### Error States

| Error | User sees | Recovery |
|-------|-----------|----------|
| Insufficient balance | "Not enough USDC. You have $X, need $Y." | Show balance, link to add funds |
| Intent expired | "Payment timed out. Tap to retry." | One-tap re-sign |
| Condition failed | "Payment conditions not met." + human-readable reason | Depends on condition |
| Network congestion | "Confirming... taking longer than usual." | Auto-retry, user can cancel |
| Account frozen | "Account is frozen. Unfreeze takes 24h." | Show unfreeze button |

### Mobile-First

The reference app is a PWA (Progressive Web App):
- Installable on iOS/Android home screen
- Passkeys work natively in mobile browsers
- No app store approval needed for v1
- Native app (React Native) for v2 with push notifications, NFC

---

## 7. Developer Experience

### SDK Architecture

```
@pay/core          — Intent types, signing, encoding. Zero dependencies.
@pay/client        — Browser SDK. Passkey auth, relayer communication.
@pay/server        — Node.js SDK. Webhook verification, payment requests.
@pay/react         — React hooks: usePayAccount, usePayment, useSubscription.
@pay/contracts     — ABIs, addresses, TypeChain types.
```

### Type Safety (TypeScript-First)

```typescript
import { createIntent, type Intent, type Token } from '@pay/core';

// Fully typed — IDE autocomplete for everything
const intent: Intent = createIntent({
  token: Token.USDC,
  to: '0x...',
  amount: parseUnits('4.50', 6),  // USDC has 6 decimals
  condition: null,                 // unconditional
  deadline: Math.floor(Date.now() / 1000) + 300,  // 5 min
});
```

### Hello World: Accept a Payment (4 lines)

```typescript
import { Pay } from '@pay/server';

const pay = new Pay({ network: 'base', webhookSecret: process.env.PAY_SECRET });
const link = pay.createRequest({ amount: '4.50', token: 'USDC', ref: 'order_123' });
pay.on('settled', (e) => console.log(`Paid: ${e.ref}`));  // webhook listener
```

### Hello World: Agent Payment (x402)

```
GET /api/data
→ 402 Payment Required
  X-Pay-Amount: 0.001
  X-Pay-To: 0x...
  X-Pay-Token: USDC
  X-Pay-Network: base

→ Agent signs Intent with session key
→ Retries with header:
  X-Pay-Proof: <signed_intent_hex>

→ Server verifies on-chain → 200 OK + data
```

### Error Handling

```typescript
import { PayError, ErrorCode } from '@pay/core';

try {
  await pay.send(intent);
} catch (e) {
  if (e instanceof PayError) {
    switch (e.code) {
      case ErrorCode.INSUFFICIENT_BALANCE:
        // show balance + add funds CTA
      case ErrorCode.INTENT_EXPIRED:
        // re-sign with new deadline
      case ErrorCode.CONDITION_FAILED:
        // e.reason has human-readable explanation
      case ErrorCode.RELAYER_UNAVAILABLE:
        // retry with backoff or switch relayer
    }
  }
}
```

### Testing

```typescript
import { PayTestnet } from '@pay/core/testing';

// Spins up local Base fork with pre-deployed contracts
const testnet = await PayTestnet.create();
const alice = await testnet.createAccount({ balance: '1000' }); // 1000 USDC
const bob = await testnet.createAccount();

await alice.send(bob.address, '50');
expect(await bob.balance()).toBe('50');

// Time-travel for subscription testing
await testnet.advanceTime(30 * 24 * 60 * 60); // 30 days
await merchant.pull(alice.address);
```

---

## 8. Receipts & Accounting

### On-Chain Receipts

Every executed intent emits:

```solidity
event IntentExecuted(
    bytes32 indexed intentHash,
    address indexed from,
    address indexed to,
    address token,
    uint256 amount,
    bytes32 condition,
    bytes32 ref,        // merchant reference (order ID, invoice #)
    uint256 timestamp
);
```

This is the canonical receipt. The `intentHash` is the unique identifier. The event log is the proof.

### Export

The SDK provides:

```typescript
const history = await pay.history({
  account: '0x...',
  from: '2026-01-01',
  to: '2026-12-31',
  format: 'csv',  // or 'json', 'ofx'
});
```

Fields: date, counterparty, amount, token, USD equivalent (at time of tx), reference, tx hash. Sufficient for tax reporting in most jurisdictions.

---

## 9. Multi-Currency

### Launch

USDC on Base. That's it. One token, one chain. Simplicity > optionality.

### Phase 2

Add tokens via governance (each requires a Chainlink price feed for gas conversion):

| Token | Priority | Notes |
|-------|----------|-------|
| USDT | High | Market demand |
| DAI | Medium | Decentralization signal |
| EURC | Medium | Euro-denominated |
| ETH (wrapped) | Low | Volatile, but demanded |

Adding a token = registering it in the IntentExecutor's token allowlist. No contract upgrade needed.

### Cross-Chain (Phase 3)

ERC-7683 (cross-chain intents) when the standard matures. User signs intent on Base, filler executes on destination chain. The protocol doesn't bridge — it delegates to the cross-chain intent market.

---

## 10. Ship Plan

| Weeks | Milestone | Deliverables |
|-------|-----------|-------------|
| 1–4 | Foundation | AccountFactory, passkey auth module, IntentExecutor, P2P USDC transfers, paymaster, basic web app |
| 5–8 | Usable | Merchant SDK, payment links/QR, webhook notifications, mobile PWA, testnet deployment |
| 9–12 | Complete | RecurringCondition, SessionCondition, x402 reference implementation, mainnet launch |
| 13–16 | Growth | Dispute module, multi-token, advanced conditions, native mobile app |

**Success metric:** 500 accounts, 5,000 transactions, 3 merchant integrations in first 12 weeks on mainnet.

---

## 11. Competitive Position

| Wedge | Advantage |
|-------|-----------|
| AI agent payments (x402) | Only protocol with native session keys + HTTP 402 flow |
| Creator subscriptions | 0.1% vs Patreon's 5–12% |
| Cross-border freelancers | Instant, near-free, no bank account needed |
| Developer experience | 4 lines to accept a payment (vs Stripe's 40) |

---

## 12. Honest Limits

- Requires internet connectivity
- On-chain = public (no payment privacy without future ZK work)
- Stablecoins only — not fiat, not magic internet money volatility
- Base L2 = centralized sequencer (Optimism mainnet as fallback)
- Smart account UX is nascent — passkey support varies across devices
- No fiat offramp in protocol — relies on partner integrations

We'll improve these over time. We won't pretend we already have.

---

## 13. Name

**Pay Protocol** is the protocol layer. Generic on purpose — like "HTTP" or "SMTP." Protocols should describe what they do.

**Pay** (or `pay.new`) is the reference app. Clean, memorable, universal.

The SDK namespace is `@pay/`. The on-chain contracts are `Pay___` (PayAccountFactory, PayIntentExecutor, etc.).

If `pay.new` is unavailable: `paypro.to`, `getpay.co`, or `usepay.xyz` as alternatives. The domain is secondary to the developer namespace.

---

---

# Appendix A: Design Decisions

### Why one Intent struct instead of separate message types?

Separate structs (PaymentMessage, SubscriptionMessage, EscrowMessage) mean separate execution paths, separate audits, separate SDK surface area. One struct with a flexible `condition` field gives us a single code path that handles everything. The condition mechanism is the extension point — you get composability without complexity.

### Why ERC-7579 smart accounts instead of EOAs?

EOAs can't do gasless transactions, can't do spending limits, can't do passkey auth, can't do session keys. Every feature in this protocol requires smart accounts. ERC-7579 is the modular standard that lets us add capabilities without redeploying.

### Why Base and not Ethereum mainnet?

$0.003 gas vs $3.00 gas. For payments under $100, mainnet gas is a dealbreaker. Base has Coinbase's distribution, sufficient decentralization trajectory, and the same security model (optimistic rollup to Ethereum L1).

### Why passkeys and not seed phrases?

Seed phrases are a UX catastrophe. 95% of target users will never write down 12 words. Passkeys are synced across devices via iCloud/Google, backed by biometrics, and phishing-resistant. The tradeoff: platform dependency. We accept this because recovery modules provide escape hatches.

### Why sequential nonces instead of random?

Sequential nonces let relayers detect gaps (missing transactions) and are simpler to reason about. Random nonces save a storage read but add complexity. For a payment protocol where ordering matters, sequential is correct.

### Why `staticcall` for condition checks?

A condition that can modify state during evaluation is a security nightmare (reentrancy, state manipulation). `staticcall` guarantees conditions are pure functions of their inputs. State updates happen only in the controlled `onExecute()` callback after successful transfer.

### Why fee caps are hardcoded?

Trust requires commitment. If we can raise fees to 5% tomorrow, merchants won't integrate. Hardcoded caps (1% merchant max, P2P permanently free) are a protocol-level promise. Changing them requires deploying a new IntentExecutor — a visible, auditable event.

### Why no governance token?

Tokens create misaligned incentives: holders want price appreciation, not protocol utility. Fee revenue goes to protocol treasury (multisig → DAO over time). Governance, if needed, uses reputation-weighted voting by active participants, not token-weighted plutocracy.

### Why append-only ConditionRegistry?

If conditions can be replaced, an attacker who compromises the registry can swap a legitimate condition for a malicious one, affecting all intents referencing that condition hash. Append-only means existing conditions are immutable. Buggy conditions are deprecated (UI-level) and users migrate to new versions.

### Why USDC first and not multi-token?

Multi-token from day one means multi-token bugs from day one. USDC is the dominant stablecoin with the best liquidity on Base. Start narrow, expand when the core is battle-tested. Adding tokens is a governance action, not a protocol upgrade.

---

# Appendix B: Non-Goals

The following are explicitly **not** goals of Pay Protocol v4:

1. **Privacy**: All transactions are on-chain and public. We do not implement mixers, ZK proofs, or confidential transfers. Privacy is a future research area, not a v4 feature.

2. **Fiat integration**: The protocol moves tokens, not dollars. Fiat on/off-ramps are partner integrations, not protocol features.

3. **Lending/DeFi**: This is a payment protocol, not a financial platform. No yield, no collateral, no liquidations.

4. **Identity/KYC**: The protocol is permissionless. Identity verification happens at the application layer (relayers, merchant apps).

5. **Dispute arbitration**: The protocol provides escrow primitives (conditions + timelocks). Actual dispute resolution (who's right?) is an application concern.

6. **Token issuance**: No protocol token, no points, no NFT receipts. Revenue comes from fees.

7. **Multi-chain from day one**: Base only at launch. Cross-chain via ERC-7683 in Phase 3 when the standard is mature.

8. **Replacing Visa/Mastercard**: We're not building a card network. We're building internet-native payment rails. Different markets, different UX.

9. **Regulatory compliance at the protocol level**: Contracts are permissionless. Compliance is the relayer's and application's responsibility.

10. **Backwards compatibility with existing wallet UX**: We use smart accounts with passkeys. Users with MetaMask/Rabby can interact via the contracts directly but won't get the full UX.

---

# Appendix C: Open Questions

### Unresolved — Needs Decision Before Implementation

1. **Condition upgrade path**: When a condition has a bug, users must manually update their intents to point to the new condition address. Is there a safe way to allow condition upgrades without introducing the "registry compromise" attack vector? Possible: per-user condition proxies.

2. **Multi-sig for high-value accounts**: Should the protocol ship a default multisig module, or rely on third-party (Safe-style) modules? Leaning toward: ship a simple 2-of-3 module, recommend Safe for complex setups.

3. **Relayer incentive alignment**: Reference relayer is free (funded by protocol fees). How do we prevent relayer centralization? Possible: relayer fee market where users can tip for priority. But this adds UX complexity.

4. **Subscription cancellation UX**: User cancels a subscription by... what exactly? Revoking the condition? Sending a cancellation intent? Setting the condition to deprecated? Need a clean answer.

5. **Intent batching**: Can a user sign one message that authorizes multiple transfers (e.g., payroll)? Current design requires one intent per transfer. Batch intents would reduce signing friction but complicate the struct.

### Unresolved — Can Defer Past v4

6. **Privacy layer**: ZK proofs for confidential amounts? Stealth addresses for recipient privacy? Important but not v4.

7. **Offline payments**: Can two users exchange signed intents without internet, settling later? Technically possible with nonce management but complex.

8. **Cross-chain atomic swaps**: User pays in USDC on Base, merchant receives EURC on Ethereum. Requires cross-chain intent infrastructure (ERC-7683).

9. **Insurance/protection fund**: Should protocol fees fund an insurance pool for smart contract exploit losses? How large? What's the claim process?

10. **Formal verification**: The IntentExecutor is simple enough to formally verify. Worth the cost (~$100K–$200K) or sufficient to rely on audits?

---

*Pay Protocol v4. The definitive version.*
*Three contracts. One intent struct. Everything is modules.*
*Sign. Send. Settled.*
