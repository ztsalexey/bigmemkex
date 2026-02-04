// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IActionLog} from "../interfaces/IActionLog.sol";
import {IAgentRegistry} from "../interfaces/IAgentRegistry.sol";

/// @title ActionLog - Transparency logging for agent actions
/// @notice Records all agent actions with risk-based approval workflows
/// @dev Provides immutable audit trail for agent behavior analysis
contract ActionLog is AccessControl, Pausable, IActionLog {
    /// @notice Agent registry for validation
    IAgentRegistry public immutable agentRegistry;

    /// @notice Next action ID to be assigned (starts at 1)
    uint256 private _nextActionId = 1;

    /// @notice Mapping from action ID to action record
    mapping(uint256 => ActionRecord) private _actions;

    /// @notice Mapping from agent ID to count of actions
    mapping(uint256 => uint256) private _agentActionCounts;

    /// @notice Constructor initializes with agent registry
    /// @param agentRegistryAddress Address of the AgentRegistry contract
    /// @param admin Address that will receive DEFAULT_ADMIN_ROLE
    constructor(address agentRegistryAddress, address admin) {
        if (agentRegistryAddress == address(0) || admin == address(0)) {
            revert AgentNotRegistered(0); // NOTE: Should use ZeroAddress() but keeping for interface compatibility
        }

        agentRegistry = IAgentRegistry(agentRegistryAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Logs an action performed by an agent
    /// @param agentId ID of the agent performing the action
    /// @param actionType Type of action being performed
    /// @param riskLevel Risk level of the action
    /// @param contextHash Hash of the action context/parameters
    /// @param description Human-readable description of the action
    /// @return actionId Unique ID assigned to this action
    function logAction(
        uint256 agentId,
        ActionType actionType,
        RiskLevel riskLevel,
        bytes32 contextHash,
        string calldata description
    ) external whenNotPaused returns (uint256 actionId) {
        // Validate agent exists and is registered
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotRegistered(agentId);
        }

        // Get agent profile to verify status
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        
        // Agent must be active to log actions
        if (agent.status != IAgentRegistry.AgentStatus.ACTIVE) {
            revert AgentNotActive(agentId);
        }

        // Only the agent operator can log actions for the agent
        if (msg.sender != agent.operator) {
            revert AgentNotRegistered(agentId); // NOTE: Could use NotAuthorized error, keeping for compatibility
        }

        actionId = _nextActionId++;

        // Create action record
        _actions[actionId] = ActionRecord({
            agentId: agentId,
            actionType: actionType,
            riskLevel: riskLevel,
            status: ActionStatus.LOGGED,
            contextHash: contextHash,
            timestamp: block.timestamp,
            approver: address(0),
            description: description
        });

        // Increment agent's action count
        _agentActionCounts[agentId]++;

        emit ActionLogged(actionId, agentId, actionType, riskLevel);
    }

    /// @notice Requests approval for a high-risk action
    /// @param agentId ID of the agent requesting approval
    /// @param actionType Type of action requiring approval
    /// @param contextHash Hash of the action context/parameters
    /// @param description Human-readable description of the action
    /// @return actionId Unique ID assigned to this pending action
    function requestApproval(
        uint256 agentId,
        ActionType actionType,
        bytes32 contextHash,
        string calldata description
    ) external whenNotPaused returns (uint256 actionId) {
        // Validate agent exists and is registered
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotRegistered(agentId);
        }

        // Get agent profile to verify status
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        
        // Agent must be active to request approval
        if (agent.status != IAgentRegistry.AgentStatus.ACTIVE) {
            revert AgentNotActive(agentId);
        }

        actionId = _nextActionId++;

        // Create pending action record - approval requests are automatically HIGH/CRITICAL risk
        _actions[actionId] = ActionRecord({
            agentId: agentId,
            actionType: actionType,
            riskLevel: RiskLevel.HIGH, // Approval requests are inherently high risk
            status: ActionStatus.PENDING,
            contextHash: contextHash,
            timestamp: block.timestamp,
            approver: address(0),
            description: description
        });

        // Increment agent's action count
        _agentActionCounts[agentId]++;

        emit ApprovalRequested(actionId, agentId, agent.operator);
    }

    /// @notice Resolves a pending action with approval or rejection
    /// @param actionId ID of the action to resolve
    /// @param approved true to approve, false to reject
    function resolveAction(uint256 actionId, bool approved) external whenNotPaused {
        if (actionId == 0 || actionId >= _nextActionId) {
            revert ActionNotFound(actionId);
        }

        ActionRecord storage action = _actions[actionId];
        
        if (action.status != ActionStatus.PENDING) {
            revert ActionNotPending(actionId);
        }

        // Get agent profile to check operator
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(action.agentId);
        
        // Only the agent operator can resolve actions for their agent
        if (msg.sender != agent.operator) {
            revert NotAuthorizedApprover(actionId, msg.sender);
        }

        // Update action status
        action.status = approved ? ActionStatus.APPROVED : ActionStatus.REJECTED;
        action.approver = msg.sender;

        if (approved) {
            emit ActionApproved(actionId, msg.sender);
        } else {
            emit ActionRejected(actionId, msg.sender);
        }
    }

    /// @notice Gets complete action record
    /// @param actionId ID of the action to retrieve
    /// @return action Complete action record struct
    function getAction(uint256 actionId) external view returns (ActionRecord memory action) {
        if (actionId == 0 || actionId >= _nextActionId) {
            revert ActionNotFound(actionId);
        }
        return _actions[actionId];
    }

    /// @notice Gets total number of actions logged by an agent
    /// @param agentId ID of the agent
    /// @return count Number of actions logged by this agent
    function getAgentActionCount(uint256 agentId) external view returns (uint256 count) {
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotRegistered(agentId);
        }
        return _agentActionCounts[agentId];
    }

    /// @notice Gets total number of actions logged in the system
    /// @return Total action count across all agents
    function totalActions() external view returns (uint256) {
        return _nextActionId - 1;
    }

    /// @notice Pauses the contract (admin only)
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract (admin only)
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Checks if an action exists
    /// @param actionId ID to check
    /// @return true if action exists
    function actionExists(uint256 actionId) external view returns (bool) {
        return actionId > 0 && actionId < _nextActionId;
    }

    /// @notice Gets actions by status (useful for filtering pending actions)
    /// @param status Status to filter by
    /// @param offset Starting index for pagination
    /// @param limit Maximum number of results
    /// @return actionIds Array of action IDs with the specified status
    /// @dev Warning: This function performs unbounded loops and may hit gas limits for large datasets
    function getActionsByStatus(
        ActionStatus status,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory actionIds) {
        uint256 totalActionCount = _nextActionId - 1;
        
        // Count matching actions first
        uint256 matchCount = 0;
        for (uint256 i = 1; i <= totalActionCount;) {
            if (_actions[i].status == status) {
                matchCount++;
            }
            unchecked { ++i; }
        }

        // Apply pagination
        uint256 startIdx = offset;
        uint256 endIdx = startIdx + limit;
        if (endIdx > matchCount) {
            endIdx = matchCount;
        }

        if (startIdx >= matchCount) {
            return new uint256[](0);
        }

        actionIds = new uint256[](endIdx - startIdx);
        uint256 currentMatch = 0;
        uint256 resultIdx = 0;

        for (uint256 i = 1; i <= totalActionCount && resultIdx < (endIdx - startIdx);) {
            if (_actions[i].status == status) {
                if (currentMatch >= startIdx) {
                    actionIds[resultIdx] = i;
                    resultIdx++;
                }
                currentMatch++;
            }
            unchecked { ++i; }
        }
    }
}