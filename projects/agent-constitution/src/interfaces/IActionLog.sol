// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IActionLog - Interface for agent action transparency
interface IActionLog {
    enum ActionType { COMMUNICATION, FINANCIAL, EXECUTION, DATA_ACCESS, SYSTEM_MODIFY, GOVERNANCE }
    enum RiskLevel { LOW, MEDIUM, HIGH, CRITICAL }
    enum ActionStatus { LOGGED, PENDING, APPROVED, REJECTED }

    struct ActionRecord {
        uint256 agentId;
        ActionType actionType;
        RiskLevel riskLevel;
        ActionStatus status;
        bytes32 contextHash;
        uint256 timestamp;
        address approver;
        string description;
    }

    event ActionLogged(uint256 indexed actionId, uint256 indexed agentId, ActionType actionType, RiskLevel riskLevel);
    event ApprovalRequested(uint256 indexed actionId, uint256 indexed agentId, address indexed operator);
    event ActionApproved(uint256 indexed actionId, address indexed approver);
    event ActionRejected(uint256 indexed actionId, address indexed rejector);

    error AgentNotRegistered(uint256 agentId);
    error AgentNotActive(uint256 agentId);
    error ActionNotFound(uint256 actionId);
    error ActionNotPending(uint256 actionId);
    error NotAuthorizedApprover(uint256 actionId, address caller);

    function logAction(
        uint256 agentId,
        ActionType actionType,
        RiskLevel riskLevel,
        bytes32 contextHash,
        string calldata description
    ) external returns (uint256 actionId);

    function requestApproval(
        uint256 agentId,
        ActionType actionType,
        bytes32 contextHash,
        string calldata description
    ) external returns (uint256 actionId);

    function resolveAction(uint256 actionId, bool approved) external;
    function getAction(uint256 actionId) external view returns (ActionRecord memory);
    function getAgentActionCount(uint256 agentId) external view returns (uint256);
}
