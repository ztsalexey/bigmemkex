// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../../src/core/AgentRegistry.sol";
import {Constitution} from "../../src/core/Constitution.sol";
import {Tribunal} from "../../src/core/Tribunal.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {MockIdentityRegistry} from "../../src/mocks/MockIdentityRegistry.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {ITribunal} from "../../src/interfaces/ITribunal.sol";
import {IAgentRegistry} from "../../src/interfaces/IAgentRegistry.sol";
import {IConstitution} from "../../src/interfaces/IConstitution.sol";

contract AgentConstitutionFuzzTest is Test {
    AgentRegistry agentRegistry;
    Constitution constitution;
    Tribunal tribunal;
    MockUSDC usdc;
    MockIdentityRegistry identity;

    address admin = makeAddr("admin");
    address judge = makeAddr("judge");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant MIN_STAKE = 100e6;
    uint256 constant MAX_STAKE = 10_000_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        identity = new MockIdentityRegistry();
        constitution = new Constitution(admin);
        agentRegistry = new AgentRegistry(address(usdc), address(identity), admin);
        tribunal = new Tribunal(address(constitution), address(agentRegistry), address(usdc));

        // Wire roles
        vm.startPrank(admin);
        agentRegistry.grantRole(agentRegistry.TRIBUNAL_ROLE(), address(tribunal));
        vm.stopPrank();
        tribunal.grantRole(tribunal.JUDGE_ROLE(), judge);

        // Fund
        usdc.mint(alice, MAX_STAKE * 10);
        usdc.mint(bob, MAX_STAKE * 10);
        vm.prank(alice);
        usdc.approve(address(agentRegistry), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(tribunal), type(uint256).max);
    }

    // ── Slashing never exceeds stake ───────────────────────────────

    function testFuzz_SlashNeverExceedsStake(uint256 stakeAmount, uint256 bps) public {
        stakeAmount = bound(stakeAmount, Constants.STAKE_BASIC, MAX_STAKE);
        bps = bound(bps, 1, Constants.MAX_SLASH_BPS);

        vm.prank(alice);
        uint256 agentId = agentRegistry.registerAgent(
            alice, "Fuzz", "ipfs://f",
            IAgentRegistry.CapabilityTier.BASIC, stakeAmount
        );

        vm.prank(admin);
        uint256 slashed = agentRegistry.slashStake(agentId, bps);

        assertLe(slashed, stakeAmount, "Slash must never exceed stake");
        assertEq(slashed, (stakeAmount * bps) / Constants.BPS, "Slash math must be exact");

        uint256 remaining = agentRegistry.getAgent(agentId).stakedAmount;
        assertEq(remaining, stakeAmount - slashed, "Remaining must equal stake minus slashed");
    }

    // ── Registration respects tier minimums ────────────────────────

    function testFuzz_RegistrationTierEnforcement(uint256 stakeAmount, uint8 tierRaw) public {
        tierRaw = uint8(bound(tierRaw, 0, 3));
        IAgentRegistry.CapabilityTier tier = IAgentRegistry.CapabilityTier(tierRaw);
        uint256 minimum = agentRegistry.minimumStake(tier);
        stakeAmount = bound(stakeAmount, 1e6, MAX_STAKE);

        vm.startPrank(alice);

        if (stakeAmount >= minimum) {
            uint256 agentId = agentRegistry.registerAgent(
                alice, "FuzzAgent", "ipfs://f", tier, stakeAmount
            );
            assertEq(agentRegistry.getAgent(agentId).stakedAmount, stakeAmount);
            assertTrue(agentRegistry.isCompliant(agentId));
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, minimum, stakeAmount)
            );
            agentRegistry.registerAgent(alice, "Fail", "ipfs://f", tier, stakeAmount);
        }

        vm.stopPrank();
    }

    // ── Reporter stake is always exactly REPORTER_STAKE ────────────

    function testFuzz_ReporterStakeExact(uint256 extraBalance) public {
        extraBalance = bound(extraBalance, 0, 1_000_000e6);

        // Register agent to report against
        vm.prank(alice);
        uint256 agentId = agentRegistry.registerAgent(
            alice, "Target", "ipfs://t",
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        // Give bob exactly REPORTER_STAKE + extra
        uint256 bobBalance = Constants.REPORTER_STAKE + extraBalance;
        usdc.mint(bob, bobBalance);

        vm.startPrank(bob);
        usdc.approve(address(tribunal), type(uint256).max);

        uint256 balBefore = usdc.balanceOf(bob);
        tribunal.reportViolation(
            agentId, Constants.RULE_NO_HARM,
            ITribunal.EvidenceType.TRANSACTION,
            keccak256("e"), "ipfs://e", "fuzz"
        );
        uint256 balAfter = usdc.balanceOf(bob);

        assertEq(balBefore - balAfter, Constants.REPORTER_STAKE, "Must deduct exactly REPORTER_STAKE");
        vm.stopPrank();
    }

    // ── Slash BPS cap ──────────────────────────────────────────────

    function testFuzz_CalculateSlashCapped(uint256 violationCount, uint256 baseSlash) public {
        baseSlash = bound(baseSlash, 100, Constants.MAX_SLASH_BPS);

        // Create custom rule
        bytes32 ruleId = keccak256(abi.encodePacked("FUZZ_RULE", baseSlash));
        vm.startPrank(admin);
        constitution.proposeRule(ruleId, "fuzz", IConstitution.RuleSeverity.MEDIUM, baseSlash);
        constitution.activateRule(ruleId);
        vm.stopPrank();

        // Register agent
        vm.prank(alice);
        uint256 agentId = agentRegistry.registerAgent(
            alice, "Cap", "ipfs://c",
            IAgentRegistry.CapabilityTier.AUTONOMOUS, Constants.STAKE_AUTONOMOUS
        );

        // Simulate violations through tribunal to build up report count
        violationCount = bound(violationCount, 0, 15);
        for (uint256 i = 0; i < violationCount; i++) {
            vm.prank(bob);
            uint256 rid = tribunal.reportViolation(
                agentId, ruleId,
                ITribunal.EvidenceType.TRANSACTION,
                keccak256(abi.encodePacked(i)), "ipfs://e", "v"
            );
            vm.prank(judge);
            tribunal.resolveReport(rid, true, "confirmed");

            // Top up stake to keep agent active
            vm.prank(alice);
            agentRegistry.addStake(agentId, Constants.STAKE_BASIC);
        }

        (, uint256 slashBps) = tribunal.calculateSlash(agentId, ruleId);
        assertLe(slashBps, Constants.MAX_SLASH_BPS, "BPS must be capped");

        uint256 expectedBps = baseSlash + (violationCount * 500);
        if (expectedBps > Constants.MAX_SLASH_BPS) expectedBps = Constants.MAX_SLASH_BPS;
        assertEq(slashBps, expectedBps, "BPS calculation must match");
    }

    // ── Max stake, max slash ───────────────────────────────────────

    function testFuzz_MaxStakeMaxSlash() public {
        vm.prank(alice);
        uint256 agentId = agentRegistry.registerAgent(
            alice, "Max", "ipfs://m",
            IAgentRegistry.CapabilityTier.AUTONOMOUS, MAX_STAKE
        );

        vm.prank(admin);
        uint256 slashed = agentRegistry.slashStake(agentId, Constants.MAX_SLASH_BPS);

        assertEq(slashed, (MAX_STAKE * Constants.MAX_SLASH_BPS) / Constants.BPS);
        assertEq(
            agentRegistry.getAgent(agentId).stakedAmount,
            MAX_STAKE - slashed
        );
    }

    // ── Double slash ───────────────────────────────────────────────

    function testFuzz_DoubleSlash(uint256 bps1, uint256 bps2) public {
        bps1 = bound(bps1, 100, 5000);
        bps2 = bound(bps2, 100, 5000);

        vm.prank(alice);
        uint256 agentId = agentRegistry.registerAgent(
            alice, "Double", "ipfs://d",
            IAgentRegistry.CapabilityTier.AUTONOMOUS, Constants.STAKE_AUTONOMOUS
        );

        uint256 stake0 = Constants.STAKE_AUTONOMOUS;

        vm.startPrank(admin);
        uint256 s1 = agentRegistry.slashStake(agentId, bps1);
        uint256 stake1 = stake0 - s1;

        uint256 s2 = agentRegistry.slashStake(agentId, bps2);
        uint256 stake2 = stake1 - s2;
        vm.stopPrank();

        assertEq(s1, (stake0 * bps1) / Constants.BPS);
        assertEq(s2, (stake1 * bps2) / Constants.BPS);
        assertEq(agentRegistry.getAgent(agentId).stakedAmount, stake2);
    }
}
