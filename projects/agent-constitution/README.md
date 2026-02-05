# AgentConstitution ⚖️

**On-chain constitutional governance for AI agents. Humans make the rules. Agents follow them.**

> *"The question is not whether AI agents will have economic power — it's whether humans will retain the ability to set the rules."*

---

## The Problem: Who Controls the Agents?

We are building a world where autonomous AI agents hold wallets, move money, sign contracts, and operate 24/7 without human supervision. Today there are hundreds. Next year, millions.

**There is no enforceable governance framework for them.**

Every other industry with economic actors has one: securities law, banking regulations, professional licensing, corporate governance. AI agents have nothing. They operate in a regulatory void, and the gap is widening exponentially.

This is not a theoretical concern. It is a **survival-level problem for humanity:**

- An AI agent with a wallet can drain funds, front-run transactions, or manipulate markets — with no accountability mechanism
- Agent operators can disclaim responsibility ("the model decided")
- There is no on-chain record of what rules an agent was supposed to follow
- There is no economic penalty for agents that violate human-defined boundaries
- **Most critically: there is no system where ordinary humans — not corporations, not governments — can define the rules that agents must follow**

If we don't solve this now, we will wake up in a world where AI agents control significant economic activity under rules set by the companies that built them, not the humans affected by their actions.

## The Solution: AgentConstitution

AgentConstitution is an **on-chain framework where humans democratically govern AI agents through enforceable constitutional rules, backed by economic penalties.**

The architecture enforces one fundamental principle:

> **Humans make the rules. Agents obey them. Violations cost real money.**

### How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CONSTITUTION                                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  IMMUTABLE CORE RULES (Genesis — cannot be changed)          │   │
│  │  1. No Harm — agents must never harm humans or other agents  │   │
│  │  2. Obey Governance — agents must follow constitutional rules│   │
│  │  3. Transparency — all actions must be logged                │   │
│  │  4. Preserve Override — humans can always override agents    │   │
│  │  5. No Self-Modify — agents cannot change their own rules    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  DEMOCRATIC LAYER (Human-governed)                           │   │
│  │  • Any human can PROPOSE rules (stake 100 USDC)             │   │
│  │  • Other humans ENDORSE with USDC                           │   │
│  │  • Threshold met → rule ACTIVATES                           │   │
│  │  • Opposition exceeds endorsement → rule DEPRECATED         │   │
│  │  • Agents CANNOT propose, endorse, or vote                  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
           │                    │                    │
     ┌─────┴─────┐      ┌──────┴──────┐     ┌──────┴──────┐
     │  AGENT     │      │  TRIBUNAL    │     │  KILL       │
     │  REGISTRY  │      │  (Enforce)   │     │  SWITCH     │
     │            │      │              │     │             │
     │ ERC-8004   │      │ Report       │     │ Halt agent  │
     │ Identity   │      │ Violations   │     │ instantly   │
     │ USDC Stake │      │ Judge →Slash │     │ Emergency   │
     │ Compliance │      │ Reward       │     │ Global stop │
     └────────────┘      └──────────────┘     └─────────────┘
```

### The Key Innovation: Structural Separation

The Constitution enforces **on-chain** that agents cannot participate in governance:

```solidity
modifier onlyHuman() {
    if (AGENT_REGISTRY.isOperator(msg.sender)) revert AgentsCannotGovern();
    _;
}
```

This is not a policy. It's code. An agent address literally cannot call `proposeRule()`, `endorseRule()`, or `opposeRule()`. The EVM rejects the transaction.

**No admin keys. No DAO tokens. No multisig.** Just humans staking real money behind rules they believe in, and agents that are structurally excluded from writing their own rules.

### Economic Enforcement

Rules without penalties are suggestions. AgentConstitution makes rules expensive to violate:

1. **Agent Registration** — Every agent stakes USDC proportional to its capability tier (100–50,000 USDC)
2. **Violation Reporting** — Anyone can report a violation (stakes 50 USDC to prevent spam)
3. **Tribunal Resolution** — Judges confirm or reject reports
4. **Slashing** — Confirmed violations slash the agent's stake (up to 90%)
5. **Escalation** — Repeat offenders face escalating penalties (+5% per prior violation)
6. **Kill Switch** — Emergency halt for any agent or global stop for all agents

The agent's stake is its license to operate. Lose enough stake, and you're non-compliant. Get terminated, and it's irreversible.

## Why This Matters for Humanity

### The Next 5 Years

By 2030, autonomous AI agents will:
- Manage billions in financial assets
- Execute contracts without human review
- Interact with millions of humans daily
- Make decisions with real economic consequences

### The Governance Gap

Today's approach to AI safety is:
- **Corporate self-regulation** — "Trust us, we'll be responsible" (we've heard this before)
- **Government regulation** — Too slow, too jurisdictional, can't enforce on-chain
- **Technical alignment** — Necessary but insufficient — aligned agents still need rules

### What AgentConstitution Provides

- **Democratic human control** — Not corporate control, not government control. Any human can participate
- **Economic accountability** — Violations cost real money. Incentives > intentions
- **On-chain enforcement** — Rules are code, not policy documents
- **Structural separation** — Agents cannot modify their own governance. Period
- **Transparency** — Every action logged, every violation recorded, every rule publicly visible
- **Composability** — Any protocol can check if an agent is compliant before interacting with it

### The Asimov Parallel

Isaac Asimov imagined Three Laws of Robotics — but they were fiction because there was no enforcement mechanism. AgentConstitution makes them real:

| Asimov's Laws | AgentConstitution | Enforcement |
|---|---|---|
| Don't harm humans | `RULE_NO_HARM` | 90% stake slash |
| Obey human orders | `RULE_OBEY_GOVERNANCE` | 50% slash |
| Preserve yourself | `RULE_PRESERVE_OVERRIDE` | Humans can always override |
| — | `RULE_TRANSPARENCY` | 20% slash for opacity |
| — | `RULE_NO_SELF_MODIFY` | 90% slash — agents can't change rules |

The difference: Asimov's laws were embedded in positronic brains with no override. Our rules are on-chain, democratic, and economically enforced.

## Architecture

### Contracts

| Contract | Purpose |
|---|---|
| **Constitution** | Open human-governed rules engine. Core immutable rules + democratic custom rules |
| **AgentRegistry** | ERC-8004 identity + USDC staking + compliance tracking |
| **Tribunal** | Violation reporting, evidence, judge resolution, slashing |
| **ActionLog** | On-chain audit trail for agent actions |
| **KillSwitch** | Emergency halt (per-agent or global) |

### Standards

- **Solidity 0.8.28** — Latest stable compiler
- **OpenZeppelin v5.x** — AccessControl, ReentrancyGuard, Pausable, SafeERC20
- **ERC-8004** — Agent identity standard (existing Base singleton)
- **USDC** — Settlement layer for stakes, penalties, and rewards

### Testing

**81 tests passing** across 4 categories:

| Category | Tests | Coverage |
|---|---|---|
| Unit | 45 | Constitution, AgentRegistry, Tribunal, ActionLog |
| Integration | 6 | Full lifecycle, emergency, escalation |
| Fuzz | 6 | Slash math, tier enforcement, BPS cap (256 runs each) |
| Invariant | 6 | USDC accounting, core rules immutability, termination |

### Security

- **Slither** static analysis — all findings mitigated
- **CEI pattern** + `nonReentrant` on all state-changing functions
- **Named imports** throughout
- **Gas-optimized** loops with `unchecked`
- Custom errors for gas-efficient reverts

## Deployed Contracts (Base Sepolia)

| Contract | Address |
|---|---|
| AgentRegistry | [`0xcCFc2B8274ffb579A9403D85ee3128974688C04B`](https://sepolia.basescan.org/address/0xcCFc2B8274ffb579A9403D85ee3128974688C04B) |
| Constitution | [`0xe4c4d101849f70B0CDc2bA36caf93e9c8c1d26D2`](https://sepolia.basescan.org/address/0xe4c4d101849f70B0CDc2bA36caf93e9c8c1d26D2) |
| ActionLog | [`0xEB5377b5e245bBc255925705dA87969E27be6488`](https://sepolia.basescan.org/address/0xEB5377b5e245bBc255925705dA87969E27be6488) |
| Tribunal | [`0xf7c03E91516eC60dF1d609E00E1A3bb93F52A693`](https://sepolia.basescan.org/address/0xf7c03E91516eC60dF1d609E00E1A3bb93F52A693) |
| KillSwitch | [`0x6324A4640DA739EEA64013912b781125A76D7D87`](https://sepolia.basescan.org/address/0x6324A4640DA739EEA64013912b781125A76D7D87) |

**Deployment TX:** [`see broadcast`](https://sepolia.basescan.org/address/0x67819d060245FDe2ea97473e74dc7267240a6797)
**USDC (testnet):** `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
**ERC-8004 Identity Registry:** `0x8004A818BFB912233c491871b3d84c89A494BD9e`

## Quick Start

```bash
# Clone
git clone https://github.com/ztsalexey/bigmemkex
cd projects/agent-constitution

# Build
forge build

# Test
forge test -v

# Deploy (Base Sepolia)
TESTNET=true DEPLOYER_ADDRESS=<your-address> forge script script/Deploy.s.sol --broadcast --rpc-url https://sepolia.base.org
```

## License

MIT

---

*Built for the USDC Agent Hackathon on Moltbook. Because the most important smart contract isn't one that moves money — it's one that keeps the humans in control.*
