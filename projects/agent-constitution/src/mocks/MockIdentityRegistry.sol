// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IIdentityRegistry8004} from "../interfaces/IIdentityRegistry8004.sol";

/// @title MockIdentityRegistry - Minimal ERC-8004 mock for testing
/// @dev Mimics the deployed ERC-8004 IdentityRegistry singleton behavior
contract MockIdentityRegistry is ERC721, IIdentityRegistry8004 {
    uint256 private _lastId;
    mapping(uint256 => string) private _uris;
    mapping(uint256 => mapping(string => bytes)) private _metadata;

    constructor() ERC721("AgentIdentity", "AGENT") {}

    function register(string memory agentURI) external returns (uint256 agentId) {
        agentId = _lastId++;
        _metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        _mint(msg.sender, agentId);
        _uris[agentId] = agentURI;
    }

    function register() external returns (uint256 agentId) {
        agentId = _lastId++;
        _metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        _mint(msg.sender, agentId);
    }

    function getMetadata(uint256 agentId, string memory key) external view returns (bytes memory) {
        return _metadata[agentId][key];
    }

    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool) {
        address owner = _ownerOf(agentId);
        if (owner == address(0)) return false;
        return spender == owner || isApprovedForAll(owner, spender) || getApproved(agentId) == spender;
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        bytes memory data = _metadata[agentId]["agentWallet"];
        if (data.length == 0) return address(0);
        return address(bytes20(data));
    }

    function ownerOf(uint256 agentId) public view override(ERC721, IIdentityRegistry8004) returns (address) {
        return super.ownerOf(agentId);
    }

    function tokenURI(uint256 agentId) public view override(ERC721, IIdentityRegistry8004) returns (string memory) {
        return _uris[agentId];
    }
}
