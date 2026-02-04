// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IKillSwitch - Interface for emergency halt mechanism
interface IKillSwitch {
    enum HaltReason { SECURITY_BREACH, CRITICAL_VIOLATION, SYSTEM_UPGRADE, GOVERNANCE_ORDER }

    event AgentHalted(uint256 indexed agentId, HaltReason reason, address indexed haltedBy);
    event AgentUnhalted(uint256 indexed agentId, address indexed unhaltedBy);
    event GlobalEmergency(HaltReason reason, address indexed triggeredBy);
    event GlobalEmergencyLifted(address indexed liftedBy);

    error AgentAlreadyHalted(uint256 agentId);
    error AgentNotHalted(uint256 agentId);
    error GlobalEmergencyActive();
    error NoGlobalEmergency();
    error InsufficientVotes();

    function haltAgent(uint256 agentId, HaltReason reason) external;
    function unhaltAgent(uint256 agentId) external;
    function triggerGlobalEmergency(HaltReason reason) external;
    function liftGlobalEmergency() external;
    function isAgentHalted(uint256 agentId) external view returns (bool);
    function isGlobalEmergency() external view returns (bool);
    function canOperate(uint256 agentId) external view returns (bool);
}
