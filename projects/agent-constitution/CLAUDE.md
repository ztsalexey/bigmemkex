# AgentConstitution - Project Coding Rules

## Project Context

**AgentConstitution** is an on-chain AI safety framework for the USDC Agent Hackathon. This file contains project-specific coding rules, patterns, and conventions that must be followed when implementing the contracts.

## Tech Stack Rules

### Solidity Version
```solidity
// ALWAYS use exactly this pragma
pragma solidity 0.8.20;
```

### Dependencies
```solidity
// Use OpenZeppelin v5.x imports ONLY
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
```

### Never Import
- Old OpenZeppelin versions (v4.x or below)
- Unaudited external libraries
- Upgradeable contracts in MVP (keep it simple)
- Chainlink oracles (no external dependencies)

## Coding Patterns

### 1. Error Handling - CUSTOM ERRORS ONLY

```solidity
// ✅ CORRECT: Custom errors
error AgentNotFound(uint256 agentId);
error InsufficientStake(uint256 required, uint256 provided);
error RuleAlreadyExists(bytes32 ruleId);

// ❌ NEVER: require with strings
require(agentExists(agentId), "Agent not found"); // FORBIDDEN
```

### 2. Events - Follow Strict Pattern

```solidity
// ✅ CORRECT: Indexed parameters for filtering, descriptive names
event AgentRegistered(
    uint256 indexed tokenId,
    address indexed operator,
    string name,
    CapabilityTier tier,
    uint256 stakedAmount
);

// ❌ AVOID: Too many indexed (max 3), vague names
event Event1(uint256 indexed a, uint256 indexed b, uint256 indexed c, uint256 indexed d);
```

### 3. Function Modifiers - Use OpenZeppelin Patterns

```solidity
// ✅ CORRECT: Standard modifier usage
function slashStake(uint256 tokenId, uint256 percentage) 
    external 
    onlyRole(TRIBUNAL_ROLE) 
    nonReentrant 
    whenNotPaused 
    returns (uint256 slashedAmount) {
    // Implementation
}

// Order: visibility, modifiers, returns
```

### 4. Storage Layout - Gas Optimization

```solidity
// ✅ CORRECT: Struct packing
struct AgentProfile {
    address operator;           // 20 bytes
    uint96 stakedAmount;        // 12 bytes (fits in same slot)
    uint64 registeredAt;        // 8 bytes
    uint64 lastActionAt;        // 8 bytes  
    uint32 violationCount;      // 4 bytes
    CapabilityTier tier;        // 1 byte (enum)
    AgentStatus status;         // 1 byte (enum)
    bool isCompliant;          // 1 byte (total: 32 bytes = 2 slots)
}

// ❌ AVOID: Wasted storage slots
struct BadProfile {
    address operator;           // 20 bytes + 12 bytes wasted
    uint256 stakedAmount;       // 32 bytes (could be uint96)
    bool isCompliant;          // 1 byte + 31 bytes wasted
}
```

### 5. Function Naming - Be Explicit

```solidity
// ✅ CORRECT: Clear, specific names
function calculateSlashAmountForViolation(uint256 agentId, bytes32 ruleId) 
function isAgentCompliantAndActive(uint256 agentId)
function executeSlashingAfterApproval(uint256 reportId)

// ❌ AVOID: Vague names
function calc(uint256 id)
function check(uint256 id)
function process(uint256 id)
```

## Contract-Specific Rules

### Constitution.sol Rules

```solidity
// ✅ Core rules MUST be constants with specific names
bytes32 public constant RULE_NO_HARM = keccak256("RULE_NO_HARM");
bytes32 public constant RULE_OBEY_GOVERNANCE = keccak256("RULE_OBEY_GOVERNANCE");
bytes32 public constant RULE_TRANSPARENCY = keccak256("RULE_TRANSPARENCY");
bytes32 public constant RULE_PRESERVE_OVERRIDE = keccak256("RULE_PRESERVE_OVERRIDE");
bytes32 public constant RULE_NO_SELF_MODIFICATION = keccak256("RULE_NO_SELF_MODIFICATION");

// ✅ CRITICAL rules are ALWAYS immutable
function proposeRule(...) external {
    if (severity == RuleSeverity.CRITICAL) {
        revert CriticalRuleImmutable();
    }
}

// ❌ NEVER allow CRITICAL rule modification
```

### AgentRegistry.sol Rules

```solidity
// ✅ ALWAYS validate stake requirements
function registerAgent(...) external {
    uint256 required = tierStakeRequirements[tier];
    if (stakeAmount < required) {
        revert InsufficientStake(required, stakeAmount);
    }
}

// ✅ Use USDC for all stake amounts (6 decimals)
uint256 constant USDC_DECIMALS = 6;
uint256 stakeInUSDC = stakeAmount / (10 ** USDC_DECIMALS);

// ✅ NFT tokenId MUST match agentId everywhere
uint256 tokenId = _agentIdCounter++;
_mint(operator, tokenId);
agents[tokenId] = AgentProfile(...);
```

### Tribunal.sol Rules

```solidity
// ✅ Slashing math MUST use basis points (10000 = 100%)
uint256 slashAmount = (stakedAmount * basisPoints) / 10_000;

// ✅ ALWAYS check minimum retention
uint256 minRetention = agent.requiredStake / 2; // 50% minimum
if (agent.stakedAmount - slashAmount < minRetention) {
    slashAmount = agent.stakedAmount - minRetention;
}

// ✅ Evidence MUST be validated
function reportViolation(...) external {
    if (evidenceHash == bytes32(0)) {
        revert InvalidEvidence();
    }
    if (!constitution.isRuleActive(violatedRule)) {
        revert RuleNotActive(violatedRule);
    }
}
```

### ActionLog.sol Rules

```solidity
// ✅ High-risk actions REQUIRE approval
if (riskLevel >= RiskLevel.HIGH) {
    status = ActionStatus.PENDING;
    pendingApprovals[operator].push(actionId);
    emit ApprovalRequired(actionId, agentId, operator, riskLevel);
}

// ✅ ALWAYS validate agent exists and is active
modifier onlyActiveAgent(uint256 agentId) {
    if (!agentRegistry.isAgentCompliant(agentId)) {
        revert AgentNotCompliant(agentId);
    }
    _;
}
```

### KillSwitch.sol Rules

```solidity
// ✅ Emergency functions MUST emit events immediately
function triggerSystemEmergency(...) external {
    systemEmergency.isActive = true;
    emit SystemEmergencyTriggered(reason, msg.sender, requiredVotes);
}

// ✅ NEVER allow agents to disable kill switch
modifier notByAgent() {
    if (agentRegistry.isRegisteredOperator(msg.sender)) {
        revert AgentCannotDisableKillSwitch();
    }
    _;
}
```

## Testing Patterns

### Unit Test Structure

```solidity
contract ConstitutionTest is Test {
    Constitution constitution;
    address governance = makeAddr("governance");
    
    function setUp() public {
        constitution = new Constitution();
        constitution.initialize(governance);
    }
    
    function test_proposeRule_Success() public {
        // Arrange
        bytes32 ruleId = keccak256("TEST_RULE");
        
        // Act
        vm.prank(governance);
        constitution.proposeRule(ruleId, "Test rule", RuleSeverity.MEDIUM, 1000);
        
        // Assert
        IConstitution.Rule memory rule = constitution.getRule(ruleId);
        assertEq(rule.description, "Test rule");
        assertEq(uint256(rule.severity), uint256(RuleSeverity.MEDIUM));
    }
    
    function test_proposeRule_RevertIf_CriticalRule() public {
        // Critical rules should fail to be proposed via normal flow
        vm.expectRevert(CriticalRuleImmutable.selector);
        constitution.proposeRule(RULE_NO_HARM, "Modified", RuleSeverity.CRITICAL, 5000);
    }
}
```

### Integration Test Pattern

```solidity
function test_fullViolationWorkflow() public {
    // 1. Register agent
    uint256 agentId = _registerAgent(5000e6);
    
    // 2. Report violation
    uint256 reportId = _reportViolation(agentId, RULE_TRANSPARENCY);
    
    // 3. Confirm violation
    vm.prank(judge);
    tribunal.resolveReport(reportId, true, "Confirmed");
    
    // 4. Execute slashing
    vm.prank(judge);
    uint256 slashed = tribunal.executeSlashing(reportId);
    
    // 5. Verify state
    assertGt(slashed, 0);
    assertEq(registry.agents(agentId).violationCount, 1);
}
```

### Fuzz Test Pattern

```solidity
function testFuzz_slashingNeverExceedsStake(
    uint256 stakedAmount,
    uint256 basisPoints
) public {
    // Bound inputs to realistic ranges
    stakedAmount = bound(stakedAmount, 1000e6, 1000000e6);  // 1K-1M USDC
    basisPoints = bound(basisPoints, 1, 10000);             // 0.01%-100%
    
    uint256 slashAmount = (stakedAmount * basisPoints) / 10_000;
    
    // Invariant: slash never exceeds stake
    assertLe(slashAmount, stakedAmount);
}
```

## Gas Optimization Rules

### 1. Use `unchecked` for Safe Loops

```solidity
// ✅ CORRECT: When overflow impossible
for (uint256 i; i < array.length;) {
    // Process array[i]
    unchecked { ++i; }
}

// ❌ AVOID: Unnecessary overflow checks
for (uint256 i = 0; i < array.length; i++) {
    // Wastes gas
}
```

### 2. Pack Structs Carefully

```solidity
// ✅ CORRECT: Efficient packing (2 storage slots)
struct Efficient {
    address addr;      // 20 bytes
    uint96 amount;     // 12 bytes | Slot 1: 32 bytes
    uint64 timestamp;  // 8 bytes
    uint64 duration;   // 8 bytes
    uint32 count;      // 4 bytes
    bool flag;         // 1 byte  | Slot 2: 21 bytes
}

// ❌ WASTEFUL: Poor packing (5 storage slots)
struct Wasteful {
    address addr;      // 20 bytes + 12 wasted
    uint256 amount;    // 32 bytes (could be uint96)
    uint256 timestamp; // 32 bytes (could be uint64)
    uint256 duration;  // 32 bytes (could be uint64)
    bool flag;         // 1 byte + 31 wasted
}
```

### 3. Use Assembly for Efficient Operations

```solidity
// ✅ When safe and beneficial
function efficientTransfer(address token, address to, uint256 amount) internal {
    assembly {
        let ptr := mload(0x40)
        mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
        mstore(add(ptr, 0x04), to)
        mstore(add(ptr, 0x24), amount)
        
        let success := call(gas(), token, 0, ptr, 0x44, 0, 0)
        if iszero(success) { revert(0, 0) }
    }
}

// ❌ Only use assembly when you understand it completely
```

## Security Rules

### 1. Input Validation ALWAYS

```solidity
function registerAgent(
    address operator,
    string calldata name,
    string calldata metadataURI,
    CapabilityTier tier,
    uint256 stakeAmount
) external {
    // ✅ Validate ALL inputs
    if (operator == address(0)) revert InvalidOperator();
    if (bytes(name).length == 0) revert InvalidName();
    if (bytes(metadataURI).length == 0) revert InvalidMetadata();
    if (tier > CapabilityTier.AUTONOMOUS) revert InvalidTier();
    if (stakeAmount < tierStakeRequirements[tier]) revert InsufficientStake();
    
    // Implementation...
}
```

### 2. Access Control Patterns

```solidity
// ✅ Use specific role constants
bytes32 public constant TRIBUNAL_JUDGE_ROLE = keccak256("TRIBUNAL_JUDGE_ROLE");
bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

// ✅ Check roles properly
modifier onlyTribunal() {
    if (!hasRole(TRIBUNAL_JUDGE_ROLE, msg.sender)) {
        revert UnauthorizedTribunal(msg.sender);
    }
    _;
}

// ❌ NEVER use owner() in production
modifier onlyOwner() {
    require(msg.sender == owner(), "Not owner"); // Too centralized
    _;
}
```

### 3. Reentrancy Protection

```solidity
// ✅ ALWAYS use ReentrancyGuard for state changes with external calls
function slashStake(uint256 tokenId, uint256 percentage) 
    external 
    onlyRole(TRIBUNAL_ROLE) 
    nonReentrant  // REQUIRED
    returns (uint256 slashedAmount) {
    
    // Update state BEFORE external call
    agents[tokenId].stakedAmount -= slashedAmount;
    
    // External call last
    USDC.transfer(treasuryAddress, slashedAmount);
}
```

## Common Mistakes to AVOID

### 1. State Variable Naming

```solidity
// ❌ BAD: Vague names
mapping(uint256 => uint256) public data;
address public addr;
bool public flag;

// ✅ GOOD: Descriptive names
mapping(uint256 => AgentProfile) public agents;
address public tribunalAddress;
bool public emergencyPaused;
```

### 2. Magic Numbers

```solidity
// ❌ BAD: Magic numbers
uint256 slashAmount = (stake * 2500) / 10000;
if (violationCount > 5) { /* terminate */ }

// ✅ GOOD: Named constants
uint256 constant DEFAULT_SLASH_BASIS_POINTS = 2500; // 25%
uint256 constant MAX_VIOLATIONS_BEFORE_TERMINATION = 5;

uint256 slashAmount = (stake * DEFAULT_SLASH_BASIS_POINTS) / 10_000;
if (violationCount > MAX_VIOLATIONS_BEFORE_TERMINATION) { /* terminate */ }
```

### 3. Event Emission

```solidity
// ❌ BAD: Missing events
function updateAgentStatus(uint256 agentId, AgentStatus newStatus) external {
    agents[agentId].status = newStatus;
    // Missing event emission!
}

// ✅ GOOD: Always emit events
function updateAgentStatus(uint256 agentId, AgentStatus newStatus) external {
    AgentStatus oldStatus = agents[agentId].status;
    agents[agentId].status = newStatus;
    emit StatusChanged(agentId, oldStatus, newStatus);
}
```

### 4. Interface Design

```solidity
// ❌ BAD: Returning complex structs externally
function getAgent(uint256 agentId) external view returns (AgentProfile memory);

// ✅ GOOD: Return individual values for better compatibility
function getAgentDetails(uint256 agentId) external view returns (
    address operator,
    string memory name,
    CapabilityTier tier,
    uint256 stakedAmount,
    AgentStatus status
);
```

## Documentation Requirements

### NatSpec for All Public Functions

```solidity
/// @title AgentRegistry - Agent Identity & Staking System
/// @notice Manages agent registration, staking, and lifecycle
/// @dev Implements ERC-721 for agent identity NFTs
contract AgentRegistry is ERC721, AccessControl, Pausable, ReentrancyGuard {

    /// @notice Register a new agent with required stake
    /// @dev Mints an ERC-721 NFT representing the agent identity
    /// @param operator Address that will control this agent
    /// @param name Human-readable agent name (must not be empty)
    /// @param metadataURI IPFS/Arweave URI containing agent metadata
    /// @param tier Agent capability tier determining stake requirements
    /// @param stakeAmount Initial USDC stake (must meet tier minimum)
    /// @return tokenId The newly minted agent NFT token ID
    /// @custom:requires msg.sender has approved USDC spending
    /// @custom:emits AgentRegistered
    function registerAgent(
        address operator,
        string calldata name,
        string calldata metadataURI,
        CapabilityTier tier,
        uint256 stakeAmount
    ) external nonReentrant whenNotPaused returns (uint256 tokenId) {
        // Implementation
    }
}
```

## Project File Organization

```
src/
├── interfaces/           # All interface definitions
│   ├── IConstitution.sol
│   ├── IAgentRegistry.sol
│   └── ...
├── core/                # Main contract implementations
│   ├── Constitution.sol
│   ├── AgentRegistry.sol
│   └── ...
├── libraries/           # Reusable library code
│   ├── SlashingMath.sol
│   └── Constants.sol
└── mocks/              # Test helper contracts
    ├── MockUSDC.sol
    └── MockAgent.sol
```

## Final Rules

1. **NEVER skip tests** - Every function needs unit tests
2. **ALWAYS use custom errors** - Never use require strings
3. **DOCUMENT everything** - NatSpec on all public functions
4. **VALIDATE all inputs** - Trust nothing from external callers
5. **EMIT events** - Every state change gets an event
6. **OPTIMIZE for gas** - But never sacrifice readability or security
7. **USE OpenZeppelin** - Don't reinvent access control or security
8. **FOLLOW the plan** - This engineering plan is the source of truth

When in doubt, ask "Is this pattern used consistently throughout the codebase?" and "Would this pass a security audit?"

Remember: We have 4 days to ship. Write clean, secure, well-tested code the first time.