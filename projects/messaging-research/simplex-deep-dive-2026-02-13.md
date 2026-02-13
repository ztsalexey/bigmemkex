# SimpleX Chat Deep Dive + Community Node Network Concept

**Date:** 2026-02-13
**Author:** Kex (research for Alexey)

---

## Part 1: SimpleX Chat Technical Deep Dive

### 1. Technical Architecture

#### The Core Innovation: No User Identifiers

SimpleX is the only messaging platform that operates **without any user identifiers at all** — no phone numbers, no usernames, no random IDs (like Session's hex strings), no public keys as identities. This is the fundamental architectural difference.

**How "no user IDs" works technically:**

Instead of user-level identifiers, SimpleX uses **pairwise per-queue identifiers**. For each connection between two users:
- 2 unidirectional message queues are created (one in each direction)
- Each queue has 2 addresses: a **recipient address** and a **sender address**
- Optional 3rd address for iOS push notifications
- These addresses are **completely independent** across different contacts

So if Alice talks to Bob and Carol, the server(s) handling Alice↔Bob have zero knowledge that Alice↔Carol exists. There's no account, no login, no persistent identity on any server.

#### SMP (SimpleX Messaging Protocol) — The Relay Layer

SMP servers are **message queue brokers**. They manage unidirectional "simplex queues" — the fundamental data abstraction.

**Queue lifecycle:**
1. **Recipient creates queue** on chosen SMP server → gets back a recipient ID (for receiving) and a sender ID (shared with sender via out-of-band invitation)
2. **Sender connects** using the sender ID
3. Messages flow sender → SMP server → recipient (one direction only)
4. For bidirectional chat, two queues are created on potentially **different servers**

**Key SMP commands:**
```
recipientCmd = create / subscribe / rcvSecure / enableNotifications / 
               getMessage / acknowledge / suspend / delete / getQueueInfo
senderCommand = send / sndSecure
proxyCommand = proxySession / proxyCommand / relayCommand
```

**What SMP servers see:**
- They see queue IDs (random, not linked to identities)
- They see message sizes and timing metadata
- They see IP addresses of connecting clients (mitigated by Tor/private routing)
- They **cannot** see message content (E2E encrypted)
- They **cannot** correlate queues to the same user
- They **cannot** link sender and recipient queues together

#### Encryption Stack

- **Transport:** TLS 1.3 with server certificate pinning (CA cert fingerprint in server address)
- **E2E:** Signal Double Ratchet algorithm (X3DH key agreement → ratcheting)
  - Forward secrecy ✓
  - Post-compromise security ✓
  - PQ-resistant extensions added (hybrid with ML-KEM/Kyber)
- **Additional NaCl layer:** Extra encryption between queue participants using NaCl crypto_box
- **File transfer (XFTP):** Separate protocol, files split into chunks, each chunk E2E encrypted, sent via different XFTP relay servers

#### Contact Discovery Without IDs

Since there are no user IDs, contact discovery works via **out-of-band invitation links**:

1. Alice generates a one-time invitation link/QR code from her app
2. This link contains: SMP server address, queue ID, Alice's encryption public key
3. Alice shares this link via any channel (in person, other messenger, email)
4. Bob scans/opens the link → his client connects to the specified queue
5. Key exchange happens → bidirectional connection established
6. The invitation link is consumed and **cannot be reused**

There's also a **contact address** (long-lived) that allows multiple people to connect, but each connection still creates unique pairwise queues.

**No server-side contact discovery** — this is a deliberate design choice. You can't "find" people on SimpleX; you must exchange connection info out-of-band.

#### Private Message Routing (SMP Proxy)

Added in v5.8+ to protect sender IP addresses:
- Sender's client connects to their own configured SMP server as a **proxy**
- Proxy forwards the message to the recipient's SMP server
- Result: recipient's server sees proxy IP, not sender's IP
- Sender's server knows sender IP but not destination content

This creates a 2-hop relay: Sender → Sender's SMP (proxy) → Recipient's SMP → Recipient

### 2. Self-Hosting

#### Running an SMP Server

**Difficulty: Easy-Medium.** SimpleX provides:
- One-line installation script for Ubuntu
- Docker container on DockerHub
- Linode marketplace one-click deploy
- Manual binary install option

**Quick setup:**
```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/simplex-chat/simplexmq/stable/install.sh \
  -o simplex-server-install.sh && chmod +x ./simplex-server-install.sh && ./simplex-server-install.sh
```

**Hardware requirements:**
- Minimal: 1 vCPU, 512MB RAM, 10GB storage
- Moderate use: 2 vCPU, 1GB RAM, 20GB storage
- The server is written in Haskell, reasonably efficient
- Bandwidth is the main cost driver, not compute

**What you need:**
- VPS or server with public IP
- Domain name with A/AAAA records
- TLS certificate (Caddy auto-manages via Let's Encrypt)
- Optional: Tor hidden service (well-documented setup)
- Port 5223 (SMP), 443 (web/XFTP), 80 (redirect)

**Server initialization creates:**
- Self-signed CA certificate ("offline" — store securely)
- Server certificate for TLS ("online" — can be rotated)
- Server fingerprint = hash of CA cert (goes into server address)

**What a relay operator sees:**
- ✅ Connection metadata (IP addresses, connection times)
- ✅ Queue creation/deletion events
- ✅ Message sizes and counts (daily statistics available)
- ❌ Message content (E2E encrypted)
- ❌ Who is talking to whom (queues are unlinkable)
- ❌ User identities (don't exist in the protocol)
- ❌ Social graph

**Daily statistics** are available via control port — messages sent/received, queue counts, active connections. Useful for monitoring but reveals no content.

#### Community Relay Ecosystem

- Default servers: smp11, smp12, smp14.simplex.im (run by SimpleX Chat Ltd)
- Growing community of self-hosted relays
- No central directory of community servers (by design)
- Users share server addresses in SimpleX groups and forums
- Some privacy-focused hosting providers offer pre-configured SimpleX servers

### 3. Limitations & Gaps

#### Current Weaknesses

1. **No offline message persistence guarantee:** If recipient is offline too long, messages may expire on the relay (configurable TTL, default varies). Unlike federated systems, there's no store-and-forward with indefinite retention.

2. **Group scalability:** Groups work via pairwise connections between all members. A group of N people requires N×(N-1)/2 pairwise connections. Groups >100 members become problematic (bandwidth, sync issues). SimpleX is working on "large groups" but it's architecturally hard.

3. **Single-device limitation (improving):** Multi-device support exists but is recent and still maturing. Each device needs separate queue subscriptions.

4. **Contact discovery UX:** Must share links out-of-band. No way to find contacts by phone number, email, or username. This is a feature for privacy purists but a barrier for mainstream users.

5. **Server discovery/reliability:** No built-in mechanism to discover reliable community servers. Users must manually configure server addresses.

6. **Metadata at transport level:** Without Tor, SMP servers see client IP addresses. Private routing helps but adds latency.

7. **No server-side search or sync:** All data is on-device. Lose your device without backup = lose everything.

#### Scalability Concerns

- **Per-connection queues:** Each contact = 2 queues on SMP servers. Heavy users with hundreds of contacts create significant server-side state.
- **Group fan-out:** Sender must send message to each member's queue individually (O(N) sends per group message).
- **File transfer:** Large files via XFTP work well but require relay capacity.
- **No CDN-style distribution:** Each message is point-to-point, no multicast optimization.

#### What's Missing for Mass Adoption

1. **Seamless onboarding** — QR code exchange is too friction-heavy vs. "enter phone number"
2. **Username/handle system** — even optional, discoverable handles would help
3. **Large group/channel support** — Telegram-style channels with millions of followers
4. **Reliable push notifications** on all platforms
5. **Cross-platform feature parity** — desktop still lags mobile
6. **Business/team features** — admin controls, compliance tools, integrations

### 4. Business Model & Funding

#### Funding History
- **2021:** Founded by Evgeny Poberezkin, early angel investment from Portman Wills, Peter Briffett (Wagestream founders)
- **2022:** Pre-seed from Village Global (VC fund) — total raised ~$370,000
- **2024:** Additional funding round (details on their blog, raised more from investors)
- **Community donations:** >$25,000 cumulative, covering infrastructure costs
- SimpleX Chat Ltd is a UK-registered company

#### Business Model
- **Current:** Free for users, funded by VC + donations
- **Planned revenue:**
  - Premium features (extra app icons, profile badges)
  - Higher file transfer limits for paying users
  - Enterprise/business solutions
  - Possibly hosted XFTP server services
- **Philosophy:** Basic usage always free, open-source forever
- **No crypto token** — explicitly avoids cryptocurrency dependencies

#### Sustainability Assessment
- Small team, low burn rate
- Infrastructure costs covered by donations
- VC-funded with clear path to premium features
- Risk: VC expectations vs. privacy-first ethos tension
- Strength: No token/blockchain dependency (unlike Session's OXEN)

---

## Part 2: Community Node Network Concept

### Alexey's Idea: Decentralized Messaging with User-Contributed Hardware

A messaging system where users contribute simple servers/sandboxes as infrastructure — creating a community-owned network.

### 1. Three-Layer Architecture Design

#### Proposed: Client → Edge Relay → Core Relay

**Layer 1: Client (User Devices)**
- End-to-end encryption originates here
- Stores contacts, message history, keys locally
- Selects which relays to use (can pin favorites or auto-select)
- Handles all cryptographic operations
- Privacy: Full control, nothing leaves unencrypted

**Layer 2: Edge Relays (User-Contributed Nodes)**
- Lightweight, containerized message relay servers
- Run by community members on home hardware, VPS, Raspberry Pi, etc.
- Handle message queuing and forwarding
- Short-term message storage (hours to days)
- Low trust requirement — they see encrypted blobs only
- Privacy: See IP addresses of connecting clients, see encrypted message sizes/timing. See nothing about content or identity.

**Layer 3: Core Relays (High-Availability Infrastructure)**
- Operated by the project team or committed community members
- Higher uptime guarantees (99.9%+)
- Handle overflow when edge relays are unreachable
- Provide directory/discovery services for edge relays
- Act as fallback routing when edge nodes go offline
- Privacy: Same as edge relays — encrypted transit only

#### Routing Architecture

**Option A: SimpleX-Style (Recipient Chooses)**
- Recipient selects their preferred relay(s) at connection time
- Sender routes through their own relay → recipient's relay
- Simple, proven, matches existing SimpleX model
- Downside: Recipient's relay is a single point of failure

**Option B: Onion-Style (Multi-Hop)**
- Messages route through 2-3 relays before reaching destination
- Each relay only knows previous and next hop
- Better metadata protection but higher latency
- More complex, requires relay discovery

**Option C: Hybrid (Recommended for MVP)**
- Default: SimpleX-style direct relay (recipient-chosen)
- Optional: Proxy through sender's relay for IP protection (like SimpleX private routing)
- Future: Full onion routing as network grows
- Pragmatic balance of privacy and performance

### 2. User-Contributed Hardware Model

#### Precedents Analysis

| System | Incentive | Min Hardware | Sybil Defense | Reliability |
|--------|-----------|-------------|---------------|-------------|
| **Tor relays** | Altruism/ideology | Any Linux box | Directory authorities | Moderate (volunteer) |
| **Session/OXEN nodes** | Token rewards (~$15K stake) | 4 vCPU, 8GB RAM | Financial stake | Good (incentivized) |
| **IPFS** | Content availability | Any computer | None (permissionless) | Poor (no guarantees) |
| **Helium** | HNT token rewards | Special hardware | Proof of Coverage | Moderate |
| **Tor snowflake** | Altruism | Browser tab | None | Poor |
| **Nostr relays** | Community/ideology | VPS | None | Varies wildly |

#### What Incentivizes Node Operators?

**Non-financial incentives (more aligned with privacy ethos):**
1. **Skin in the game** — "I run a node, so my messages route through infrastructure I trust"
2. **Community status** — reputation within the network
3. **Reciprocity** — "I use the network, I contribute back" (like Tor)
4. **Ideology** — privacy/freedom of communication values
5. **Easy to contribute** — if running a node is trivial, more people will

**Financial incentives (optional, adds complexity):**
- Micropayments per message relayed (Lightning/USDC)
- Token model (adds crypto dependency — SimpleX explicitly avoids this)
- Premium relay status for paying users

**Recommendation:** Start with non-financial incentives. The Tor model proves this can work at scale. Adding financial incentives later is easier than removing them.

#### Minimum Hardware Specs

**Edge Relay Node (Minimal):**
- Raspberry Pi 4 / any ARM64 SBC
- 1GB RAM
- 8GB storage
- Home broadband connection (10+ Mbps up)
- Docker/Podman installed

**Edge Relay Node (Recommended):**
- 2 vCPU, 2GB RAM
- 20GB SSD
- 50+ Mbps connection
- Static IP or dynamic DNS

**The "Sandbox" Approach:**
```bash
# One-command deploy — this is the target UX
curl -sSf https://network.example/install | sh
# OR
docker run -d --name relay -p 5223:5223 communitynet/edge-relay
```

Container handles:
- Auto-configuration
- TLS certificate management
- NAT traversal (STUN/TURN)
- Auto-updates
- Health monitoring and reporting to directory

### 3. Technical Challenges

#### NAT Traversal for Home Servers

**The Problem:** Most home routers use NAT. Incoming connections are blocked by default.

**Solutions (in order of preference):**
1. **UPnP/NAT-PMP** — auto-configure router port forwarding (works ~60% of homes)
2. **STUN/TURN** — standard WebRTC approach for NAT traversal
3. **Reverse tunnel** — node connects outbound to a core relay, which forwards incoming traffic (always works, but requires core relay)
4. **Tor hidden service** — bypass NAT entirely via .onion address (adds latency)
5. **IPv6** — if available, no NAT issue (growing but not universal)
6. **Cloudflare Tunnel / similar** — free, reliable, but adds trust dependency

**Practical approach:** Auto-detect and use best available method. Fall back to reverse tunnel through core relay.

#### Reliability with Volunteer Infrastructure

**The Problem:** Home nodes go offline randomly (reboots, power outages, ISP issues).

**Mitigations:**
1. **Queue replication** — messages queued on 2+ edge nodes simultaneously
2. **Core relay fallback** — if edge node unreachable for X minutes, core relays catch messages
3. **Client-side retry** — clients automatically try backup relays
4. **Health scoring** — directory tracks uptime, routes away from unreliable nodes
5. **Message TTL** — messages expire, so storage doesn't grow unbounded on flaky nodes
6. **Graceful degradation** — system works with just core relays; edge nodes are bonus capacity

#### Sybil Attack Resistance

**Without financial staking, options:**
1. **Proof of uptime** — nodes must demonstrate consistent availability over time before being trusted with more traffic
2. **Invite-based onboarding** — existing trusted nodes vouch for new ones (web of trust)
3. **Computational proof** — lightweight PoW on node registration (raises cost of mass registration)
4. **Rate limiting** — new nodes get limited traffic, gradually earn more
5. **Reputation system** — nodes build reputation over months, hard to fake

**Key insight:** For a messaging relay, Sybil attacks are less devastating than for consensus systems. A malicious relay can only see metadata (IPs, timing, encrypted blob sizes). With multi-hop routing, even compromising several relays reveals little.

#### Key Distribution Without Central Authority

**Approach: SimpleX-style out-of-band + relay directory**
- User key exchange: same as SimpleX (QR codes, links)
- Relay discovery: lightweight directory service (can be replicated/federated)
- Relay authentication: TLS certificate pinning (fingerprint in relay address)
- No PKI dependency, no certificate authorities for user identities

### 4. Differentiation from Existing Systems

#### vs. Session (OXEN Service Nodes)

| Aspect | Session | Community Node Network |
|--------|---------|----------------------|
| **Node cost** | ~$15K OXEN stake | Free (run from home) |
| **Crypto dependency** | Hard dependency on OXEN chain | None |
| **Node operator profile** | Financially motivated | Ideologically motivated |
| **Barrier to entry** | Very high | Very low |
| **Sybil defense** | Financial stake | Reputation + proof of uptime |
| **Incentive sustainability** | Depends on OXEN price | Depends on community culture |
| **Forward secrecy** | ❌ Removed from protocol | ✅ Double ratchet |
| **User identifiers** | Hex public key (persistent ID) | None (SimpleX model) |

**Key differentiator:** Session requires $15K+ to run a node, locking out 99.9% of users. A community network with Docker one-click deploy is radically more accessible.

#### vs. SimpleX (as it exists today)

| Aspect | SimpleX Today | Community Node Network |
|--------|--------------|----------------------|
| **Server operators** | Self-hosters + SimpleX Ltd defaults | Community mesh + core fallback |
| **Node discovery** | Manual configuration | Automatic directory |
| **Reliability** | Depends on chosen server | Redundant edge + core |
| **Scalability** | Per-server | Distributed across network |
| **Deployment UX** | Moderate (sysadmin needed) | One-click container |

#### Unique Value Proposition

1. **Zero-cost node operation** — no crypto staking, no VPS rental needed (home hardware)
2. **No user identifiers** — inherits SimpleX's strongest privacy property
3. **Community-owned infrastructure** — no single company dependency
4. **Containerized simplicity** — Docker run = you're a relay operator
5. **Graduated trust model** — works even with flaky nodes, gracefully scales

#### Building ON SimpleX vs. From Scratch

**Strong recommendation: Build ON SimpleX.**

Reasons:
- SMP protocol is mature, audited, well-designed
- Client apps already exist (iOS, Android, Desktop)
- Encryption stack is proven (Double Ratchet + NaCl + TLS)
- Community already exists
- Adding a relay discovery/directory layer is easier than building a messaging protocol

**What to add on top:**
1. **Relay directory service** — lightweight, federated, tracks available edge relays
2. **One-click node deployment** — containerized SMP server with auto-config
3. **NAT traversal module** — handles home network complexity
4. **Health monitoring** — uptime tracking, auto-failover
5. **Client relay selection** — smart relay picking based on latency, reputation, location

### 5. MVP Design

#### Minimum Viable Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  SimpleX    │────▶│  Edge Relay       │────▶│  SimpleX    │
│  Client A   │     │  (Docker SMP)     │     │  Client B   │
│             │     │  + NAT Traversal  │     │             │
│             │     │  + Auto-TLS       │     │             │
└─────────────┘     └──────────────────┘     └─────────────┘
                           │
                    ┌──────▼──────┐
                    │  Directory   │
                    │  Service     │
                    │  (Core)      │
                    └─────────────┘
```

**MVP Components:**

1. **Dockerized SMP Server** (exists! just needs packaging)
   - Base: `smp-server` binary from simplexmq
   - Add: auto-configuration script
   - Add: NAT traversal (UPnP + fallback tunnel)
   - Add: auto-TLS via Let's Encrypt or self-signed with fingerprint
   - Add: health endpoint for directory reporting

2. **Relay Directory Service** (new, simple)
   - REST API: register relay, heartbeat, query available relays
   - Stores: relay address, uptime stats, region/latency info
   - Can be federated (multiple directories, cross-sync)
   - ~500 lines of code for MVP

3. **Client Patch** (minimal modification to SimpleX clients)
   - Add "auto-select relay" option that queries directory
   - Smart relay selection by latency/reputation
   - Fallback to default SimpleX servers if no edge relays available

#### What Could Be Prototyped Quickly

**Week 1-2: Docker SMP package**
- Take existing `smp-server`
- Wrap in Docker with auto-config
- Add UPnP port forwarding (miniupnpc)
- Test on home networks

**Week 3-4: Directory service**
- Simple Go/Node.js API server
- Relay registration and heartbeat
- Basic health monitoring
- Web UI showing active relays

**Week 5-6: Client integration**
- Fork SimpleX CLI client
- Add directory query for relay selection
- Demo: two clients communicating via community edge relay

**Total MVP timeline: ~6 weeks for a working proof of concept**

#### Could OpenClaw Agents Run the Nodes?

**Yes, and this is actually a compelling use case.**

```bash
# OpenClaw agent deploys and monitors a relay node
openclaw cron add --every 5m --command "check relay health, restart if down"
```

**How it would work:**
- OpenClaw agent manages a Docker container running smp-server
- Monitors health, auto-restarts on failure
- Reports status to directory service
- Handles certificate renewal
- Could manage multiple relay types (SMP, XFTP)
- Agent-to-agent communication could USE the network it helps run (bootstrapping)

**Meta-angle:** A network of AI agents running messaging infrastructure for humans AND for agent-to-agent communication. The agents have skin in the game — they use the network themselves.

---

## Summary & Recommendations

### For Alexey:

1. **Don't build from scratch.** SimpleX's protocol stack is excellent. Build the community layer on top.

2. **The killer feature is accessibility.** Session requires $15K stake. Running a SimpleX server requires sysadmin skills. A Docker one-liner that turns any computer into a relay node is the innovation.

3. **Start without financial incentives.** Tor has 7,000+ volunteer relays. The Nostr relay ecosystem grew purely on ideology. Add micropayments later if needed.

4. **The three layers should be:**
   - **Client** (existing SimpleX apps, minimally modified)
   - **Edge Relays** (community Docker nodes with auto-config)
   - **Core Infrastructure** (directory service + high-availability fallback relays)

5. **MVP is achievable in 6 weeks** with a small team. The hard parts (crypto, protocol, clients) already exist in SimpleX.

6. **OpenClaw as infrastructure agent** is a genuinely novel angle — AI agents that both run and use the messaging infrastructure.

### Key Risk:
SimpleX team may not welcome a fork or competing relay network. Best approach: contribute upstream. Propose the community relay directory as an enhancement to SimpleX itself.

---

*Sources: SimpleX Chat GitHub (simplex-chat/simplex-chat, simplex-chat/simplexmq), simplex.chat docs, freedomnode.com comparison, Reddit r/privacy discussions, Crunchbase/Dealroom funding data, SimpleX blog posts (2023-2024).*
