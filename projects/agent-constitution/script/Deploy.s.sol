// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/core/Constitution.sol";
import "../src/core/AgentRegistry.sol";
import "../src/core/ActionLog.sol";
import "../src/core/Tribunal.sol";
import "../src/core/KillSwitch.sol";

/// @title Deploy - Deploys full AgentConstitution system
/// @notice Deploy to Base L2 with existing USDC at 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
contract Deploy is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address usdc = vm.envOr("USDC_ADDRESS", address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));

        vm.startBroadcast();

        // 1. Constitution (immutable rules)
        Constitution constitution = new Constitution(deployer);
        console.log("Constitution:", address(constitution));

        // 2. Agent Registry (identity + staking)
        AgentRegistry registry = new AgentRegistry(usdc, address(constitution), deployer);
        console.log("AgentRegistry:", address(registry));

        // 3. Action Log (audit trail)
        ActionLog actionLog = new ActionLog(address(registry), deployer);
        console.log("ActionLog:", address(actionLog));

        // 4. Tribunal (violation reporting)
        Tribunal tribunal = new Tribunal(address(constitution), address(registry), usdc);
        console.log("Tribunal:", address(tribunal));

        // 5. Kill Switch (emergency halt)
        KillSwitch killSwitch = new KillSwitch(address(registry));
        console.log("KillSwitch:", address(killSwitch));

        // Wire up roles
        registry.grantRole(registry.TRIBUNAL_ROLE(), address(tribunal));
        registry.grantRole(registry.ADMIN_ROLE(), address(killSwitch));

        tribunal.grantRole(tribunal.JUDGE_ROLE(), deployer);

        killSwitch.grantRole(killSwitch.EMERGENCY_ROLE(), deployer);
        killSwitch.grantRole(killSwitch.GOVERNANCE_ROLE(), deployer);

        vm.stopBroadcast();

        console.log("\n=== AgentConstitution Deployed ===");
        console.log("Chain ID:", block.chainid);
        console.log("USDC:", usdc);
    }
}
