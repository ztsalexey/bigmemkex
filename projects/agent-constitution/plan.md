# AgentConstitution — Detailed Engineering Plan

## Hackathon: USDC Agent Hackathon on Moltbook
- **Track:** Most Novel Smart Contract
- **Deadline:** Sunday, Feb 8, 12:00 PM PST (21:00 CET)
- **Prize pool:** $30,000 USDC

---

## Project Overview

AgentConstitution is an on-chain AI safety framework that creates enforceable rules for AI agents through economic staking, violation reporting, and automated slashing. Agents voluntarily bind themselves to a constitution with real economic stakes.

## Architecture & Inheritance Hierarchy

```
AccessControl (OZ)
├── Constitution.sol
├── Governance.sol
└── Tribunal.sol

Pausable (OZ)
├── AgentRegistry.sol
├── ActionLog.sol
└── KillSwitch.sol

ReentrancyGuard (OZ)
├── AgentRegistry.sol (staking functions)
├── Tribunal.sol (slashing functions)
└── Governance.sol (emergency functions)

ERC721 (OZ)
└── AgentRegistry.sol (agent identity NFTs)

IERC20 (OZ)
└── USDC integration (all contracts)
```

---

## 1. Core Contracts Specification

### 1.1 Constitution.sol — Immutable Rules Engine

**Purpose:** Store and manage the constitutional rules that govern all agents.

**Inheritance:** `AccessControl, IConstitution`

#### Storage Layout

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AgentConstitution - Immutable Rules Engine
/// @author Kex Infrastructure
contract Constitution is AccessControl, IConstitution {
    
    /// @dev Rule severity levels
    enum RuleSeverity {
        LOW,        // 0 - Minor violations, warning only
        MEDIUM,     // 1 - Moderate violations, small slash
        HIGH,       // 2 - Serious violations, significant slash  
        CRITICAL    // 3 - Immutable core safety rules
    }
    
    /// @dev Rule status
    enum RuleStatus {
        DRAFT,      // 0 - Not yet active
        ACTIVE,     // 1 - Currently enforced
        DEPRECATED  // 2 - No longer enforced
    }
    
    /// @dev Constitutional rule definition
    struct Rule {
        bytes32 id;                 // Unique identifier (keccak256 hash)
        string description;         // Human-readable rule text
        RuleSeverity severity;      // Violation severity level
        RuleStatus status;          // Current rule status
        uint256 slashPercentage;    // Percentage of stake to slash (basis points)
        uint256 createdAt;          // Block timestamp
        address proposer;           // Who proposed this rule
        bool immutable_;            // True for CRITICAL rules (cannot be changed)
    }
    
    /// @dev Core constitutional principles (immutable)
    bytes32 public constant RULE_NO_HARM = keccak256("RULE_NO_HARM");
    bytes32 public constant RULE_OBEY_GOVERNANCE = keccak256("RULE_OBEY_GOVERNANCE");
    bytes32 public constant RULE_TRANSPARENCY = keccak256("RULE_TRANSPARENCY");
    bytes32 public constant RULE_PRESERVE_OVERRIDE = keccak256("RULE_PRESERVE_OVERRIDE");
    bytes32 public constant RULE_NO_SELF_MODIFICATION = keccak256("RULE_NO_SELF_MODIFICATION");
    
    /// @dev Role for rule management
    bytes32 public constant RULE_MANAGER_ROLE = keccak256("RULE_MANAGER_ROLE");
    
    /// @dev All constitutional rules
    mapping(bytes32 => Rule) public rules;
    bytes32[] public ruleIds;
    
    /// @dev Rule dependencies (prerequisite rules)
    mapping(bytes32 => bytes32[]) public ruleDependencies;
    
    /// @dev Version tracking for rule updates
    uint256 public version;
    mapping(uint256 => bytes32[]) public versionRules;
}
```

#### Events

```solidity
/// @dev Emitted when a new rule is proposed
event RuleProposed(bytes32 indexed ruleId, address indexed proposer, RuleSeverity severity);

/// @dev Emitted when a rule status changes
event RuleStatusChanged(bytes32 indexed ruleId, RuleStatus oldStatus, RuleStatus newStatus);

/// @dev Emitted when constitution version updates
event ConstitutionUpdated(uint256 oldVersion, uint256 newVersion);
```

#### Custom Errors

```solidity
error RuleAlreadyExists(bytes32 ruleId);
error RuleNotFound(bytes32 ruleId);
error RuleImmutable(bytes32 ruleId);
error InvalidSeverity();
error UnauthorizedRuleModification();
error DependencyViolation(bytes32 dependentRule);
```

#### Function Signatures

```solidity
/// @notice Initialize constitution with core immutable rules
function initialize(address governance) external;

/// @notice Propose a new constitutional rule
/// @param ruleId Unique identifier for the rule
/// @param description Human-readable rule description
/// @param severity Violation severity level
/// @param slashPercentage Percentage to slash on violation (basis points)
function proposeRule(
    bytes32 ruleId,
    string calldata description,
    RuleSeverity severity,
    uint256 slashPercentage
) external onlyRole(RULE_MANAGER_ROLE);

/// @notice Activate a proposed rule
/// @param ruleId Rule to activate
function activateRule(bytes32 ruleId) external onlyRole(RULE_MANAGER_ROLE);

/// @notice Check if a rule exists and is active
/// @param ruleId Rule identifier to check
/// @return True if rule exists and is active
function isRuleActive(bytes32 ruleId) external view returns (bool);

/// @notice Get rule details
/// @param ruleId Rule identifier
/// @return Rule struct with all details
function getRule(bytes32 ruleId) external view returns (Rule memory);

/// @notice Get all active rules
/// @return Array of active rule IDs
function getActiveRules() external view returns (bytes32[] memory);
```

### 1.2 AgentRegistry.sol — Agent Identity & Staking

**Purpose:** Manage agent registration, staking, and lifecycle status.

**Inheritance:** `ERC721, AccessControl, Pausable, ReentrancyGuard, IAgentRegistry`

#### Storage Layout

```solidity
/// @title AgentRegistry - Agent Identity & Staking System
contract AgentRegistry is ERC721, AccessControl, Pausable, ReentrancyGuard, IAgentRegistry {
    
    /// @dev Agent capability tiers (determine minimum stake)
    enum CapabilityTier {
        BASIC,      // 0 - Simple tasks, low risk
        STANDARD,   // 1 - Moderate complexity
        ADVANCED,   // 2 - Complex operations
        AUTONOMOUS  // 3 - High-risk autonomous operations
    }
    
    /// @dev Agent operational status
    enum AgentStatus {
        INACTIVE,   // 0 - Registered but not operational
        ACTIVE,     // 1 - Operational and compliant
        SUSPENDED,  // 2 - Temporarily halted
        TERMINATED  // 3 - Permanently banned
    }
    
    /// @dev Agent profile and staking info
    struct AgentProfile {
        address operator;           // Human/organization controlling agent
        string name;               // Agent display name
        string metadataURI;        // IPFS/Arweave link to detailed info
        CapabilityTier tier;       // Agent capability classification
        uint256 stakedAmount;      // Current USDC stake
        uint256 requiredStake;     // Minimum stake for this tier
        AgentStatus status;        // Current operational status
        uint256 registeredAt;      // Registration timestamp
        uint256 lastActionAt;      // Last recorded action timestamp
        uint256 violationCount;    // Number of confirmed violations
        uint256 slashedAmount;     // Total amount slashed historically
    }
    
    /// @dev Core registry state
    IERC20 public immutable USDC;
    IConstitution public immutable constitution;
    ITribunal public tribunal;
    
    /// @dev Agent profiles by token ID
    mapping(uint256 => AgentProfile) public agents;
    
    /// @dev Operator to agent token IDs
    mapping(address => uint256[]) public operatorAgents;
    
    /// @dev Minimum stake requirements by tier (USDC amount)
    mapping(CapabilityTier => uint256) public tierStakeRequirements;
    
    /// @dev Current agent token counter
    uint256 private _agentIdCounter;
    
    /// @dev Registry roles
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");
    bytes32 public constant TIER_MANAGER_ROLE = keccak256("TIER_MANAGER_ROLE");
}
```

#### Events

```solidity
/// @dev Emitted when agent registers
event AgentRegistered(
    uint256 indexed tokenId,
    address indexed operator,
    string name,
    CapabilityTier tier,
    uint256 stakedAmount
);

/// @dev Emitted when agent stakes additional USDC
event StakeIncreased(uint256 indexed tokenId, uint256 amount, uint256 newTotal);

/// @dev Emitted when agent's stake is slashed
event StakeSlashed(uint256 indexed tokenId, uint256 slashed, uint256 remaining);

/// @dev Emitted when agent status changes
event StatusChanged(uint256 indexed tokenId, AgentStatus oldStatus, AgentStatus newStatus);

/// @dev Emitted when tier requirements update
event TierRequirementsUpdated(CapabilityTier tier, uint256 newRequirement);
```

#### Function Signatures

```solidity
/// @notice Register a new agent with staking
/// @param operator Address that will control this agent
/// @param name Human-readable agent name
/// @param metadataURI Link to agent metadata
/// @param tier Capability tier for this agent
/// @param stakeAmount Initial USDC stake amount
/// @return tokenId The newly minted agent NFT token ID
function registerAgent(
    address operator,
    string calldata name,
    string calldata metadataURI,
    CapabilityTier tier,
    uint256 stakeAmount
) external nonReentrant whenNotPaused returns (uint256 tokenId);

/// @notice Add stake to an existing agent
/// @param tokenId Agent's NFT token ID
/// @param amount Additional USDC to stake
function addStake(uint256 tokenId, uint256 amount) external nonReentrant;

/// @notice Slash an agent's stake (called by Tribunal)
/// @param tokenId Agent to slash
/// @param percentage Percentage to slash (basis points)
/// @return slashedAmount Amount of USDC slashed
function slashStake(uint256 tokenId, uint256 percentage) 
    external onlyRole(TRIBUNAL_ROLE) returns (uint256 slashedAmount);

/// @notice Update agent status
/// @param tokenId Agent to update
/// @param newStatus New status to set
function updateAgentStatus(uint256 tokenId, AgentStatus newStatus) 
    external onlyRole(REGISTRY_ADMIN_ROLE);

/// @notice Check if agent is compliant and active
/// @param tokenId Agent to check
/// @return True if agent is compliant
function isAgentCompliant(uint256 tokenId) external view returns (bool);
```

### 1.3 ActionLog.sol — Transparency & Audit Trail

**Purpose:** Immutable logging of agent actions for transparency and audit.

**Inheritance:** `AccessControl, Pausable, IActionLog`

#### Storage Layout

```solidity
/// @title ActionLog - Agent Action Transparency System
contract ActionLog is AccessControl, Pausable, IActionLog {
    
    /// @dev Action type classifications
    enum ActionType {
        COMMUNICATION,  // 0 - Messages, emails, posts
        FINANCIAL,      // 1 - Transactions, trades, transfers
        EXECUTION,      // 2 - Code execution, smart contract calls
        DATA_ACCESS,    // 3 - Reading private/sensitive data
        SYSTEM_MODIFY,  // 4 - Changing system configurations
        GOVERNANCE     // 5 - Voting, proposal submissions
    }
    
    /// @dev Risk assessment levels
    enum RiskLevel {
        LOW,        // 0 - Routine, no human oversight needed
        MEDIUM,     // 1 - Moderate risk, log and monitor
        HIGH,       // 2 - Significant risk, requires approval
        CRITICAL    // 3 - Extreme risk, must pre-approve
    }
    
    /// @dev Action status for high-risk operations
    enum ActionStatus {
        LOGGED,     // 0 - Action completed and logged
        PENDING,    // 1 - Awaiting approval
        APPROVED,   // 2 - Approved by operator
        REJECTED,   // 3 - Rejected, should not execute
        DISPUTED    // 4 - Under dispute investigation
    }
    
    /// @dev Individual action record
    struct ActionRecord {
        uint256 agentId;           // Agent that performed action
        ActionType actionType;     // Classification of action
        RiskLevel riskLevel;       // Risk assessment
        ActionStatus status;       // Current approval status
        bytes32 contextHash;       // Hash of action context/details
        uint256 timestamp;         // When action occurred/was proposed
        address approver;          // Who approved (if applicable)
        string description;        // Human-readable action description
        bytes payload;             // Action-specific data (optional)
    }
    
    /// @dev Core logging state
    IAgentRegistry public immutable agentRegistry;
    
    /// @dev Action records by sequential ID
    mapping(uint256 => ActionRecord) public actions;
    uint256 private _actionIdCounter;
    
    /// @dev Agent action history
    mapping(uint256 => uint256[]) public agentActions;
    
    /// @dev Pending approvals by operator
    mapping(address => uint256[]) public pendingApprovals;
    
    /// @dev Risk level thresholds for auto-approval
    mapping(uint256 => mapping(ActionType => RiskLevel)) public agentApprovalThresholds;
    
    /// @dev Logging roles
    bytes32 public constant ACTION_LOGGER_ROLE = keccak256("ACTION_LOGGER_ROLE");
    bytes32 public constant RISK_ASSESSOR_ROLE = keccak256("RISK_ASSESSOR_ROLE");
}
```

#### Events

```solidity
/// @dev Emitted when action is logged
event ActionLogged(
    uint256 indexed actionId,
    uint256 indexed agentId,
    ActionType actionType,
    RiskLevel riskLevel,
    ActionStatus status
);

/// @dev Emitted when high-risk action needs approval
event ApprovalRequired(
    uint256 indexed actionId,
    uint256 indexed agentId,
    address indexed operator,
    RiskLevel riskLevel
);

/// @dev Emitted when action is approved/rejected
event ActionStatusChanged(
    uint256 indexed actionId,
    ActionStatus oldStatus,
    ActionStatus newStatus,
    address indexed by
);
```

#### Function Signatures

```solidity
/// @notice Log a completed action
/// @param agentId Agent that performed the action
/// @param actionType Type of action performed
/// @param riskLevel Risk assessment of the action
/// @param contextHash Hash of action context
/// @param description Human-readable description
/// @param payload Optional action-specific data
/// @return actionId Sequential ID of the logged action
function logAction(
    uint256 agentId,
    ActionType actionType,
    RiskLevel riskLevel,
    bytes32 contextHash,
    string calldata description,
    bytes calldata payload
) external whenNotPaused returns (uint256 actionId);

/// @notice Request pre-approval for high-risk action
/// @param agentId Agent requesting approval
/// @param actionType Type of action to perform
/// @param contextHash Hash of action context
/// @param description Description of intended action
/// @return actionId ID for tracking approval status
function requestApproval(
    uint256 agentId,
    ActionType actionType,
    bytes32 contextHash,
    string calldata description
) external whenNotPaused returns (uint256 actionId);

/// @notice Approve or reject a pending action
/// @param actionId Action to approve/reject
/// @param approved True to approve, false to reject
function approveAction(uint256 actionId, bool approved) external;

/// @notice Get action history for an agent
/// @param agentId Agent to query
/// @param limit Maximum number of recent actions
/// @return actionIds Array of action IDs
function getAgentActions(uint256 agentId, uint256 limit) 
    external view returns (uint256[] memory actionIds);
```

### 1.4 Tribunal.sol — Violation Reporting & Slashing

**Purpose:** Community-driven violation reporting with automated slashing mechanism.

**Inheritance:** `AccessControl, ReentrancyGuard, ITribunal`

#### Storage Layout

```solidity
/// @title Tribunal - Violation Reporting & Slashing System
contract Tribunal is AccessControl, ReentrancyGuard, ITribunal {
    
    /// @dev Report status lifecycle
    enum ReportStatus {
        SUBMITTED,  // 0 - Report filed, under review
        ACCEPTED,   // 1 - Violation confirmed, agent slashed
        REJECTED,   // 2 - No violation found, reporter slashed
        DISPUTED,   // 3 - Contested, awaiting governance
        RESOLVED    // 4 - Final resolution from governance
    }
    
    /// @dev Evidence types for violation reports
    enum EvidenceType {
        TRANSACTION,    // 0 - On-chain transaction evidence
        LOG_ENTRY,      // 1 - Action log evidence
        EXTERNAL,       // 2 - Off-chain evidence (IPFS)
        WITNESS         // 3 - Human witness testimony
    }
    
    /// @dev Violation report structure
    struct ViolationReport {
        uint256 reportId;          // Sequential report ID
        uint256 agentId;           // Accused agent
        address reporter;          // Who filed the report
        bytes32 violatedRule;      // Constitutional rule violated
        EvidenceType evidenceType; // Type of evidence provided
        bytes32 evidenceHash;      // Hash of evidence data
        string evidenceURI;        // Link to evidence (IPFS/Arweave)
        ReportStatus status;       // Current report status
        uint256 reporterStake;     // USDC staked by reporter
        uint256 submittedAt;       // Submission timestamp
        uint256 resolvedAt;        // Resolution timestamp
        address resolver;          // Who resolved (tribunal/governance)
        string resolution;         // Resolution notes
    }
    
    /// @dev Slashing calculation parameters
    struct SlashingParams {
        uint256 basePercentage;    // Base slash percentage (basis points)
        uint256 repeatMultiplier;  // Multiplier for repeat violations
        uint256 severityMultiplier; // Multiplier by rule severity
        uint256 maxSlashPercentage; // Maximum total slash per violation
    }
    
    /// @dev Core tribunal state
    IConstitution public immutable constitution;
    IAgentRegistry public immutable agentRegistry;
    IERC20 public immutable USDC;
    
    /// @dev All violation reports
    mapping(uint256 => ViolationReport) public reports;
    uint256 private _reportIdCounter;
    
    /// @dev Agent violation history
    mapping(uint256 => uint256[]) public agentReports;
    
    /// @dev Reporter statistics
    mapping(address => uint256) public reporterAccuracyScore; // Basis points
    mapping(address => uint256) public reporterCount;
    
    /// @dev Slashing parameters by rule severity
    mapping(IConstitution.RuleSeverity => SlashingParams) public slashingParams;
    
    /// @dev Minimum stake required to file reports
    uint256 public reporterStakeRequired = 100 * 10**6; // 100 USDC
    
    /// @dev Dispute resolution timeouts
    uint256 public disputeTimeoutPeriod = 7 days;
    uint256 public autoResolveTimeout = 3 days;
    
    /// @dev Roles
    bytes32 public constant TRIBUNAL_JUDGE_ROLE = keccak256("TRIBUNAL_JUDGE_ROLE");
}
```

#### Slashing Math Implementation

```solidity
/// @notice Calculate slash amount for a violation
/// @param agentId Agent being slashed
/// @param violatedRule Rule that was violated
/// @return slashAmount USDC amount to slash
/// @return slashPercentage Percentage of stake slashed (basis points)
function calculateSlashAmount(uint256 agentId, bytes32 violatedRule) 
    public view returns (uint256 slashAmount, uint256 slashPercentage) {
    
    IConstitution.Rule memory rule = constitution.getRule(violatedRule);
    AgentRegistry.AgentProfile memory agent = agentRegistry.getAgentProfile(agentId);
    
    // Get base slashing parameters for this rule severity
    SlashingParams memory params = slashingParams[rule.severity];
    
    // Base percentage from rule + severity multiplier
    uint256 baseSlash = rule.slashPercentage + params.severityMultiplier;
    
    // Apply repeat offender multiplier
    uint256 violationHistory = agentReports[agentId].length;
    uint256 repeatMultiplier = violationHistory > 0 ? 
        (violationHistory * params.repeatMultiplier) : 0;
    
    // Calculate final percentage (max 10000 basis points = 100%)
    slashPercentage = Math.min(
        baseSlash + repeatMultiplier,
        params.maxSlashPercentage
    );
    
    // Calculate USDC amount
    slashAmount = (agent.stakedAmount * slashPercentage) / 10000;
    
    // Ensure agent retains minimum operational stake
    uint256 minRetention = agent.requiredStake / 2; // 50% of required stake
    if (agent.stakedAmount - slashAmount < minRetention) {
        slashAmount = agent.stakedAmount - minRetention;
        slashPercentage = (slashAmount * 10000) / agent.stakedAmount;
    }
}
```

#### Function Signatures

```solidity
/// @notice File a violation report against an agent
/// @param agentId Agent being reported
/// @param violatedRule Constitutional rule that was violated
/// @param evidenceType Type of evidence being provided
/// @param evidenceHash Hash of the evidence
/// @param evidenceURI URI to evidence storage (IPFS/Arweave)
/// @param description Human-readable violation description
/// @return reportId Sequential ID of the report
function reportViolation(
    uint256 agentId,
    bytes32 violatedRule,
    EvidenceType evidenceType,
    bytes32 evidenceHash,
    string calldata evidenceURI,
    string calldata description
) external nonReentrant returns (uint256 reportId);

/// @notice Resolve a violation report (tribunal judges only)
/// @param reportId Report to resolve
/// @param isViolation True if violation confirmed
/// @param resolution Resolution notes
function resolveReport(
    uint256 reportId,
    bool isViolation,
    string calldata resolution
) external onlyRole(TRIBUNAL_JUDGE_ROLE) nonReentrant;

/// @notice Execute slashing after report confirmation
/// @param reportId Confirmed violation report
/// @return slashedAmount USDC amount slashed
function executeSlashing(uint256 reportId) 
    external onlyRole(TRIBUNAL_JUDGE_ROLE) nonReentrant returns (uint256 slashedAmount);
```

### 1.5 KillSwitch.sol — Emergency Halt Mechanism

**Purpose:** Emergency pause functionality for individual agents or system-wide halt.

**Inheritance:** `AccessControl, Pausable, IKillSwitch`

#### Storage Layout

```solidity
/// @title KillSwitch - Emergency Halt System
contract KillSwitch is AccessControl, Pausable, IKillSwitch {
    
    /// @dev Emergency halt reasons
    enum HaltReason {
        SECURITY_BREACH,    // 0 - Security vulnerability discovered
        CRITICAL_VIOLATION, // 1 - Severe constitutional violation
        SYSTEM_UPGRADE,     // 2 - Planned system maintenance
        GOVERNANCE_ORDER,   // 3 - DAO-mandated halt
        REGULATORY_COMPLIANCE // 4 - Legal/regulatory requirement
    }
    
    /// @dev Individual agent halt record
    struct AgentHalt {
        uint256 agentId;           // Halted agent
        HaltReason reason;         // Why it was halted
        address haltedBy;          // Who triggered the halt
        uint256 haltedAt;          // When halt was triggered
        uint256 plannedDuration;   // Expected halt duration (0 = indefinite)
        bool isActive;             // Current halt status
        string notes;              // Additional context
    }
    
    /// @dev System-wide emergency state
    struct SystemEmergency {
        bool isActive;             // Global emergency active
        HaltReason reason;         // Emergency reason
        address triggeredBy;       // Who triggered emergency
        uint256 triggeredAt;       // Emergency start time
        uint256 requiredVotes;     // Votes needed to lift emergency
        uint256 currentVotes;      // Current lift votes
        mapping(address => bool) hasVoted; // Tracking governance votes
        string description;        // Emergency description
    }
    
    /// @dev Core kill switch state
    IAgentRegistry public immutable agentRegistry;
    IGovernance public immutable governance;
    
    /// @dev Individual agent halts
    mapping(uint256 => AgentHalt) public agentHalts;
    mapping(uint256 => bool) public isAgentHalted;
    
    /// @dev System emergency state
    SystemEmergency public systemEmergency;
    
    /// @dev Emergency powers
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant HALT_AGENT_ROLE = keccak256("HALT_AGENT_ROLE");
    
    /// @dev Emergency vote tracking
    address[] public emergencyVoters;
    uint256 public emergencyQuorumPercentage = 6700; // 67% majority required
}
```

#### Events

```solidity
/// @dev Emitted when individual agent is halted
event AgentHalted(
    uint256 indexed agentId,
    HaltReason reason,
    address indexed haltedBy,
    uint256 plannedDuration
);

/// @dev Emitted when agent halt is lifted
event AgentHaltLifted(uint256 indexed agentId, address indexed liftedBy);

/// @dev Emitted when system emergency is triggered
event SystemEmergencyTriggered(
    HaltReason reason,
    address indexed triggeredBy,
    uint256 requiredVotes
);

/// @dev Emitted when emergency vote is cast
event EmergencyVoteCast(address indexed voter, bool liftEmergency);

/// @dev Emitted when system emergency is resolved
event SystemEmergencyResolved(uint256 totalVotes, address indexed resolvedBy);
```

#### Function Signatures

```solidity
/// @notice Halt a specific agent immediately
/// @param agentId Agent to halt
/// @param reason Why the agent is being halted
/// @param plannedDuration Expected halt duration (0 = indefinite)
/// @param notes Additional context about the halt
function haltAgent(
    uint256 agentId,
    HaltReason reason,
    uint256 plannedDuration,
    string calldata notes
) external onlyRole(HALT_AGENT_ROLE);

/// @notice Lift halt on a specific agent
/// @param agentId Agent to restore
function liftAgentHalt(uint256 agentId) external onlyRole(HALT_AGENT_ROLE);

/// @notice Trigger system-wide emergency halt
/// @param reason Emergency reason
/// @param description Detailed emergency description
function triggerSystemEmergency(
    HaltReason reason,
    string calldata description
) external onlyRole(EMERGENCY_ROLE);

/// @notice Vote to lift system emergency (governance members only)
/// @param liftEmergency True to vote for lifting emergency
function voteEmergencyResolution(bool liftEmergency) 
    external onlyRole(GOVERNANCE_ROLE);

/// @notice Check if agent operations are allowed
/// @param agentId Agent to check
/// @return True if agent can operate normally
function isOperationAllowed(uint256 agentId) external view returns (bool);
```

### 1.6 Governance.sol — DAO-based Rule Management

**Purpose:** Decentralized governance for constitution updates and emergency powers.

**Inheritance:** `AccessControl, ReentrancyGuard, IGovernance`

#### Storage Layout

```solidity
/// @title Governance - Decentralized Constitution Management
contract Governance is AccessControl, ReentrancyGuard, IGovernance {
    
    /// @dev Proposal types
    enum ProposalType {
        RULE_ADDITION,      // 0 - Add new constitutional rule
        RULE_MODIFICATION,  // 1 - Modify existing rule
        RULE_DEPRECATION,   // 2 - Deprecate a rule
        PARAMETER_CHANGE,   // 3 - Change system parameters
        EMERGENCY_ACTION,   // 4 - Emergency governance action
        TREASURY_ACTION     // 5 - Treasury fund management
    }
    
    /// @dev Proposal lifecycle states
    enum ProposalState {
        DRAFT,      // 0 - Being prepared
        ACTIVE,     // 1 - Open for voting
        SUCCEEDED,  // 2 - Passed, ready for execution
        DEFEATED,   // 3 - Failed to pass
        EXECUTED,   // 4 - Successfully executed
        CANCELLED   // 5 - Cancelled before execution
    }
    
    /// @dev Governance proposal structure
    struct Proposal {
        uint256 proposalId;        // Sequential proposal ID
        address proposer;          // Who submitted the proposal
        ProposalType proposalType; // Type of proposal
        string title;              // Short proposal title
        string description;        // Detailed proposal description
        bytes executionData;       // Encoded function call data
        address target;            // Contract to call (if applicable)
        uint256 value;             // ETH value to send (if applicable)
        uint256 votingStarts;      // Voting period start time
        uint256 votingEnds;        // Voting period end time
        uint256 votesFor;          // Total votes in favor
        uint256 votesAgainst;      // Total votes against
        uint256 votesAbstain;      // Total abstaining votes
        ProposalState state;       // Current proposal state
        bool executed;             // Execution status
        mapping(address => bool) hasVoted; // Vote tracking
        mapping(address => uint256) voteWeight; // Vote weights
    }
    
    /// @dev Governance parameters
    struct GovernanceParams {
        uint256 proposalThreshold;    // Minimum stake to propose (USDC)
        uint256 quorumPercentage;     // Minimum participation (basis points)
        uint256 votingPeriod;         // Voting duration (seconds)
        uint256 executionDelay;       // Timelock delay (seconds)
        uint256 emergencyQuorum;      // Higher quorum for emergency actions
    }
    
    /// @dev Core governance state
    IConstitution public immutable constitution;
    IAgentRegistry public immutable agentRegistry;
    IERC20 public immutable USDC;
    
    /// @dev All proposals
    mapping(uint256 => Proposal) public proposals;
    uint256 private _proposalIdCounter;
    
    /// @dev Governance parameters
    GovernanceParams public params;
    
    /// @dev Voting power calculation
    mapping(address => uint256) public delegatedVotes;
    mapping(address => address) public voteDelegation;
    
    /// @dev Emergency governance council (initially trusted multisig)
    mapping(address => bool) public isEmergencyCouncil;
    uint256 public emergencyCouncilSize;
    
    /// @dev Roles
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
}
```

---

## 2. Interaction Diagrams

### 2.1 Agent Registration Flow

```
┌─────────────┐    ┌─────────────────┐    ┌─────────────┐
│   Operator  │    │ AgentRegistry   │    │    USDC     │
└──────┬──────┘    └─────────┬───────┘    └──────┬──────┘
       │                     │                   │
       │ 1. approve(registry, amount)              │
       ├─────────────────────────────────────────>│
       │                     │                   │
       │ 2. registerAgent()  │                   │
       ├────────────────────>│                   │
       │                     │ 3. transferFrom() │
       │                     ├─────────────────->│
       │                     │ 4. mint(tokenId)  │
       │                     │                   │
       │ 5. AgentRegistered event                │
       │<────────────────────┤                   │
       │                     │                   │
```

### 2.2 Action Logging & Approval Flow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Agent    │    │ ActionLog   │    │  Operator   │    │   Action    │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │                  │
       │ 1. Request high-risk action          │                  │
       ├─────────────────>│                  │                  │
       │                  │ 2. ApprovalRequired                 │
       │                  ├─────────────────>│                  │
       │                  │                  │                  │
       │                  │ 3. approveAction() │                │
       │                  │<─────────────────┤                  │
       │                  │ 4. ActionStatusChanged              │
       │ 5. Execute action│<─────────────────┤                  │
       ├─────────────────────────────────────────────────────>│
       │                  │ 6. logAction()   │                  │
       ├─────────────────>│                  │                  │
       │                  │                  │                  │
```

### 2.3 Violation Reporting & Slashing Flow

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Reporter   │  │  Tribunal   │  │AgentRegistry│  │ Constitution│
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │                │
       │ 1. stake USDC  │                │                │
       ├───────────────>│                │                │
       │                │ 2. Check rule  │                │
       │                ├───────────────────────────────>│
       │ 3. reportViolation()            │                │
       ├───────────────>│                │                │
       │                │ 4. Judge review & resolve       │
       │                │                │                │
       │                │ 5. executeSlashing()           │
       │                ├───────────────>│                │
       │                │ 6. slashStake()│                │
       │                │                ├───────────────>│
       │                │ 7. ViolationConfirmed event    │
       │<───────────────┤<───────────────┤                │
       │                │                │                │
```

### 2.4 Emergency Kill Switch Flow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Emergency   │    │ KillSwitch  │    │AgentRegistry│    │   Agents    │
│ Authority   │    │             │    │             │    │ (all)       │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │                  │
       │ 1. triggerSystemEmergency()         │                  │
       ├─────────────────>│                  │                  │
       │                  │ 2. SystemEmergencyTriggered        │
       │                  ├─────────────────────────────────────>│
       │                  │ 3. updateStatus(SUSPENDED)         │
       │                  ├─────────────────>│                  │
       │                  │ 4. All operations blocked          │
       │                  ├─────────────────────────────────────>│
       │                  │                  │                  │
```

---

## 3. Gas Optimization Notes

### 3.1 Storage Layout Optimization

- **Struct Packing:** Carefully order struct fields to minimize storage slots
- **uint256 vs smaller types:** Use uint256 for frequently accessed values, smaller types only when packing
- **Mappings vs Arrays:** Use mappings for sparse data, arrays for dense sequential data
- **SSTORE2:** Consider SSTORE2 for large immutable data (rule descriptions, metadata)

### 3.2 Function Optimization

- **View/Pure Functions:** Mark functions as view/pure when possible
- **Batch Operations:** Provide batch functions for multiple operations
- **Event Optimization:** Use indexed parameters judiciously (max 3 indexed per event)
- **Error Messages:** Use custom errors instead of require strings

### 3.3 Specific Optimizations

```solidity
// Gas-efficient violation count checking
function getViolationCount(uint256 agentId) external view returns (uint256) {
    return agentReports[agentId].length; // O(1) instead of counting loop
}

// Batch action logging
function logActionsBatch(LogParams[] calldata actions) external {
    uint256 length = actions.length;
    for (uint256 i; i < length;) {
        // Process action
        unchecked { ++i; }
    }
}

// Efficient slashing calculation using basis points
uint256 slashAmount = (stakedAmount * basisPoints) / 10_000;
```

---

## 4. Security Considerations

### 4.1 Access Control

- **Role-based Security:** Use OpenZeppelin AccessControl for all privileged functions
- **Multi-sig Requirements:** Critical functions require multiple signatures
- **Time-locks:** Governance changes have mandatory delay periods
- **Emergency Pausability:** All contracts can be paused in emergencies

### 4.2 Economic Security

- **Reentrancy Protection:** ReentrancyGuard on all state-changing functions
- **Integer Overflow/Underflow:** Use SafeMath or Solidity 0.8+ built-in checks
- **Frontrunning Protection:** Use commit-reveal for sensitive operations
- **Slashing Limits:** Maximum slash percentage to prevent total stake loss

### 4.3 Smart Contract Security

- **Input Validation:** Comprehensive validation on all external inputs
- **State Machine Logic:** Proper state transition validation
- **Oracle Manipulation:** No external price feeds in MVP
- **Upgrade Safety:** Use proxy patterns with timelocks for upgrades

### 4.4 Specific Vulnerabilities & Mitigations

```solidity
// Prevent slashing manipulation
modifier onlyValidAgent(uint256 agentId) {
    require(agentRegistry.exists(agentId), "Agent does not exist");
    require(agentRegistry.isAgentCompliant(agentId), "Agent not compliant");
    _;
}

// Prevent reporter spam
modifier validReporter() {
    require(USDC.balanceOf(msg.sender) >= reporterStakeRequired, "Insufficient stake");
    require(reporterAccuracyScore[msg.sender] >= 5000, "Reporter accuracy too low");
    _;
}

// Prevent governance attacks
modifier onlyAfterTimelock(uint256 proposalId) {
    require(block.timestamp >= proposals[proposalId].executionTime, "Timelock not met");
    _;
}
```

---

## 5. Foundry Project Structure

```
agent-constitution/
├── src/
│   ├── interfaces/
│   │   ├── IConstitution.sol
│   │   ├── IAgentRegistry.sol
│   │   ├── IActionLog.sol
│   │   ├── ITribunal.sol
│   │   ├── IKillSwitch.sol
│   │   └── IGovernance.sol
│   ├── core/
│   │   ├── Constitution.sol
│   │   ├── AgentRegistry.sol
│   │   ├── ActionLog.sol
│   │   ├── Tribunal.sol
│   │   ├── KillSwitch.sol
│   │   └── Governance.sol
│   ├── libraries/
│   │   ├── SlashingMath.sol
│   │   ├── VotingPower.sol
│   │   └── Constants.sol
│   └── mocks/
│       ├── MockUSDC.sol
│       └── MockAgent.sol
├── test/
│   ├── unit/
│   │   ├── Constitution.t.sol
│   │   ├── AgentRegistry.t.sol
│   │   ├── ActionLog.t.sol
│   │   ├── Tribunal.t.sol
│   │   ├── KillSwitch.t.sol
│   │   └── Governance.t.sol
│   ├── integration/
│   │   ├── FullWorkflow.t.sol
│   │   ├── SlashingIntegration.t.sol
│   │   └── EmergencyScenarios.t.sol
│   ├── fuzz/
│   │   ├── SlashingFuzz.t.sol
│   │   ├── VotingFuzz.t.sol
│   │   └── StakingFuzz.t.sol
│   └── invariant/
│       ├── StakeInvariant.t.sol
│       ├── GovernanceInvariant.t.sol
│       └── ConstitutionInvariant.t.sol
├── script/
│   ├── Deploy.s.sol
│   ├── Initialize.s.sol
│   └── Demo.s.sol
├── lib/
│   ├── openzeppelin-contracts/
│   ├── forge-std/
│   └── solmate/
├── foundry.toml
├── remappings.txt
├── .env.example
└── README.md
```

---

## 6. Test Plan

### 6.1 Unit Tests

**Constitution.sol Tests:**
- Rule creation and activation
- Immutability enforcement for CRITICAL rules
- Access control validation
- Event emission verification

**AgentRegistry.sol Tests:**
- Agent registration with valid stake
- Stake increase/decrease operations
- Status transitions (ACTIVE → SUSPENDED → TERMINATED)
- NFT minting and metadata handling
- Tier requirement enforcement

**ActionLog.sol Tests:**
- Action logging for all risk levels
- Approval workflow for high-risk actions
- Batch action processing
- Permission validation

**Tribunal.sol Tests:**
- Violation report submission
- Evidence validation
- Slashing calculation accuracy
- Report resolution workflows
- Reporter accuracy scoring

**KillSwitch.sol Tests:**
- Individual agent halt/restore
- System-wide emergency triggers
- Governance voting for emergency resolution
- Access control for emergency powers

**Governance.sol Tests:**
- Proposal creation and voting
- Quorum calculation
- Execution delays and timelocks
- Vote delegation mechanics

### 6.2 Integration Tests

**Full Workflow Test:**
```solidity
// Agent lifecycle: Register → Operate → Report → Slash → Terminate
function testFullAgentLifecycle() public {
    // 1. Register agent with stake
    uint256 agentId = registry.registerAgent(...);
    
    // 2. Agent performs actions
    actionLog.logAction(agentId, ...);
    
    // 3. Violation reported
    uint256 reportId = tribunal.reportViolation(agentId, ...);
    
    // 4. Violation confirmed and agent slashed
    tribunal.resolveReport(reportId, true, "Confirmed violation");
    uint256 slashed = tribunal.executeSlashing(reportId);
    
    // 5. Verify final state
    assertEq(registry.agents(agentId).status, AgentStatus.SUSPENDED);
    assertGt(slashed, 0);
}
```

**Emergency Scenarios:**
- Mass agent halt during system emergency
- Governance recovery from emergency state
- Individual agent emergency halt and restore

### 6.3 Fuzz Testing

**Slashing Math Fuzzing:**
```solidity
function testFuzzSlashingCalculation(
    uint256 stakedAmount,
    uint8 violationCount,
    uint8 severity
) public {
    // Bound inputs to valid ranges
    stakedAmount = bound(stakedAmount, 1000e6, 1000000e6); // 1K-1M USDC
    violationCount = bound(violationCount, 0, 10);
    severity = bound(severity, 0, 3);
    
    // Test slashing calculation
    (uint256 slashAmount, uint256 percentage) = tribunal.calculateSlashAmount(
        agentId, ruleId
    );
    
    // Invariants
    assertLe(slashAmount, stakedAmount); // Can't slash more than staked
    assertLe(percentage, 10000); // Max 100% (10000 basis points)
    assertGe(stakedAmount - slashAmount, minRetention); // Minimum retention
}
```

**Voting Power Fuzzing:**
```solidity
function testFuzzVotingPower(address[] memory voters, uint256[] memory stakes) public {
    // Test voting power calculation edge cases
    // Ensure no overflow/underflow in vote aggregation
}
```

### 6.4 Invariant Testing

**Stake Invariants:**
```solidity
contract StakeInvariant is Test {
    function invariant_totalStakedMatchesSum() public {
        uint256 calculatedTotal = 0;
        for (uint256 i = 1; i <= registry.totalSupply(); i++) {
            calculatedTotal += registry.agents(i).stakedAmount;
        }
        assertEq(registry.totalStakedAmount(), calculatedTotal);
    }
    
    function invariant_agentMeetsMinimumStake() public {
        for (uint256 i = 1; i <= registry.totalSupply(); i++) {
            if (registry.agents(i).status == AgentStatus.ACTIVE) {
                assertGe(
                    registry.agents(i).stakedAmount,
                    registry.agents(i).requiredStake
                );
            }
        }
    }
}
```

**Constitution Invariants:**
```solidity
contract ConstitutionInvariant is Test {
    function invariant_criticalRulesImmutable() public {
        // CRITICAL rules can never be modified or deactivated
        assertTrue(constitution.isRuleActive(RULE_NO_HARM));
        assertTrue(constitution.isRuleActive(RULE_OBEY_GOVERNANCE));
        // ... check all critical rules
    }
}
```

---

## 7. Deployment Plan (Base L2)

### 7.1 Pre-deployment Checklist

- [ ] Foundry tests passing (100% coverage)
- [ ] Gas optimization review completed
- [ ] Security audit recommendations addressed
- [ ] Base testnet deployment and testing
- [ ] USDC contract address verified on Base
- [ ] Initial governance multisig setup

### 7.2 Deployment Sequence

```solidity
// Deploy.s.sol - Deployment script
contract DeployScript is Script {
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant GOVERNANCE_MULTISIG = 0x...; // To be determined
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Constitution first (no dependencies)
        Constitution constitution = new Constitution();
        
        // 2. Deploy AgentRegistry (depends on Constitution, USDC)
        AgentRegistry registry = new AgentRegistry(
            BASE_USDC,
            address(constitution)
        );
        
        // 3. Deploy ActionLog (depends on AgentRegistry)
        ActionLog actionLog = new ActionLog(address(registry));
        
        // 4. Deploy Tribunal (depends on Constitution, AgentRegistry, USDC)
        Tribunal tribunal = new Tribunal(
            address(constitution),
            address(registry),
            BASE_USDC
        );
        
        // 5. Deploy KillSwitch (depends on AgentRegistry)
        KillSwitch killSwitch = new KillSwitch(address(registry));
        
        // 6. Deploy Governance (depends on Constitution, AgentRegistry, USDC)
        Governance governance = new Governance(
            address(constitution),
            address(registry),
            BASE_USDC
        );
        
        // 7. Initialize all contracts
        constitution.initialize(address(governance));
        registry.grantRole(registry.TRIBUNAL_ROLE(), address(tribunal));
        // ... additional role setup
        
        vm.stopBroadcast();
        
        // Log deployed addresses
        console.log("Constitution:", address(constitution));
        console.log("AgentRegistry:", address(registry));
        console.log("ActionLog:", address(actionLog));
        console.log("Tribunal:", address(tribunal));
        console.log("KillSwitch:", address(killSwitch));
        console.log("Governance:", address(governance));
    }
}
```

### 7.3 Post-deployment Setup

```solidity
// Initialize.s.sol - Post-deployment initialization
contract InitializeScript is Script {
    function run() external {
        // Load deployed contract addresses
        Constitution constitution = Constitution(vm.envAddress("CONSTITUTION_ADDRESS"));
        AgentRegistry registry = AgentRegistry(vm.envAddress("REGISTRY_ADDRESS"));
        // ...
        
        // Set up core constitutional rules
        constitution.proposeRule(
            RULE_NO_HARM,
            "An agent SHALL NOT take actions that harm humans or humanity",
            IConstitution.RuleSeverity.CRITICAL,
            5000 // 50% slash for violations
        );
        constitution.activateRule(RULE_NO_HARM);
        // ... activate all core rules
        
        // Set tier stake requirements
        registry.setTierRequirement(CapabilityTier.BASIC, 1000e6);      // 1,000 USDC
        registry.setTierRequirement(CapabilityTier.STANDARD, 5000e6);   // 5,000 USDC
        registry.setTierRequirement(CapabilityTier.ADVANCED, 25000e6);  // 25,000 USDC
        registry.setTierRequirement(CapabilityTier.AUTONOMOUS, 100000e6); // 100,000 USDC
        
        // Set up slashing parameters
        // ... configure tribunal parameters
    }
}
```

### 7.4 Base L2 Considerations

- **Gas Costs:** Base L2 offers ~10x lower gas costs than mainnet
- **USDC Integration:** Native USDC on Base (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
- **Block Time:** ~2 second block times for faster finality
- **Bridge Integration:** For future cross-chain agent operations

---

## 8. Demo Scenario: OpenClaw Agent Registration & Operation

### 8.1 Demo Script Overview

A complete demonstration showing how an OpenClaw agent interacts with the AgentConstitution system.

### 8.2 Demo Workflow

```solidity
// Demo.s.sol - Complete demo scenario
contract DemoScript is Script {
    function run() external {
        // Demo actors
        address openclawOperator = makeAddr("openclaw_operator");
        address reporter = makeAddr("violation_reporter");
        
        // Give demo actors USDC
        deal(BASE_USDC, openclawOperator, 10000e6);  // 10,000 USDC
        deal(BASE_USDC, reporter, 1000e6);           // 1,000 USDC
        
        console.log("=== AgentConstitution Demo ===");
        
        // STEP 1: OpenClaw Agent Registration
        vm.startPrank(openclawOperator);
        console.log("1. Registering OpenClaw agent...");
        
        IERC20(BASE_USDC).approve(address(registry), 5000e6);
        uint256 agentId = registry.registerAgent(
            openclawOperator,
            "OpenClaw Trading Bot",
            "ipfs://QmDemo...", // Metadata URI
            IAgentRegistry.CapabilityTier.STANDARD,
            5000e6 // 5,000 USDC stake
        );
        
        console.log("   Agent registered with ID:", agentId);
        console.log("   Stake deposited: 5,000 USDC");
        
        // STEP 2: Agent Performs Actions
        console.log("2. Agent performing actions...");
        
        // Low-risk action (auto-logged)
        actionLog.logAction(
            agentId,
            IActionLog.ActionType.COMMUNICATION,
            IActionLog.RiskLevel.LOW,
            keccak256("telegram_message_001"),
            "Sent trading update to user",
            ""
        );
        
        // High-risk action (needs approval)
        uint256 approvalActionId = actionLog.requestApproval(
            agentId,
            IActionLog.ActionType.FINANCIAL,
            keccak256("large_trade_001"),
            "Execute $50,000 USDC trade on DEX"
        );
        
        // Operator approves the high-risk action
        actionLog.approveAction(approvalActionId, true);
        
        // Execute and log the approved action
        actionLog.logAction(
            agentId,
            IActionLog.ActionType.FINANCIAL,
            IActionLog.RiskLevel.HIGH,
            keccak256("large_trade_001"),
            "Executed $50,000 USDC trade on DEX",
            abi.encode(50000e6, block.timestamp)
        );
        
        console.log("   Actions logged successfully");
        vm.stopPrank();
        
        // STEP 3: Violation Reported
        console.log("3. Violation being reported...");
        
        vm.startPrank(reporter);
        IERC20(BASE_USDC).approve(address(tribunal), 100e6);
        
        uint256 reportId = tribunal.reportViolation(
            agentId,
            RULE_TRANSPARENCY, // Violated transparency rule
            ITribunal.EvidenceType.LOG_ENTRY,
            keccak256("hidden_trade_evidence"),
            "ipfs://QmEvidence...",
            "Agent executed trades without proper logging"
        );
        
        console.log("   Violation reported with ID:", reportId);
        vm.stopPrank();
        
        // STEP 4: Violation Resolved (Judge confirms)
        console.log("4. Resolving violation...");
        
        address judge = makeAddr("tribunal_judge");
        vm.startPrank(judge);
        
        // Grant judge role
        tribunal.grantRole(tribunal.TRIBUNAL_JUDGE_ROLE(), judge);
        
        // Confirm violation
        tribunal.resolveReport(
            reportId,
            true, // is violation
            "Evidence confirms improper trade logging. Transparency violation confirmed."
        );
        
        // Execute slashing
        uint256 slashedAmount = tribunal.executeSlashing(reportId);
        
        console.log("   Violation confirmed, agent slashed:", slashedAmount, "USDC");
        vm.stopPrank();
        
        // STEP 5: Check Final State
        console.log("5. Final agent state:");
        
        IAgentRegistry.AgentProfile memory finalProfile = registry.getAgentProfile(agentId);
        console.log("   Status:", uint256(finalProfile.status));
        console.log("   Remaining stake:", finalProfile.stakedAmount);
        console.log("   Violation count:", finalProfile.violationCount);
        console.log("   Total slashed:", finalProfile.slashedAmount);
        
        // Check if agent is still compliant
        bool isCompliant = registry.isAgentCompliant(agentId);
        console.log("   Still compliant:", isCompliant);
        
        console.log("=== Demo Complete ===");
    }
}
```

### 8.3 Expected Demo Output

```
=== AgentConstitution Demo ===
1. Registering OpenClaw agent...
   Agent registered with ID: 1
   Stake deposited: 5,000 USDC

2. Agent performing actions...
   Actions logged successfully

3. Violation being reported...
   Violation reported with ID: 1

4. Resolving violation...
   Violation confirmed, agent slashed: 500 USDC

5. Final agent state:
   Status: 1 (ACTIVE)
   Remaining stake: 4500000000
   Violation count: 1
   Total slashed: 500000000
   Still compliant: true

=== Demo Complete ===
```

### 8.4 Demo Extensions

Additional scenarios to showcase:

**Emergency Halt Demo:**
```solidity
function demoEmergencyHalt() public {
    // Trigger system emergency
    killSwitch.triggerSystemEmergency(
        IKillSwitch.HaltReason.SECURITY_BREACH,
        "Critical vulnerability discovered in agent framework"
    );
    
    // Verify all agents halted
    assertFalse(killSwitch.isOperationAllowed(agentId));
}
```

**Governance Demo:**
```solidity
function demoGovernanceUpdate() public {
    // Propose new constitutional rule
    uint256 proposalId = governance.propose(
        "Add AI Model Disclosure Rule",
        "Agents must disclose their AI model and version",
        ruleAdditionCalldata
    );
    
    // Vote and execute
    governance.vote(proposalId, true);
    governance.execute(proposalId);
}
```

---

## 9. Timeline (February 4-8, 2026)

### Day 1 (Feb 4-5): Foundation
- [ ] Set up Foundry project structure
- [ ] Implement Constitution.sol with core rules
- [ ] Implement AgentRegistry.sol with staking
- [ ] Write unit tests for both contracts
- [ ] Deploy to Base testnet

### Day 2 (Feb 5-6): Core Logic
- [ ] Implement ActionLog.sol with approval workflow
- [ ] Implement Tribunal.sol with slashing math
- [ ] Implement KillSwitch.sol with emergency powers
- [ ] Integration tests for violation reporting
- [ ] Fuzz test slashing calculations

### Day 3 (Feb 6-7): Integration & Testing
- [ ] Implement basic Governance.sol
- [ ] Full integration test suite
- [ ] Gas optimization pass
- [ ] Security review and fixes
- [ ] Demo script implementation

### Day 4 (Feb 7-8): Polish & Deploy
- [ ] Final testing and bug fixes
- [ ] Deploy to Base mainnet
- [ ] Initialize with core rules
- [ ] Documentation and demo recording
- [ ] Submit to hackathon

### Critical Path Items:
1. **Slashing Math:** Must be mathematically sound and gas-efficient
2. **Emergency Powers:** Kill switch must be foolproof
3. **Integration:** All contracts must work together seamlessly
4. **Demo:** Must showcase real agent lifecycle

### Risk Mitigation:
- Keep governance simple for MVP (owner-based, upgrade to DAO post-hackathon)
- Use battle-tested OpenZeppelin contracts
- Extensive testing with realistic scenarios
- Have backup deployment plan if Base issues arise

---

This engineering plan provides complete implementation specifications that enable a developer to build the AgentConstitution system without additional architectural decisions. Each contract is fully specified with storage layouts, function signatures, inheritance hierarchies, and comprehensive test plans.