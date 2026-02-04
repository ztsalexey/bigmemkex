// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IAgentRegistry - Interface for agent identity & staking
interface IAgentRegistry {
    enum CapabilityTier { BASIC, STANDARD, ADVANCED, AUTONOMOUS }
    enum AgentStatus { INACTIVE, ACTIVE, SUSPENDED, TERMINATED }

    struct AgentProfile {
        address operator;
        string name;
        string metadataURI;
        CapabilityTier tier;
        AgentStatus status;
        uint256 stakedAmount;
        uint256 registeredAt;
        uint256 violationCount;
        uint256 totalSlashed;
    }

    event AgentRegistered(uint256 indexed agentId, address indexed operator, string name, CapabilityTier tier, uint256 staked);
    event StakeAdded(uint256 indexed agentId, uint256 amount, uint256 newTotal);
    event StakeSlashed(uint256 indexed agentId, uint256 amount, uint256 remaining);
    event StakeWithdrawn(uint256 indexed agentId, uint256 amount);
    event AgentStatusChanged(uint256 indexed agentId, AgentStatus oldStatus, AgentStatus newStatus);

    error AgentNotFound(uint256 agentId);
    error InsufficientStake(uint256 required, uint256 provided);
    error AgentNotActive(uint256 agentId);
    error NotAgentOperator(uint256 agentId, address caller);
    error InvalidTier();
    error AgentAlreadyTerminated(uint256 agentId);

    function registerAgent(
        address operator,
        string calldata name,
        string calldata metadataURI,
        CapabilityTier tier,
        uint256 stakeAmount
    ) external returns (uint256 agentId);

    function addStake(uint256 agentId, uint256 amount) external;
    function slashStake(uint256 agentId, uint256 bps) external returns (uint256 slashed);
    function setAgentStatus(uint256 agentId, AgentStatus newStatus) external;
    function isCompliant(uint256 agentId) external view returns (bool);
    function getAgent(uint256 agentId) external view returns (AgentProfile memory);
    function agentExists(uint256 agentId) external view returns (bool);
    function minimumStake(CapabilityTier tier) external view returns (uint256);
    function totalAgents() external view returns (uint256);
}
