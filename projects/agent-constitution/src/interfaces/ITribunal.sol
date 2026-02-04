// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IConstitution} from "./IConstitution.sol";

/// @title ITribunal - Interface for violation reporting & slashing
interface ITribunal {
    enum ReportStatus { SUBMITTED, ACCEPTED, REJECTED, DISPUTED }
    enum EvidenceType { TRANSACTION, LOG_ENTRY, EXTERNAL, WITNESS }

    struct ViolationReport {
        uint256 agentId;
        address reporter;
        bytes32 ruleId;
        EvidenceType evidenceType;
        bytes32 evidenceHash;
        string evidenceURI;
        ReportStatus status;
        uint256 reporterStake;
        uint256 submittedAt;
        uint256 resolvedAt;
        string resolution;
    }

    event ViolationReported(uint256 indexed reportId, uint256 indexed agentId, bytes32 indexed ruleId, address reporter);
    event ReportResolved(uint256 indexed reportId, ReportStatus status, uint256 slashedAmount);
    event ReporterRewarded(uint256 indexed reportId, address indexed reporter, uint256 reward);
    event ReporterSlashed(uint256 indexed reportId, address indexed reporter, uint256 amount);

    error ReportNotFound(uint256 reportId);
    error ReportAlreadyResolved(uint256 reportId);
    error InsufficientReporterStake(uint256 required, uint256 provided);
    error RuleNotActive(bytes32 ruleId);
    error AgentNotActive(uint256 agentId);

    function reportViolation(
        uint256 agentId,
        bytes32 ruleId,
        EvidenceType evidenceType,
        bytes32 evidenceHash,
        string calldata evidenceURI,
        string calldata description
    ) external returns (uint256 reportId);

    function resolveReport(uint256 reportId, bool isViolation, string calldata resolution) external;
    function calculateSlash(uint256 agentId, bytes32 ruleId) external view returns (uint256 slashAmount, uint256 slashBps);
    function getReport(uint256 reportId) external view returns (ViolationReport memory);
    function getAgentReportCount(uint256 agentId) external view returns (uint256);
}
