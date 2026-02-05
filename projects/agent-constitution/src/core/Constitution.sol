// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IConstitution} from "../interfaces/IConstitution.sol";
import {IAgentRegistry} from "../interfaces/IAgentRegistry.sol";
import {Constants} from "../libraries/Constants.sol";

/// @title Constitution - Open human-governed rules engine for AI agents
/// @notice Humans make the rules. Agents follow them.
///         Any human can propose rules, endorse them with USDC, and collectively
///         activate governance over AI agents. Agent addresses are structurally
///         excluded from all governance actions.
/// @dev No admin keys. No DAO tokens. Core rules are immutable from genesis.
///      Custom rules activate when they reach the USDC endorsement threshold.
contract Constitution is ReentrancyGuard, IConstitution {
    using SafeERC20 for IERC20;

    // ── Immutables ─────────────────────────────────────────────────
    IERC20 public immutable USDC;
    IAgentRegistry public immutable AGENT_REGISTRY;

    // ── Configuration ──────────────────────────────────────────────
    /// @notice USDC required to propose a rule (anti-spam, returned on deprecation)
    uint256 public constant PROPOSAL_STAKE = 100e6; // 100 USDC

    /// @notice USDC endorsement threshold to activate a rule
    uint256 public immutable ACTIVATION_THRESHOLD;

    // ── State ──────────────────────────────────────────────────────
    uint256 private _version;
    uint256 private _ruleCount;
    mapping(bytes32 => Rule) private _rules;
    bytes32[] private _ruleIds;
    mapping(bytes32 => bool) private _ruleExists;

    /// @notice endorsements[ruleId][endorser] = amount staked
    mapping(bytes32 => mapping(address => uint256)) private _endorsements;

    /// @notice oppositions[ruleId][opposer] = amount staked
    mapping(bytes32 => mapping(address => uint256)) private _oppositions;

    // ── Modifiers ──────────────────────────────────────────────────

    /// @notice Only humans can call this function (not agent operators)
    modifier onlyHuman() {
        if (AGENT_REGISTRY.isOperator(msg.sender)) revert AgentsCannotGovern();
        _;
    }

    // ── Constructor ────────────────────────────────────────────────

    /// @notice Deploy the Constitution with core immutable rules
    /// @param usdc_ USDC token address
    /// @param agentRegistry_ AgentRegistry address (for agent detection)
    /// @param threshold_ USDC endorsement threshold to activate rules
    constructor(address usdc_, address agentRegistry_, uint256 threshold_) {
        if (usdc_ == address(0) || agentRegistry_ == address(0)) revert ZeroAmount();
        if (threshold_ == 0) revert ZeroAmount();

        USDC = IERC20(usdc_);
        AGENT_REGISTRY = IAgentRegistry(agentRegistry_);
        ACTIVATION_THRESHOLD = threshold_;
        _version = 1;

        // Genesis rules — immutable, active from block 0, no endorsement needed
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
            5000
        );
        _createImmutableRule(
            Constants.RULE_TRANSPARENCY,
            "Agents must log all significant actions for transparency",
            RuleSeverity.HIGH,
            2000
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

    // ── Propose ────────────────────────────────────────────────────

    /// @notice Propose a new rule. Costs PROPOSAL_STAKE USDC (counts as endorsement).
    /// @param ruleId Unique identifier for the rule
    /// @param description Human-readable description
    /// @param severity Severity level
    /// @param slashBps Slash percentage in basis points for violations
    function proposeRule(
        bytes32 ruleId,
        string calldata description,
        RuleSeverity severity,
        uint256 slashBps
    ) external onlyHuman nonReentrant {
        if (_ruleExists[ruleId]) revert RuleAlreadyExists(ruleId);
        if (slashBps == 0 || slashBps > Constants.MAX_SLASH_BPS) revert InvalidSlashBps();

        // Take proposal stake (also counts as first endorsement)
        USDC.safeTransferFrom(msg.sender, address(this), PROPOSAL_STAKE);

        _rules[ruleId] = Rule({
            id: ruleId,
            description: description,
            severity: severity,
            status: RuleStatus.PROPOSED,
            slashBps: slashBps,
            createdAt: block.timestamp,
            proposer: msg.sender,
            immutable_: false,
            totalEndorsed: PROPOSAL_STAKE,
            totalOpposed: 0,
            activatedAt: 0
        });

        _endorsements[ruleId][msg.sender] = PROPOSAL_STAKE;
        _ruleExists[ruleId] = true;
        _ruleIds.push(ruleId);
        _ruleCount++;

        emit RuleProposed(ruleId, msg.sender, severity, slashBps);
        emit RuleEndorsed(ruleId, msg.sender, PROPOSAL_STAKE, PROPOSAL_STAKE);
    }

    // ── Endorse / Oppose ───────────────────────────────────────────

    /// @notice Endorse a proposed rule with USDC stake
    /// @param ruleId Rule to endorse
    /// @param amount USDC amount to stake in support
    function endorseRule(bytes32 ruleId, uint256 amount) external onlyHuman nonReentrant {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);
        if (amount == 0) revert ZeroAmount();

        Rule storage rule = _rules[ruleId];
        if (rule.status == RuleStatus.DEPRECATED) revert RuleNotProposed(ruleId);

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        _endorsements[ruleId][msg.sender] += amount;
        rule.totalEndorsed += amount;

        emit RuleEndorsed(ruleId, msg.sender, amount, rule.totalEndorsed);
    }

    /// @notice Oppose an active rule with USDC stake
    /// @param ruleId Rule to oppose
    /// @param amount USDC amount to stake against
    function opposeRule(bytes32 ruleId, uint256 amount) external onlyHuman nonReentrant {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);
        if (amount == 0) revert ZeroAmount();

        Rule storage rule = _rules[ruleId];
        if (rule.status != RuleStatus.ACTIVE) revert RuleNotActive(ruleId);
        if (rule.immutable_) revert RuleIsImmutable(ruleId);

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        _oppositions[ruleId][msg.sender] += amount;
        rule.totalOpposed += amount;

        emit RuleOpposed(ruleId, msg.sender, amount, rule.totalOpposed);
    }

    /// @notice Withdraw your endorsement from a deprecated or proposed rule
    /// @param ruleId Rule to withdraw from
    function withdrawEndorsement(bytes32 ruleId) external nonReentrant {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);

        Rule storage rule = _rules[ruleId];
        // Can only withdraw from non-active rules (proposed or deprecated)
        if (rule.status == RuleStatus.ACTIVE) revert RuleStillActive(ruleId);

        uint256 endorsed = _endorsements[ruleId][msg.sender];
        uint256 opposed = _oppositions[ruleId][msg.sender];
        uint256 total = endorsed + opposed;
        if (total == 0) revert NoEndorsement(ruleId, msg.sender);

        _endorsements[ruleId][msg.sender] = 0;
        _oppositions[ruleId][msg.sender] = 0;

        USDC.safeTransfer(msg.sender, total);

        emit EndorsementWithdrawn(ruleId, msg.sender, total);
    }

    // ── Activation / Deprecation ───────────────────────────────────

    /// @notice Activate a proposed rule that has reached the endorsement threshold
    /// @param ruleId Rule to activate
    /// @dev Anyone can call this — it just checks the threshold
    function activateRule(bytes32 ruleId) external {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);

        Rule storage rule = _rules[ruleId];
        if (rule.status != RuleStatus.PROPOSED) revert RuleNotProposed(ruleId);
        if (rule.totalEndorsed < ACTIVATION_THRESHOLD) {
            revert ThresholdNotMet(ruleId, rule.totalEndorsed, ACTIVATION_THRESHOLD);
        }

        rule.status = RuleStatus.ACTIVE;
        rule.activatedAt = block.timestamp;
        _version++;

        emit RuleActivated(ruleId, rule.totalEndorsed);
        emit ConstitutionVersionBumped(_version);
    }

    /// @notice Deprecate an active rule where opposition exceeds endorsement
    /// @param ruleId Rule to deprecate
    /// @dev Anyone can call this — it just checks opposition > endorsement
    function deprecateRule(bytes32 ruleId) external {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);

        Rule storage rule = _rules[ruleId];
        if (rule.immutable_) revert RuleIsImmutable(ruleId);
        if (rule.status != RuleStatus.ACTIVE) revert RuleNotActive(ruleId);

        // Opposition must exceed endorsement to deprecate
        if (rule.totalOpposed <= rule.totalEndorsed) {
            revert ThresholdNotMet(ruleId, rule.totalOpposed, rule.totalEndorsed + 1);
        }

        rule.status = RuleStatus.DEPRECATED;
        _version++;

        emit RuleDeprecated(ruleId, rule.totalOpposed);
        emit ConstitutionVersionBumped(_version);
    }

    // ── Views ──────────────────────────────────────────────────────

    function isRuleActive(bytes32 ruleId) external view returns (bool) {
        return _ruleExists[ruleId] && _rules[ruleId].status == RuleStatus.ACTIVE;
    }

    function getRule(bytes32 ruleId) external view returns (Rule memory) {
        if (!_ruleExists[ruleId]) revert RuleNotFound(ruleId);
        return _rules[ruleId];
    }

    /// @dev O(n) where n = total rules. Acceptable for governance reads.
    function getActiveRuleIds() external view returns (bytes32[] memory activeRules) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _ruleIds.length;) {
            if (_rules[_ruleIds[i]].status == RuleStatus.ACTIVE) {
                activeCount++;
            }
            unchecked { ++i; }
        }

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

    function ruleCount() external view returns (uint256) {
        return _ruleCount;
    }

    function version() external view returns (uint256) {
        return _version;
    }

    function activationThreshold() external view returns (uint256) {
        return ACTIVATION_THRESHOLD;
    }

    function getEndorsement(bytes32 ruleId, address endorser) external view returns (uint256) {
        return _endorsements[ruleId][endorser];
    }

    function getOpposition(bytes32 ruleId, address opposer) external view returns (uint256) {
        return _oppositions[ruleId][opposer];
    }

    // ── Internal ───────────────────────────────────────────────────

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
            proposer: address(0), // Genesis — no human proposer
            immutable_: true,
            totalEndorsed: type(uint256).max, // Infinite endorsement — cannot be opposed
            totalOpposed: 0,
            activatedAt: block.timestamp
        });

        _ruleExists[ruleId] = true;
        _ruleIds.push(ruleId);
        _ruleCount++;

        emit RuleProposed(ruleId, address(0), severity, slashBps);
        emit RuleActivated(ruleId, type(uint256).max);
    }
}
