// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IKillSwitch} from "../interfaces/IKillSwitch.sol";
import {IAgentRegistry} from "../interfaces/IAgentRegistry.sol";

/// @title KillSwitch - Emergency halt mechanism for agents
/// @notice Provides emergency controls to halt individual agents or trigger system-wide emergency
contract KillSwitch is AccessControl, IKillSwitch {
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    IAgentRegistry public immutable agentRegistry;

    mapping(uint256 => bool) private _haltedAgents;
    bool private _globalEmergency;

    /// @notice Creates a new KillSwitch instance
    /// @param _agentRegistry Address of the AgentRegistry contract
    constructor(address _agentRegistry) {
        agentRegistry = IAgentRegistry(_agentRegistry);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Halt an individual agent
    /// @param agentId The ID of the agent to halt
    /// @param reason The reason for halting
    function haltAgent(uint256 agentId, HaltReason reason) external onlyRole(EMERGENCY_ROLE) {
        if (_haltedAgents[agentId]) {
            revert AgentAlreadyHalted(agentId);
        }

        _haltedAgents[agentId] = true;
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.SUSPENDED);
        
        emit AgentHalted(agentId, reason, msg.sender);
    }

    /// @notice Unhalt an individual agent
    /// @param agentId The ID of the agent to unhalt
    function unhaltAgent(uint256 agentId) external onlyRole(EMERGENCY_ROLE) {
        if (!_haltedAgents[agentId]) {
            revert AgentNotHalted(agentId);
        }

        _haltedAgents[agentId] = false;
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.ACTIVE);
        
        emit AgentUnhalted(agentId, msg.sender);
    }

    /// @notice Trigger a global emergency that halts all agents
    /// @param reason The reason for the emergency
    function triggerGlobalEmergency(HaltReason reason) external onlyRole(EMERGENCY_ROLE) {
        if (_globalEmergency) {
            revert GlobalEmergencyActive();
        }

        _globalEmergency = true;
        
        emit GlobalEmergency(reason, msg.sender);
    }

    /// @notice Lift the global emergency state
    function liftGlobalEmergency() external onlyRole(GOVERNANCE_ROLE) {
        if (!_globalEmergency) {
            revert NoGlobalEmergency();
        }

        _globalEmergency = false;
        
        emit GlobalEmergencyLifted(msg.sender);
    }

    /// @notice Check if an agent is individually halted
    /// @param agentId The agent ID to check
    /// @return True if the agent is halted
    function isAgentHalted(uint256 agentId) external view returns (bool) {
        return _haltedAgents[agentId];
    }

    /// @notice Check if there is a global emergency
    /// @return True if global emergency is active
    function isGlobalEmergency() external view returns (bool) {
        return _globalEmergency;
    }

    /// @notice Check if an agent can operate
    /// @param agentId The agent ID to check
    /// @return True if the agent can operate (not halted and no global emergency)
    function canOperate(uint256 agentId) external view returns (bool) {
        return !_haltedAgents[agentId] && !_globalEmergency;
    }
}