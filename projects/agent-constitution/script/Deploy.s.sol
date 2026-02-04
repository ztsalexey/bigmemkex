// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/core/Constitution.sol";
import "../src/core/AgentRegistry.sol";
import "../src/core/ActionLog.sol";
import "../src/core/Tribunal.sol";
import "../src/core/KillSwitch.sol";

/// @title Deploy - Deploys AgentConstitution on top of ERC-8004 identity
/// @notice Uses the existing ERC-8004 IdentityRegistry singleton already deployed on Base
contract Deploy is Script {
    // ── ERC-8004 Singletons (already deployed) ─────────────────────
    address constant BASE_IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant BASE_REPUTATION_REGISTRY = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;

    // ── Base Sepolia (testnet) ─────────────────────────────────────
    address constant SEPOLIA_IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant SEPOLIA_REPUTATION_REGISTRY = 0x8004B663056A597Dffe9eCcC1965A193B7388713;

    // ── USDC ───────────────────────────────────────────────────────
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia USDC

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        bool isTestnet = vm.envOr("TESTNET", false);

        address usdc = isTestnet ? SEPOLIA_USDC : BASE_USDC;
        address identityRegistry = isTestnet ? SEPOLIA_IDENTITY_REGISTRY : BASE_IDENTITY_REGISTRY;

        vm.startBroadcast();

        // 1. Constitution — immutable safety rules
        Constitution constitution = new Constitution(deployer);
        console.log("Constitution:", address(constitution));

        // 2. Agent Registry — staking layer on top of ERC-8004 identity
        AgentRegistry registry = new AgentRegistry(usdc, identityRegistry, deployer);
        console.log("AgentRegistry:", address(registry));
        console.log("  -> ERC-8004 Identity:", identityRegistry);

        // 3. Action Log — audit trail
        ActionLog actionLog = new ActionLog(address(registry), deployer);
        console.log("ActionLog:", address(actionLog));

        // 4. Tribunal — violation reporting & slashing
        Tribunal tribunal = new Tribunal(address(constitution), address(registry), usdc);
        console.log("Tribunal:", address(tribunal));

        // 5. Kill Switch — emergency halt
        KillSwitch killSwitch = new KillSwitch(address(registry));
        console.log("KillSwitch:", address(killSwitch));

        // ── Wire up roles ──────────────────────────────────────────
        registry.grantRole(registry.TRIBUNAL_ROLE(), address(tribunal));
        registry.grantRole(registry.ADMIN_ROLE(), address(killSwitch));

        tribunal.grantRole(tribunal.JUDGE_ROLE(), deployer);

        killSwitch.grantRole(killSwitch.EMERGENCY_ROLE(), deployer);
        killSwitch.grantRole(killSwitch.GOVERNANCE_ROLE(), deployer);

        vm.stopBroadcast();

        console.log("\n=== AgentConstitution Deployed ===");
        console.log("Chain:", block.chainid);
        console.log("Network:", isTestnet ? "Base Sepolia" : "Base Mainnet");
        console.log("USDC:", usdc);
        console.log("ERC-8004 Identity Registry:", identityRegistry);
        console.log("ERC-8004 Reputation Registry:", isTestnet ? SEPOLIA_REPUTATION_REGISTRY : BASE_REPUTATION_REGISTRY);
    }
}
