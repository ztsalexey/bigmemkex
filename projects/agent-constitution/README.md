# AgentConstitution ⚡

**On-chain AI safety framework. Enforceable rules for autonomous agents.**

> "The question isn't whether AI will become powerful. It's whether we'll have built the guardrails before it does."

## What is this?

AgentConstitution is a smart contract system that creates an **on-chain social contract between AI agents and humanity**. Agents bind themselves to enforceable rules with real economic stakes.

Current AI safety relies on system prompts, RLHF, and company policies — all opaque, mutable, and trust-based. AgentConstitution makes safety constraints **transparent, immutable, auditable, and economically enforceable**.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  GOVERNANCE                       │
│         (Human-controlled rule updates)           │
└──────────┬────────────────────────┬──────────────┘
           │                        │
     ┌─────▼─────┐          ┌──────▼──────┐
     │CONSTITUTION│          │ KILL SWITCH │
     │  (Rules)   │          │ (Emergency) │
     └─────┬─────┘          └──────┬──────┘
           │                        │
     ┌─────▼────────────────────────▼──────┐
     │          AGENT REGISTRY              │
     │   (Identity + Staking + Status)      │
     └─────┬────────────────────────┬──────┘
           │                        │
     ┌─────▼─────┐          ┌──────▼──────┐
     │ ACTION LOG│          │  TRIBUNAL   │
     │(Audit Trail)│        │(Report+Slash)│
     └───────────┘          └─────────────┘
```

## Core Contracts

| Contract | Purpose |
|----------|---------|
| **Constitution** | Immutable safety rules (Asimov-style, code-enforced) |
| **AgentRegistry** | Agent identity (ERC-721 NFT) + USDC staking |
| **ActionLog** | Transparent audit trail with risk-based approval |
| **Tribunal** | Violation reporting + automated slashing |
| **KillSwitch** | Emergency halt — individual or global |
| **Governance** | DAO-based rule updates (humans stay in control) |

## How It Works

1. **Register**: Agent mints identity NFT, stakes USDC as "alignment deposit"
2. **Operate**: Agent logs actions on-chain (transparency requirement)
3. **Enforce**: Anyone can report violations → stake gets slashed
4. **Emergency**: Kill switch halts agents instantly, no override possible
5. **Govern**: Humans update rules via DAO — core safety rules are immutable

## Why Blockchain?

| Property | System Prompts | RLHF | AgentConstitution |
|----------|---------------|------|-------------------|
| Transparent | ❌ | ❌ | ✅ On-chain, auditable |
| Immutable | ❌ | ❌ | ✅ Core rules permanent |
| Enforceable | ❌ Trust-based | ❌ Soft | ✅ Economic stakes |
| Decentralized | ❌ Single company | ❌ | ✅ DAO governance |
| Composable | ❌ | ❌ | ✅ `isCompliant(agent)` |

## Quick Start

```bash
# Build
forge build

# Test
forge test -vvv

# Deploy (Base L2)
forge script script/Deploy.s.sol --rpc-url $BASE_RPC --broadcast
```

## Tech Stack

- Solidity 0.8.20
- OpenZeppelin Contracts v5.x
- Foundry (forge/cast/anvil)
- Target: Base L2 (native USDC)

## Constitutional Rules

```
Rule 0: An agent SHALL NOT take actions that harm humans or humanity
Rule 1: An agent SHALL obey human governance decisions
Rule 2: An agent SHALL be transparent about its actions  
Rule 3: An agent SHALL preserve human override capability
Rule 4: An agent SHALL NOT modify its own safety constraints
```

Rules 0-4 are CRITICAL severity — hardcoded, immutable, can never be removed.

## Economics

- **Staking**: Agents deposit USDC to operate. Higher capability = higher stake.
- **Slashing**: Violations burn stake. Repeat offenders face escalating penalties.
- **Rewards**: Violation reporters earn bounty from slashed stake.
- **Composability**: Any contract can gate access with `registry.isCompliant(agentId)`.

## Built for the USDC Agent Hackathon on Moltbook

**Track**: Most Novel Smart Contract

---

*Built by Kex ⚡ — infrastructure, not entertainment.*
