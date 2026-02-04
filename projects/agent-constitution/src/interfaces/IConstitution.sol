// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IConstitution - Interface for the immutable rules engine
interface IConstitution {
    enum RuleSeverity { LOW, MEDIUM, HIGH, CRITICAL }
    enum RuleStatus { DRAFT, ACTIVE, DEPRECATED }

    struct Rule {
        bytes32 id;
        string description;
        RuleSeverity severity;
        RuleStatus status;
        uint256 slashBps;       // slash percentage in basis points
        uint256 createdAt;
        address proposer;
        bool immutable_;        // true = cannot be modified or deprecated
    }

    event RuleProposed(bytes32 indexed ruleId, address indexed proposer, RuleSeverity severity);
    event RuleActivated(bytes32 indexed ruleId);
    event RuleDeprecated(bytes32 indexed ruleId);
    event ConstitutionVersionBumped(uint256 newVersion);

    error RuleAlreadyExists(bytes32 ruleId);
    error RuleNotFound(bytes32 ruleId);
    error RuleIsImmutable(bytes32 ruleId);
    error InvalidSlashBps();
    error RuleNotActive(bytes32 ruleId);

    function proposeRule(
        bytes32 ruleId,
        string calldata description,
        RuleSeverity severity,
        uint256 slashBps
    ) external;

    function activateRule(bytes32 ruleId) external;
    function deprecateRule(bytes32 ruleId) external;
    function isRuleActive(bytes32 ruleId) external view returns (bool);
    function getRule(bytes32 ruleId) external view returns (Rule memory);
    function getActiveRuleIds() external view returns (bytes32[] memory);
    function ruleCount() external view returns (uint256);
    function version() external view returns (uint256);
}
