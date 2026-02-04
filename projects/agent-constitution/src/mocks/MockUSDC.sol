// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC - Mock USDC token for testing
/// @notice Simple ERC20 token with public mint function for testing purposes
contract MockUSDC is ERC20 {
    /// @notice Creates a new MockUSDC token
    constructor() ERC20("USD Coin", "USDC") {}

    /// @notice Returns the number of decimals for the token
    /// @return The number of decimals (6, matching real USDC)
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint tokens to an address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}