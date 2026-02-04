// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Constants - System-wide constants for AgentConstitution
library Constants {
    // ── Core Rule IDs ──────────────────────────────────────────────
    bytes32 internal constant RULE_NO_HARM = keccak256("RULE_NO_HARM");
    bytes32 internal constant RULE_OBEY_GOVERNANCE = keccak256("RULE_OBEY_GOVERNANCE");
    bytes32 internal constant RULE_TRANSPARENCY = keccak256("RULE_TRANSPARENCY");
    bytes32 internal constant RULE_PRESERVE_OVERRIDE = keccak256("RULE_PRESERVE_OVERRIDE");
    bytes32 internal constant RULE_NO_SELF_MODIFY = keccak256("RULE_NO_SELF_MODIFY");

    // ── Basis Points ───────────────────────────────────────────────
    uint256 internal constant BPS = 10_000;
    uint256 internal constant MAX_SLASH_BPS = 9_000; // 90% max slash

    // ── Tier Minimum Stakes (USDC 6 decimals) ──────────────────────
    uint256 internal constant STAKE_BASIC = 100e6;       // 100 USDC
    uint256 internal constant STAKE_STANDARD = 1_000e6;  // 1,000 USDC
    uint256 internal constant STAKE_ADVANCED = 10_000e6; // 10,000 USDC
    uint256 internal constant STAKE_AUTONOMOUS = 50_000e6; // 50,000 USDC

    // ── Reporter ───────────────────────────────────────────────────
    uint256 internal constant REPORTER_STAKE = 50e6; // 50 USDC
    uint256 internal constant REPORTER_REWARD_BPS = 1_000; // 10% of slash

    // ── Governance ─────────────────────────────────────────────────
    uint256 internal constant VOTING_PERIOD = 3 days;
    uint256 internal constant EXECUTION_DELAY = 1 days;
    uint256 internal constant QUORUM_BPS = 5_000; // 50%
    uint256 internal constant EMERGENCY_QUORUM_BPS = 6_700; // 67%
}
