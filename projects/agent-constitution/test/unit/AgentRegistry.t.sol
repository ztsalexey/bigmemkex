// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/core/AgentRegistry.sol";
import "../../src/core/Constitution.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockIdentityRegistry.sol";
import "../../src/libraries/Constants.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    Constitution public constitution;
    MockUSDC public usdc;
    MockIdentityRegistry public identity;

    address public admin = makeAddr("admin");
    address public operator1 = makeAddr("operator1");
    address public operator2 = makeAddr("operator2");
    address public staker = makeAddr("staker");
    address public nonAdmin = makeAddr("nonAdmin");

    string constant AGENT_NAME = "Test Agent";
    string constant METADATA_URI = "ipfs://test-metadata";

    function setUp() public {
        usdc = new MockUSDC();
        constitution = new Constitution(admin);
        identity = new MockIdentityRegistry();
        registry = new AgentRegistry(address(usdc), address(identity), admin);

        usdc.mint(staker, 200_000e6);
        vm.prank(staker);
        usdc.approve(address(registry), type(uint256).max);
    }

    // ── Registration via ERC-8004 ──────────────────────────────────

    function test_RegisterAgent_MintsERC8004Identity() public {
        vm.prank(staker);
        uint256 agentId = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        // ERC-8004 NFT minted to the AgentRegistry (it calls IDENTITY.register())
        assertEq(identity.ownerOf(agentId), address(registry));

        // Profile stored in our registry
        IAgentRegistry.AgentProfile memory a = registry.getAgent(agentId);
        assertEq(a.operator, operator1);
        assertEq(a.name, AGENT_NAME);
        assertEq(uint256(a.tier), uint256(IAgentRegistry.CapabilityTier.BASIC));
        assertEq(uint256(a.status), uint256(IAgentRegistry.AgentStatus.ACTIVE));
        assertEq(a.stakedAmount, Constants.STAKE_BASIC);
        assertGt(a.registeredAt, 0);

        // USDC transferred
        assertEq(usdc.balanceOf(address(registry)), Constants.STAKE_BASIC);
        assertTrue(registry.isCompliant(agentId));
        assertEq(registry.totalAgents(), 1);
    }

    function test_BindExistingAgent() public {
        // First mint identity on ERC-8004 directly
        vm.prank(staker);
        uint256 agentId = identity.register(METADATA_URI);

        // Then bind to Constitution with stake
        vm.prank(staker);
        registry.bindExistingAgent(agentId, AGENT_NAME, IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC);

        assertTrue(registry.agentExists(agentId));
        assertTrue(registry.isCompliant(agentId));
        assertEq(registry.getAgent(agentId).operator, staker);
    }

    function test_BindExistingAgent_RejectsNonOwner() public {
        vm.prank(staker);
        uint256 agentId = identity.register(METADATA_URI);

        vm.prank(nonAdmin);
        usdc.mint(nonAdmin, 200_000e6);
        vm.prank(nonAdmin);
        usdc.approve(address(registry), type(uint256).max);

        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.NotIdentityOwner.selector, agentId, nonAdmin));
        registry.bindExistingAgent(agentId, AGENT_NAME, IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC);
    }

    function test_CannotBindSameAgentTwice() public {
        vm.prank(staker);
        uint256 agentId = identity.register(METADATA_URI);

        vm.prank(staker);
        registry.bindExistingAgent(agentId, AGENT_NAME, IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC);

        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentAlreadyBound.selector, agentId));
        registry.bindExistingAgent(agentId, "Duplicate", IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC);
    }

    // ── Tier minimums ──────────────────────────────────────────────

    function test_RegisterAgent_AllTiers() public {
        IAgentRegistry.CapabilityTier[4] memory tiers = [
            IAgentRegistry.CapabilityTier.BASIC,
            IAgentRegistry.CapabilityTier.STANDARD,
            IAgentRegistry.CapabilityTier.ADVANCED,
            IAgentRegistry.CapabilityTier.AUTONOMOUS
        ];
        uint256[4] memory stakes = [
            Constants.STAKE_BASIC,
            Constants.STAKE_STANDARD,
            Constants.STAKE_ADVANCED,
            Constants.STAKE_AUTONOMOUS
        ];

        for (uint256 i = 0; i < tiers.length; i++) {
            vm.prank(staker);
            uint256 id = registry.registerAgent(
                operator1, string(abi.encodePacked("Agent ", vm.toString(i))),
                METADATA_URI, tiers[i], stakes[i]
            );
            assertEq(registry.getAgent(id).stakedAmount, stakes[i]);
        }
    }

    function test_TierMinimumStakeEnforcement() public {
        uint256 insufficient = Constants.STAKE_STANDARD - 1;
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(
            IAgentRegistry.InsufficientStake.selector, Constants.STAKE_STANDARD, insufficient
        ));
        registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.STANDARD, insufficient
        );
    }

    // ── Staking ────────────────────────────────────────────────────

    function test_AddStake() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        uint256 add = 50e6;
        vm.prank(staker);
        registry.addStake(id, add);

        assertEq(registry.getAgent(id).stakedAmount, Constants.STAKE_BASIC + add);
    }

    function test_ZeroStakeAddition() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, 1, 0));
        registry.addStake(id, 0);
    }

    // ── Slashing ───────────────────────────────────────────────────

    function test_SlashStake() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        uint256 slashBps = 1000; // 10%
        uint256 expected = (Constants.STAKE_BASIC * slashBps) / Constants.BPS;

        vm.prank(admin);
        uint256 slashed = registry.slashStake(id, slashBps);

        assertEq(slashed, expected);
        assertEq(registry.getAgent(id).stakedAmount, Constants.STAKE_BASIC - expected);
        assertEq(registry.getAgent(id).violationCount, 1);
        assertEq(usdc.balanceOf(admin), expected);
    }

    function test_SlashStake_AccessControl() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.slashStake(id, 1000);
    }

    function test_SlashAmountValidation() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            IAgentRegistry.InsufficientStake.selector, Constants.MAX_SLASH_BPS, Constants.MAX_SLASH_BPS + 1
        ));
        registry.slashStake(id, Constants.MAX_SLASH_BPS + 1);
    }

    // ── Status ─────────────────────────────────────────────────────

    function test_StatusTransitions() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        vm.prank(admin);
        registry.setAgentStatus(id, IAgentRegistry.AgentStatus.SUSPENDED);
        assertFalse(registry.isCompliant(id));

        vm.prank(admin);
        registry.setAgentStatus(id, IAgentRegistry.AgentStatus.ACTIVE);
        assertTrue(registry.isCompliant(id));

        vm.prank(admin);
        registry.setAgentStatus(id, IAgentRegistry.AgentStatus.TERMINATED);
        assertFalse(registry.isCompliant(id));
    }

    function test_CannotChangeStatusFromTerminated() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        vm.prank(admin);
        registry.setAgentStatus(id, IAgentRegistry.AgentStatus.TERMINATED);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentAlreadyTerminated.selector, id));
        registry.setAgentStatus(id, IAgentRegistry.AgentStatus.ACTIVE);
    }

    function test_AccessControl_OnlyAdminCanSetStatus() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.setAgentStatus(id, IAgentRegistry.AgentStatus.SUSPENDED);
    }

    // ── Compliance ─────────────────────────────────────────────────

    function test_IsCompliant_DropsBelowMinimum() public {
        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );
        assertTrue(registry.isCompliant(id));

        // Slash 90% — below minimum
        vm.prank(admin);
        registry.slashStake(id, 9000);
        assertFalse(registry.isCompliant(id));

        // Top up
        vm.prank(staker);
        registry.addStake(id, Constants.STAKE_BASIC);
        assertTrue(registry.isCompliant(id));
    }

    // ── View helpers ───────────────────────────────────────────────

    function test_MinimumStakeForAllTiers() public view {
        assertEq(registry.minimumStake(IAgentRegistry.CapabilityTier.BASIC), Constants.STAKE_BASIC);
        assertEq(registry.minimumStake(IAgentRegistry.CapabilityTier.STANDARD), Constants.STAKE_STANDARD);
        assertEq(registry.minimumStake(IAgentRegistry.CapabilityTier.ADVANCED), Constants.STAKE_ADVANCED);
        assertEq(registry.minimumStake(IAgentRegistry.CapabilityTier.AUTONOMOUS), Constants.STAKE_AUTONOMOUS);
    }

    function test_ErrorsForNonExistentAgent() public {
        assertFalse(registry.agentExists(999));
        assertFalse(registry.isCompliant(999));

        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentNotFound.selector, 999));
        registry.getAgent(999);
    }

    function test_ZeroAddressValidation() public {
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.ZeroAddress.selector));
        new AgentRegistry(address(0), address(identity), admin);

        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.ZeroAddress.selector));
        new AgentRegistry(address(usdc), address(0), admin);
    }

    // ── Pause ──────────────────────────────────────────────────────

    function test_PauseFunctionality() public {
        vm.prank(admin);
        registry.pause();

        vm.prank(staker);
        vm.expectRevert();
        registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );

        vm.prank(admin);
        registry.unpause();

        vm.prank(staker);
        uint256 id = registry.registerAgent(
            operator1, AGENT_NAME, METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );
        assertTrue(registry.agentExists(id));
    }

    function test_MultipleRegistrations() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(staker);
            registry.registerAgent(
                makeAddr(string(abi.encodePacked("op", vm.toString(i)))),
                string(abi.encodePacked("Agent ", vm.toString(i))),
                METADATA_URI, IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
            );
        }
        assertEq(registry.totalAgents(), 3);
    }
}
