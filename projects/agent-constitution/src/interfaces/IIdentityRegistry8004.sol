// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IIdentityRegistry8004 - Minimal interface for ERC-8004 Identity Registry
/// @notice Read-only interface to interact with the deployed ERC-8004 singleton
/// @dev See https://eips.ethereum.org/EIPS/eip-8004
interface IIdentityRegistry8004 {
    /// @notice Register a new agent with URI
    function register(string memory agentURI) external returns (uint256 agentId);

    /// @notice Get the owner of an agent NFT
    function ownerOf(uint256 agentId) external view returns (address);

    /// @notice Get agent metadata
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);

    /// @notice Check if spender is owner or approved
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);

    /// @notice Get the agent's wallet address
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Get agent URI
    function tokenURI(uint256 agentId) external view returns (string memory);
}
