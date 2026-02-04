// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAgentRegistry} from "../interfaces/IAgentRegistry.sol";
import {IIdentityRegistry8004} from "../interfaces/IIdentityRegistry8004.sol";
import {Constants} from "../libraries/Constants.sol";

/// @title AgentRegistry - Staking & enforcement layer for ERC-8004 agent identities
/// @notice Extends ERC-8004 Identity Registry with USDC staking, capability tiers,
///         and compliance enforcement. Identity lives in the ERC-8004 singleton;
///         this contract handles the economic security layer.
/// @dev Agents first register via ERC-8004, then bind their identity here with stake.
///      The agentId is the ERC-8004 tokenId — one identity system, no wheel reinvention.
contract AgentRegistry is AccessControl, Pausable, ReentrancyGuard, IAgentRegistry {
    using SafeERC20 for IERC20;

    // ── Roles ──────────────────────────────────────────────────────
    bytes32 public constant TRIBUNAL_ROLE = keccak256("TRIBUNAL_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ── Immutables ─────────────────────────────────────────────────
    IERC20 public immutable USDC;
    IIdentityRegistry8004 public immutable IDENTITY;

    // ── State ──────────────────────────────────────────────────────
    mapping(uint256 => AgentProfile) private _agents;
    uint256 private _totalBound;

    // ── Events ─────────────────────────────────────────────────────
    event AgentBound(uint256 indexed agentId, address indexed operator, CapabilityTier tier, uint256 staked);

    // ── Errors ─────────────────────────────────────────────────────
    error NotIdentityOwner(uint256 agentId, address caller);
    error AgentAlreadyBound(uint256 agentId);
    error AgentNotBound(uint256 agentId);

    /// @notice Deploy with ERC-8004 Identity Registry + USDC addresses
    /// @param USDC_ USDC token (6 decimals)
    /// @param IDENTITY_ ERC-8004 IdentityRegistry singleton address
    /// @param ADMIN_ Admin address for role management
    constructor(address USDC_, address IDENTITY_, address ADMIN_) {
        if (USDC_ == address(0) || IDENTITY_ == address(0) || ADMIN_ == address(0)) {
            revert ZeroAddress();
        }

        USDC = IERC20(USDC_);
        IDENTITY = IIdentityRegistry8004(IDENTITY_);

        _grantRole(DEFAULT_ADMIN_ROLE, ADMIN_);
        _grantRole(ADMIN_ROLE, ADMIN_);
        _grantRole(TRIBUNAL_ROLE, ADMIN_);
    }

    // ── Registration ───────────────────────────────────────────────

    /// @notice Bind an existing ERC-8004 identity to the Constitution with stake
    /// @dev Caller must be the ERC-8004 NFT owner/approved. The agentId IS the ERC-8004 tokenId.
    /// @param operator Address that controls the agent (usually the ERC-8004 owner)
    /// @param name Human-readable name
    /// @param metadataURI URI for off-chain metadata (mirrors ERC-8004 agentURI)
    /// @param tier Capability tier determining minimum stake
    /// @param stakeAmount USDC to stake (must meet tier minimum)
    /// @return agentId The ERC-8004 tokenId (passed through)
    function registerAgent(
        address operator,
        string calldata name,
        string calldata metadataURI,
        CapabilityTier tier,
        uint256 stakeAmount
    ) external nonReentrant whenNotPaused returns (uint256 agentId) {
        if (operator == address(0)) revert ZeroAddress();

        uint256 required = minimumStake(tier);
        if (stakeAmount < required) {
            revert InsufficientStake(required, stakeAmount);
        }

        // Register on ERC-8004 — mints NFT to msg.sender
        agentId = IDENTITY.register(metadataURI);

        // Ensure not already bound (shouldn't happen with fresh mint, but defense in depth)
        if (_agents[agentId].registeredAt != 0) revert AgentAlreadyBound(agentId);

        // Take USDC stake
        USDC.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // Store profile
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

        _totalBound++;

        emit AgentRegistered(agentId, operator, name, tier, stakeAmount);
        emit AgentBound(agentId, operator, tier, stakeAmount);
    }

    /// @notice Bind an already-minted ERC-8004 identity (for agents that registered on 8004 first)
    /// @param agentId Existing ERC-8004 tokenId
    /// @param name Human-readable name
    /// @param tier Capability tier
    /// @param stakeAmount USDC to stake
    function bindExistingAgent(
        uint256 agentId,
        string calldata name,
        CapabilityTier tier,
        uint256 stakeAmount
    ) external nonReentrant whenNotPaused {
        // Verify caller owns or is approved for this ERC-8004 identity
        if (!IDENTITY.isAuthorizedOrOwner(msg.sender, agentId)) {
            revert NotIdentityOwner(agentId, msg.sender);
        }

        if (_agents[agentId].registeredAt != 0) revert AgentAlreadyBound(agentId);

        uint256 required = minimumStake(tier);
        if (stakeAmount < required) {
            revert InsufficientStake(required, stakeAmount);
        }

        USDC.safeTransferFrom(msg.sender, address(this), stakeAmount);

        address identityOwner = IDENTITY.ownerOf(agentId);
        string memory uri = IDENTITY.tokenURI(agentId);

        _agents[agentId] = AgentProfile({
            operator: identityOwner,
            name: name,
            metadataURI: uri,
            tier: tier,
            status: AgentStatus.ACTIVE,
            stakedAmount: stakeAmount,
            registeredAt: block.timestamp,
            violationCount: 0,
            totalSlashed: 0
        });

        _totalBound++;

        emit AgentRegistered(agentId, identityOwner, name, tier, stakeAmount);
        emit AgentBound(agentId, identityOwner, tier, stakeAmount);
    }

    // ── Staking ────────────────────────────────────────────────────

    /// @notice Add USDC stake to an agent
    function addStake(uint256 agentId, uint256 amount) external nonReentrant whenNotPaused {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);
        if (amount == 0) revert InsufficientStake(1, 0);

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        _agents[agentId].stakedAmount += amount;

        emit StakeAdded(agentId, amount, _agents[agentId].stakedAmount);
    }

    /// @notice Slash stake — callable only by Tribunal
    /// @param agentId Agent to slash
    /// @param bps Slash percentage in basis points
    /// @return slashed Actual USDC amount slashed
    function slashStake(uint256 agentId, uint256 bps)
        external
        onlyRole(TRIBUNAL_ROLE)
        nonReentrant
        returns (uint256 slashed)
    {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);
        if (bps > Constants.MAX_SLASH_BPS) revert InsufficientStake(Constants.MAX_SLASH_BPS, bps);

        AgentProfile storage agent = _agents[agentId];
        slashed = (agent.stakedAmount * bps) / Constants.BPS;
        agent.stakedAmount -= slashed;
        agent.totalSlashed += slashed;
        agent.violationCount++;

        if (slashed > 0) {
            USDC.safeTransfer(msg.sender, slashed);
        }

        emit StakeSlashed(agentId, slashed, agent.stakedAmount);
    }

    // ── Status ─────────────────────────────────────────────────────

    /// @notice Set agent status (admin/killswitch only)
    function setAgentStatus(uint256 agentId, AgentStatus newStatus) external onlyRole(ADMIN_ROLE) {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);

        AgentProfile storage agent = _agents[agentId];
        if (agent.status == AgentStatus.TERMINATED) revert AgentAlreadyTerminated(agentId);

        AgentStatus old = agent.status;
        agent.status = newStatus;

        emit AgentStatusChanged(agentId, old, newStatus);
    }

    // ── Views ──────────────────────────────────────────────────────

    /// @notice Check if agent is active + meets minimum stake for its tier
    function isCompliant(uint256 agentId) external view returns (bool) {
        if (!agentExists(agentId)) return false;
        AgentProfile storage a = _agents[agentId];
        return a.status == AgentStatus.ACTIVE && a.stakedAmount >= minimumStake(a.tier);
    }

    function getAgent(uint256 agentId) external view returns (AgentProfile memory) {
        if (!agentExists(agentId)) revert AgentNotFound(agentId);
        return _agents[agentId];
    }

    function agentExists(uint256 agentId) public view returns (bool) {
        return _agents[agentId].registeredAt != 0;
    }

    function minimumStake(CapabilityTier tier) public pure returns (uint256) {
        if (tier == CapabilityTier.BASIC) return Constants.STAKE_BASIC;
        if (tier == CapabilityTier.STANDARD) return Constants.STAKE_STANDARD;
        if (tier == CapabilityTier.ADVANCED) return Constants.STAKE_ADVANCED;
        if (tier == CapabilityTier.AUTONOMOUS) return Constants.STAKE_AUTONOMOUS;
        revert InvalidTier();
    }

    function totalAgents() external view returns (uint256) {
        return _totalBound;
    }

    // ── Admin ──────────────────────────────────────────────────────

    function pause() external onlyRole(ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(ADMIN_ROLE) { _unpause(); }
}
