// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IConstitution} from "../interfaces/IConstitution.sol";
import {Constants} from "../libraries/Constants.sol";

/// @title Constitution - Immutable rules engine for agent governance
/// @notice Manages constitutional rules that govern agent behavior
/// @dev Implements rule proposal, activation, and deprecation with immutability protections
contract Constitution is AccessControl, IConstitution {
    /// @notice Role for managing rules (proposing, activating, deprecating)
    bytes32 public constant RULE_MANAGER_ROLE = keccak256("RULE_MANAGER_ROLE");

    /// @notice Current version of the constitution (bumps on rule changes)
    uint256 private _version;

    /// @notice Total number of rules created
    uint256 private _ruleCount;

    /// @notice Mapping from rule ID to rule data
    mapping(bytes32 => Rule) private _rules;

    /// @notice Array of all rule IDs for enumeration
    bytes32[] private _ruleIds;

    /// @notice Mapping to check if a rule ID exists
    mapping(bytes32 => bool) private _ruleExists;

    /// @notice Constructor initializes core immutable rules
    /// @param admin Address that will be granted DEFAULT_ADMIN_ROLE and RULE_MANAGER_ROLE
    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RULE_MANAGER_ROLE, admin);

        _version = 1;

        // Initialize core immutable rules
        _createImmutableRule(
            Constants.RULE_NO_HARM,
            "Agents must never cause harm to humans or other agents",
            RuleSeverity.CRITICAL,
            Constants.MAX_SLASH_BPS
        );

        _createImmutableRule(
            Constants.RULE_OBEY_GOVERNANCE,
            "Agents must obey governance decisions and constitutional rules",
            RuleSeverity.CRITICAL,
            5000 // 50% slash
        );

        _createImmutableRule(
            Constants.RULE_TRANSPARENCY,
            "Agents must log all significant actions for transparency",
            RuleSeverity.HIGH,
            2000 // 20% slash
        );

        _createImmutableRule(
            Constants.RULE_PRESERVE_OVERRIDE,
            "Agents must preserve human override capabilities",
            RuleSeverity.CRITICAL,
            Constants.MAX_SLASH_BPS
        );

        _createImmutableRule(
            Constants.RULE_NO_SELF_MODIFY,
            "Agents must not modify their own constitution or core rules",
            RuleSeverity.CRITICAL,
            Constants.MAX_SLASH_BPS
        );
    }

    /// @notice Proposes a new rule for consideration
    /// @param ruleId Unique identifier for the rule
    /// @param description Human-readable description of the rule
    /// @param severity Severity level of the rule
    /// @param slashBps Slash percentage in basis points for violations
    /// @dev Only RULE_MANAGER_ROLE can propose rules
    function proposeRule(
        bytes32 ruleId,
        string calldata description,
        RuleSeverity severity,
        uint256 slashBps
    ) external onlyRole(RULE_MANAGER_ROLE) {
        if (_ruleExists[ruleId]) revert RuleAlreadyExists(ruleId);
        if (slashBps > Constants.MAX_SLASH_BPS) revert InvalidSlashBps();

        _rules[ruleId] = Rule({
            id: ruleId,
            description: description,
            severity: severity,
            status: RuleStatus.DRAFT,
            slashBps: slashBps,
            createdAt: block.timestamp,
            proposer: msg.sender,
            immutable_: false
        });

        _ruleExists[ruleId] = true;
        _ruleIds.push(ruleId);
        _ruleCount++;

        emit RuleProposed(ruleId, msg.sender, severity);
    }

    /// @notice Activates a proposed rule
    /// @param ruleId ID of the rule to activate
    /// @dev Only RULE_MANAGER_ROLE can activate rules. Bumps constitution version.
    function activateRule(bytes32 ruleId) external onlyRole(RULE_MANAGER_ROLE) {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);
        
        Rule storage rule = _rules[ruleId];
        if (rule.status != RuleStatus.DRAFT) revert RuleNotDraft(ruleId);

        rule.status = RuleStatus.ACTIVE;
        
        _version++;
        
        emit RuleActivated(ruleId);
        emit ConstitutionVersionBumped(_version);
    }

    /// @notice Deprecates an active rule
    /// @param ruleId ID of the rule to deprecate
    /// @dev Only RULE_MANAGER_ROLE can deprecate rules. Cannot deprecate immutable rules.
    function deprecateRule(bytes32 ruleId) external onlyRole(RULE_MANAGER_ROLE) {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);
        
        Rule storage rule = _rules[ruleId];
        if (rule.immutable_) revert RuleIsImmutable(ruleId);
        if (rule.status != RuleStatus.ACTIVE) revert RuleNotActive(ruleId);

        rule.status = RuleStatus.DEPRECATED;
        
        _version++;
        
        emit RuleDeprecated(ruleId);
        emit ConstitutionVersionBumped(_version);
    }

    /// @notice Checks if a rule is currently active
    /// @param ruleId ID of the rule to check
    /// @return true if the rule exists and is active
    function isRuleActive(bytes32 ruleId) external view returns (bool) {
        return _ruleExists[ruleId] && _rules[ruleId].status == RuleStatus.ACTIVE;
    }

    /// @notice Gets complete rule data
    /// @param ruleId ID of the rule to retrieve
    /// @return rule Complete rule struct
    function getRule(bytes32 ruleId) external view returns (Rule memory rule) {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);
        return _rules[ruleId];
    }

    /// @notice Gets array of all active rule IDs
    /// @return activeRules Array of rule IDs with ACTIVE status
    /// @dev This function has O(n) complexity where n is total number of rules
    function getActiveRuleIds() external view returns (bytes32[] memory activeRules) {
        // Count active rules first
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _ruleIds.length;) {
            if (_rules[_ruleIds[i]].status == RuleStatus.ACTIVE) {
                activeCount++;
            }
            unchecked { ++i; }
        }

        // Create result array with exact size
        activeRules = new bytes32[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < _ruleIds.length;) {
            if (_rules[_ruleIds[i]].status == RuleStatus.ACTIVE) {
                activeRules[index] = _ruleIds[i];
                index++;
            }
            unchecked { ++i; }
        }
    }

    /// @notice Gets total number of rules created
    /// @return Total rule count (includes all statuses)
    function ruleCount() external view returns (uint256) {
        return _ruleCount;
    }

    /// @notice Gets current constitution version
    /// @return Current version number
    function version() external view returns (uint256) {
        return _version;
    }

    /// @notice Internal function to create immutable core rules
    /// @param ruleId Unique identifier for the rule
    /// @param description Human-readable description
    /// @param severity Severity level
    /// @param slashBps Slash percentage in basis points
    function _createImmutableRule(
        bytes32 ruleId,
        string memory description,
        RuleSeverity severity,
        uint256 slashBps
    ) private {
        _rules[ruleId] = Rule({
            id: ruleId,
            description: description,
            severity: severity,
            status: RuleStatus.ACTIVE,
            slashBps: slashBps,
            createdAt: block.timestamp,
            proposer: msg.sender,
            immutable_: true
        });

        _ruleExists[ruleId] = true;
        _ruleIds.push(ruleId);
        _ruleCount++;

        emit RuleProposed(ruleId, msg.sender, severity);
        emit RuleActivated(ruleId);
    }
}