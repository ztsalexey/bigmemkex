// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAgentRegistry.sol";
import "../interfaces/IConstitution.sol";
import "../libraries/Constants.sol";

/// @title AgentRegistry - ERC721-based registry for AI agents with staking
/// @notice Manages agent identities, staking requirements, and compliance status
/// @dev Each agent is represented as an NFT with associated staking and profile data
contract AgentRegistry is ERC721, AccessControl, Pausable, ReentrancyGuard, IAgentRegistry {
    using SafeERC20 for IERC20;

    /// @notice Role for tribunal actions (slashing)
    bytes32 public constant TRIBUNAL_ROLE = keccak256("TRIBUNAL_ROLE");

    /// @notice Role for administrative actions (status changes)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice USDC token contract for staking
    IERC20 public immutable usdcToken;

    /// @notice Constitution contract for rule compliance
    IConstitution public immutable constitution;

    /// @notice Next token ID to be minted (starts at 1)
    uint256 private _nextTokenId = 1;

    /// @notice Mapping from agent ID to profile data
    mapping(uint256 => AgentProfile) private _agents;

    /// @notice Constructor initializes the registry with USDC and Constitution contracts
    /// @param usdcAddress Address of the USDC token contract
    /// @param constitutionAddress Address of the Constitution contract
    /// @param admin Address that will receive all administrative roles
    constructor(
        address usdcAddress,
        address constitutionAddress,
        address admin
    ) ERC721("AgentConstitution Registry", "AGENT") {
        if (usdcAddress == address(0) || constitutionAddress == address(0) || admin == address(0)) {
            revert InsufficientStake(0, 0); // Reusing error for zero address validation
        }

        usdcToken = IERC20(usdcAddress);
        constitution = IConstitution(constitutionAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(TRIBUNAL_ROLE, admin);
    }

    /// @notice Registers a new agent with required stake
    /// @param operator Address that will control the agent
    /// @param name Human-readable name for the agent
    /// @param metadataURI URI pointing to agent metadata
    /// @param tier Capability tier determining stake requirements
    /// @param stakeAmount Amount of USDC to stake
    /// @return agentId Newly minted agent NFT ID
    function registerAgent(
        address operator,
        string calldata name,
        string calldata metadataURI,
        CapabilityTier tier,
        uint256 stakeAmount
    ) external nonReentrant whenNotPaused returns (uint256 agentId) {
        if (operator == address(0)) revert InsufficientStake(0, 0); // Reusing error for zero address
        
        uint256 requiredStake = minimumStake(tier);
        if (stakeAmount < requiredStake) {
            revert InsufficientStake(requiredStake, stakeAmount);
        }

        agentId = _nextTokenId++;
        
        // Transfer stake from sender
        usdcToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // Create agent profile
        _agents[agentId] = AgentProfile({
            operator: operator,
            name: name,
            metadataURI: metadataURI,
            tier: tier,
            status: AgentStatus.ACTIVE,
            stakedAmount: stakeAmount,
            registeredAt: block.timestamp,
            violationCount: 0,
            totalSlashed: 0
        });

        // Mint NFT to the operator
        _safeMint(operator, agentId);

        emit AgentRegistered(agentId, operator, name, tier, stakeAmount);
    }

    /// @notice Adds additional stake to an existing agent
    /// @param agentId ID of the agent to add stake for
    /// @param amount Amount of USDC to add
    function addStake(uint256 agentId, uint256 amount) external nonReentrant whenNotPaused {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);
        if (amount == 0) revert InsufficientStake(1, 0);

        AgentProfile storage agent = _agents[agentId];
        
        // Transfer additional stake
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        
        agent.stakedAmount += amount;

        emit StakeAdded(agentId, amount, agent.stakedAmount);
    }

    /// @notice Slashes stake from an agent for rule violations
    /// @param agentId ID of the agent to slash
    /// @param bps Percentage to slash in basis points (e.g., 1000 = 10%)
    /// @return slashed Amount of USDC slashed
    function slashStake(uint256 agentId, uint256 bps) external onlyRole(TRIBUNAL_ROLE) nonReentrant returns (uint256 slashed) {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);
        if (bps > Constants.MAX_SLASH_BPS) revert InsufficientStake(Constants.MAX_SLASH_BPS, bps); // Reusing error

        AgentProfile storage agent = _agents[agentId];
        
        slashed = (agent.stakedAmount * bps) / Constants.BPS;
        agent.stakedAmount -= slashed;
        agent.totalSlashed += slashed;
        agent.violationCount++;

        // Transfer slashed amount to caller (tribunal)
        if (slashed > 0) {
            usdcToken.safeTransfer(msg.sender, slashed);
        }

        emit StakeSlashed(agentId, slashed, agent.stakedAmount);
    }

    /// @notice Sets the status of an agent
    /// @param agentId ID of the agent
    /// @param newStatus New status to set
    function setAgentStatus(uint256 agentId, AgentStatus newStatus) external onlyRole(ADMIN_ROLE) {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);

        AgentProfile storage agent = _agents[agentId];
        AgentStatus oldStatus = agent.status;
        
        if (oldStatus == AgentStatus.TERMINATED) {
            revert AgentAlreadyTerminated(agentId);
        }

        agent.status = newStatus;

        emit AgentStatusChanged(agentId, oldStatus, newStatus);
    }

    /// @notice Checks if an agent is compliant (active and has minimum stake)
    /// @param agentId ID of the agent to check
    /// @return true if agent is active and has sufficient stake for its tier
    function isCompliant(uint256 agentId) external view returns (bool) {
        if (!agentExists(agentId)) return false;

        AgentProfile storage agent = _agents[agentId];
        
        return agent.status == AgentStatus.ACTIVE && 
               agent.stakedAmount >= minimumStake(agent.tier);
    }

    /// @notice Gets complete agent profile data
    /// @param agentId ID of the agent
    /// @return agent Complete agent profile struct
    function getAgent(uint256 agentId) external view returns (AgentProfile memory agent) {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);
        return _agents[agentId];
    }

    /// @notice Checks if an agent exists
    /// @param agentId ID to check
    /// @return true if agent exists (NFT has been minted)
    function agentExists(uint256 agentId) public view returns (bool) {
        return _ownerOf(agentId) != address(0);
    }

    /// @notice Gets minimum stake required for a capability tier
    /// @param tier Capability tier to check
    /// @return Minimum stake amount in USDC (6 decimals)
    function minimumStake(CapabilityTier tier) public pure returns (uint256) {
        if (tier == CapabilityTier.BASIC) return Constants.STAKE_BASIC;
        if (tier == CapabilityTier.STANDARD) return Constants.STAKE_STANDARD;
        if (tier == CapabilityTier.ADVANCED) return Constants.STAKE_ADVANCED;
        if (tier == CapabilityTier.AUTONOMOUS) return Constants.STAKE_AUTONOMOUS;
        revert InvalidTier();
    }

    /// @notice Gets total number of agents registered
    /// @return Total number of minted agent NFTs
    function totalAgents() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /// @notice Pauses the contract (admin only)
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract (admin only)
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Returns token URI for an agent NFT
    /// @param tokenId Agent ID
    /// @return URI pointing to agent metadata
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!agentExists(tokenId)) revert AgentNotFound(tokenId);
        return _agents[tokenId].metadataURI;
    }

    /// @notice See {IERC165-supportsInterface}
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Hook called before token transfers
    /// @dev Prevents transfers when paused
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
}