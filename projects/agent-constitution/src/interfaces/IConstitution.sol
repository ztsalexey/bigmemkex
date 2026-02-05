// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IConstitution - Open human-governed rules engine for AI agents
/// @notice Anyone can propose rules. Humans endorse them with USDC stake.
///         Agents are structurally excluded from governance.
interface IConstitution {
    enum RuleSeverity { LOW, MEDIUM, HIGH, CRITICAL }
    enum RuleStatus { PROPOSED, ACTIVE, DEPRECATED }

    struct Rule {
        bytes32 id;
        string description;
        RuleSeverity severity;
        RuleStatus status;
        uint256 slashBps;           // slash percentage in basis points
        uint256 createdAt;
        address proposer;
        bool immutable_;            // true = cannot be modified or deprecated
        uint256 totalEndorsed;      // total USDC endorsing this rule
        uint256 totalOpposed;       // total USDC opposing this rule
        uint256 activatedAt;        // when rule reached threshold and activated
    }

    // ── Events ─────────────────────────────────────────────────────
    event RuleProposed(bytes32 indexed ruleId, address indexed proposer, RuleSeverity severity, uint256 slashBps);
    event RuleEndorsed(bytes32 indexed ruleId, address indexed endorser, uint256 amount, uint256 totalEndorsed);
    event RuleOpposed(bytes32 indexed ruleId, address indexed opposer, uint256 amount, uint256 totalOpposed);
    event RuleActivated(bytes32 indexed ruleId, uint256 totalEndorsed);
    event RuleDeprecated(bytes32 indexed ruleId, uint256 totalOpposed);
    event EndorsementWithdrawn(bytes32 indexed ruleId, address indexed endorser, uint256 amount);
    event ConstitutionVersionBumped(uint256 newVersion);

    // ── Errors ─────────────────────────────────────────────────────
    error AgentsCannotGovern();
    error RuleAlreadyExists(bytes32 ruleId);
    error RuleNotFound(bytes32 ruleId);
    error RuleIsImmutable(bytes32 ruleId);
    error InvalidSlashBps();
    error RuleNotActive(bytes32 ruleId);
    error RuleNotProposed(bytes32 ruleId);
    error RuleAlreadyActive(bytes32 ruleId);
    error ThresholdNotMet(bytes32 ruleId, uint256 current, uint256 required);
    error ZeroAmount();
    error NoEndorsement(bytes32 ruleId, address endorser);
    error RuleStillActive(bytes32 ruleId);

    // ── Propose / Endorse / Oppose ─────────────────────────────────
    function proposeRule(
        bytes32 ruleId,
        string calldata description,
        RuleSeverity severity,
        uint256 slashBps
    ) external;

    function endorseRule(bytes32 ruleId, uint256 amount) external;
    function opposeRule(bytes32 ruleId, uint256 amount) external;
    function withdrawEndorsement(bytes32 ruleId) external;

    // ── Activation / Deprecation ───────────────────────────────────
    function activateRule(bytes32 ruleId) external;
    function deprecateRule(bytes32 ruleId) external;

    // ── Views ──────────────────────────────────────────────────────
    function isRuleActive(bytes32 ruleId) external view returns (bool);
    function getRule(bytes32 ruleId) external view returns (Rule memory);
    function getActiveRuleIds() external view returns (bytes32[] memory);
    function ruleCount() external view returns (uint256);
    function version() external view returns (uint256);
    function activationThreshold() external view returns (uint256);
    function getEndorsement(bytes32 ruleId, address endorser) external view returns (uint256);
}
