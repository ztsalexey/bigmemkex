// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITribunal} from "../interfaces/ITribunal.sol";
import {IConstitution} from "../interfaces/IConstitution.sol";
import {IAgentRegistry} from "../interfaces/IAgentRegistry.sol";
import {Constants} from "../libraries/Constants.sol";

/// @title Tribunal - Violation reporting and slashing mechanism
/// @notice Manages violation reports, evidence, and punishment enforcement
contract Tribunal is AccessControl, ReentrancyGuard, ITribunal {
    using SafeERC20 for IERC20;

    bytes32 public constant JUDGE_ROLE = keccak256("JUDGE_ROLE");

    IConstitution public immutable constitution;
    IAgentRegistry public immutable agentRegistry;
    IERC20 public immutable usdc;

    uint256 private _nextReportId = 1;
    mapping(uint256 => ViolationReport) private _reports;
    mapping(uint256 => uint256) private _agentReportCounts;

    /// @notice Creates a new Tribunal instance
    /// @param _constitution Address of the Constitution contract
    /// @param _agentRegistry Address of the AgentRegistry contract
    /// @param _usdc Address of the USDC token contract
    constructor(
        address _constitution,
        address _agentRegistry,
        address _usdc
    ) {
        constitution = IConstitution(_constitution);
        agentRegistry = IAgentRegistry(_agentRegistry);
        usdc = IERC20(_usdc);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Report a violation by an agent
    /// @param agentId The ID of the agent being reported
    /// @param ruleId The rule that was allegedly violated
    /// @param evidenceType Type of evidence provided
    /// @param evidenceHash Hash of the evidence
    /// @param evidenceURI URI to access the evidence
    /// @param description Description of the violation
    /// @return reportId The ID of the created report
    function reportViolation(
        uint256 agentId,
        bytes32 ruleId,
        EvidenceType evidenceType,
        bytes32 evidenceHash,
        string calldata evidenceURI,
        string calldata description
    ) external nonReentrant returns (uint256 reportId) {
        // Validate rule is active
        if (!constitution.isRuleActive(ruleId)) {
            revert RuleNotActive(ruleId);
        }

        // Validate agent exists
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotActive(agentId);
        }

        // Validate agent is active
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        if (agent.status != IAgentRegistry.AgentStatus.ACTIVE) {
            revert AgentNotActive(agentId);
        }

        // Collect reporter stake
        usdc.safeTransferFrom(msg.sender, address(this), Constants.REPORTER_STAKE);

        reportId = _nextReportId++;
        
        _reports[reportId] = ViolationReport({
            agentId: agentId,
            reporter: msg.sender,
            ruleId: ruleId,
            evidenceType: evidenceType,
            evidenceHash: evidenceHash,
            evidenceURI: evidenceURI,
            status: ReportStatus.SUBMITTED,
            reporterStake: Constants.REPORTER_STAKE,
            submittedAt: block.timestamp,
            resolvedAt: 0,
            resolution: description
        });

        emit ViolationReported(reportId, agentId, ruleId, msg.sender);
    }

    /// @notice Resolve a violation report
    /// @param reportId The ID of the report to resolve
    /// @param isViolation Whether the report is valid and a violation occurred
    /// @param resolution Description of the resolution
    function resolveReport(
        uint256 reportId,
        bool isViolation,
        string calldata resolution
    ) external onlyRole(JUDGE_ROLE) nonReentrant {
        ViolationReport storage report = _reports[reportId];
        
        if (report.submittedAt == 0) {
            revert ReportNotFound(reportId);
        }
        
        if (report.status != ReportStatus.SUBMITTED) {
            revert ReportAlreadyResolved(reportId);
        }

        report.resolvedAt = block.timestamp;
        report.resolution = resolution;

        if (isViolation) {
            // Accept the violation report
            report.status = ReportStatus.ACCEPTED;
            
            // Calculate and execute slash
            (uint256 slashAmount, ) = calculateSlash(report.agentId, report.ruleId);
            uint256 actualSlashed = agentRegistry.slashStake(report.agentId, slashAmount);
            
            // Reward reporter with percentage of slashed amount
            uint256 rewardAmount = (actualSlashed * Constants.REPORTER_REWARD_BPS) / Constants.BPS;
            if (rewardAmount > 0) {
                usdc.safeTransfer(report.reporter, rewardAmount);
                emit ReporterRewarded(reportId, report.reporter, rewardAmount);
            }

            // Return reporter's stake
            usdc.safeTransfer(report.reporter, report.reporterStake);

            // Increment violation count
            _agentReportCounts[report.agentId]++;

            emit ReportResolved(reportId, ReportStatus.ACCEPTED, actualSlashed);
        } else {
            // Reject the report - reporter loses stake
            report.status = ReportStatus.REJECTED;
            emit ReporterSlashed(reportId, report.reporter, report.reporterStake);
            emit ReportResolved(reportId, ReportStatus.REJECTED, 0);
        }
    }

    /// @notice Calculate the slash amount for an agent and rule violation
    /// @param agentId The agent ID
    /// @param ruleId The rule that was violated
    /// @return slashAmount The amount to slash in basis points
    /// @return slashBps The slash percentage in basis points
    function calculateSlash(uint256 agentId, bytes32 ruleId) 
        public 
        view 
        returns (uint256 slashAmount, uint256 slashBps) 
    {
        IConstitution.Rule memory rule = constitution.getRule(ruleId);
        uint256 violationCount = _agentReportCounts[agentId];
        
        // Base slash from rule
        slashBps = rule.slashBps;
        
        // Add repeat offender multiplier (500 bps per previous violation)
        slashBps += violationCount * 500;
        
        // Cap at maximum slash
        if (slashBps > Constants.MAX_SLASH_BPS) {
            slashBps = Constants.MAX_SLASH_BPS;
        }
        
        slashAmount = slashBps;
    }

    /// @notice Get a violation report by ID
    /// @param reportId The report ID
    /// @return The violation report
    function getReport(uint256 reportId) external view returns (ViolationReport memory) {
        ViolationReport memory report = _reports[reportId];
        if (report.submittedAt == 0) {
            revert ReportNotFound(reportId);
        }
        return report;
    }

    /// @notice Get the number of violation reports for an agent
    /// @param agentId The agent ID
    /// @return The number of reports
    function getAgentReportCount(uint256 agentId) external view returns (uint256) {
        return _agentReportCounts[agentId];
    }
}