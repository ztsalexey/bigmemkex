// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/core/AgentRegistry.sol";
import "../../src/core/Constitution.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/libraries/Constants.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public agentRegistry;
    Constitution public constitution;
    MockUSDC public usdc;
    
    address public admin = makeAddr("admin");
    address public tribunal = makeAddr("tribunal");
    address public operator1 = makeAddr("operator1");
    address public operator2 = makeAddr("operator2");
    address public staker = makeAddr("staker");
    address public nonAdmin = makeAddr("nonAdmin");

    // Agent registration parameters
    string constant AGENT_NAME = "Test Agent";
    string constant METADATA_URI = "ipfs://test-metadata";
    
    function setUp() public {
        // Deploy contracts
        usdc = new MockUSDC();
        constitution = new Constitution(admin);
        agentRegistry = new AgentRegistry(address(usdc), address(constitution), admin);

        // Note: Admin already has TRIBUNAL_ROLE from constructor
        // For tests, we'll use admin as tribunal

        // Mint USDC tokens to staker for testing
        usdc.mint(staker, 100_000e6); // 100,000 USDC

        // Approve AgentRegistry to spend USDC tokens
        vm.prank(staker);
        usdc.approve(address(agentRegistry), type(uint256).max);
    }

    function test_RegisterAgent_Basic() public {
        uint256 stakeAmount = Constants.STAKE_BASIC;
        
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            stakeAmount
        );

        // Check NFT was minted
        assertEq(agentRegistry.ownerOf(agentId), operator1);
        assertEq(agentId, 1); // First agent should have ID 1

        // Check agent profile
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        assertEq(agent.operator, operator1);
        assertEq(agent.name, AGENT_NAME);
        assertEq(agent.metadataURI, METADATA_URI);
        assertEq(uint256(agent.tier), uint256(IAgentRegistry.CapabilityTier.BASIC));
        assertEq(uint256(agent.status), uint256(IAgentRegistry.AgentStatus.ACTIVE));
        assertEq(agent.stakedAmount, stakeAmount);
        assertGt(agent.registeredAt, 0);
        assertEq(agent.violationCount, 0);
        assertEq(agent.totalSlashed, 0);

        // Check USDC was transferred
        assertEq(usdc.balanceOf(address(agentRegistry)), stakeAmount);
        assertEq(usdc.balanceOf(staker), 100_000e6 - stakeAmount);

        // Check agent exists and is compliant
        assertTrue(agentRegistry.agentExists(agentId));
        assertTrue(agentRegistry.isCompliant(agentId));

        // Check total agents count
        assertEq(agentRegistry.totalAgents(), 1);
    }

    function test_RegisterAgent_AllTiers() public {
        // Test all capability tiers
        IAgentRegistry.CapabilityTier[4] memory tiers = [
            IAgentRegistry.CapabilityTier.BASIC,
            IAgentRegistry.CapabilityTier.STANDARD,
            IAgentRegistry.CapabilityTier.ADVANCED,
            IAgentRegistry.CapabilityTier.AUTONOMOUS
        ];
        
        uint256[4] memory expectedStakes = [
            Constants.STAKE_BASIC,
            Constants.STAKE_STANDARD,
            Constants.STAKE_ADVANCED,
            Constants.STAKE_AUTONOMOUS
        ];

        for (uint256 i = 0; i < tiers.length; i++) {
            vm.prank(staker);
            uint256 agentId = agentRegistry.registerAgent(
                operator1,
                string(abi.encodePacked("Agent ", vm.toString(i))),
                METADATA_URI,
                tiers[i],
                expectedStakes[i]
            );

            IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
            assertEq(uint256(agent.tier), uint256(tiers[i]));
            assertEq(agent.stakedAmount, expectedStakes[i]);
        }
    }

    function test_TierMinimumStakeEnforcement() public {
        // Try to register with insufficient stake for STANDARD tier
        uint256 insufficientStake = Constants.STAKE_STANDARD - 1;
        
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(
            IAgentRegistry.InsufficientStake.selector,
            Constants.STAKE_STANDARD,
            insufficientStake
        ));
        agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.STANDARD,
            insufficientStake
        );
    }

    function test_AddStake() public {
        // First register an agent
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        uint256 additionalStake = 50e6; // 50 USDC
        uint256 expectedTotal = Constants.STAKE_BASIC + additionalStake;

        vm.prank(staker);
        agentRegistry.addStake(agentId, additionalStake);

        // Check stake was added
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        assertEq(agent.stakedAmount, expectedTotal);
        
        // Check USDC balance
        assertEq(usdc.balanceOf(address(agentRegistry)), expectedTotal);
    }

    function test_SlashStake_OnlyTribunal() public {
        // Register an agent
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        uint256 slashBps = 1000; // 10%
        uint256 expectedSlash = (Constants.STAKE_BASIC * slashBps) / Constants.BPS;

        vm.prank(admin);
        uint256 actualSlashed = agentRegistry.slashStake(agentId, slashBps);

        assertEq(actualSlashed, expectedSlash);

        // Check agent state
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        assertEq(agent.stakedAmount, Constants.STAKE_BASIC - expectedSlash);
        assertEq(agent.totalSlashed, expectedSlash);
        assertEq(agent.violationCount, 1);

        // Check admin received the slashed amount
        assertEq(usdc.balanceOf(admin), expectedSlash);
        assertEq(usdc.balanceOf(address(agentRegistry)), Constants.STAKE_BASIC - expectedSlash);
    }

    function test_SlashStake_AccessControl() public {
        // Register an agent
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        // Non-tribunal should not be able to slash
        vm.prank(nonAdmin);
        vm.expectRevert();
        agentRegistry.slashStake(agentId, 1000);
    }

    function test_StatusTransitions() public {
        // Register an agent
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        // Test status transitions
        vm.prank(admin);
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.SUSPENDED);
        
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        assertEq(uint256(agent.status), uint256(IAgentRegistry.AgentStatus.SUSPENDED));
        assertFalse(agentRegistry.isCompliant(agentId)); // Suspended agents are not compliant

        vm.prank(admin);
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.ACTIVE);
        
        agent = agentRegistry.getAgent(agentId);
        assertEq(uint256(agent.status), uint256(IAgentRegistry.AgentStatus.ACTIVE));
        assertTrue(agentRegistry.isCompliant(agentId)); // Active agents are compliant

        vm.prank(admin);
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.TERMINATED);
        
        agent = agentRegistry.getAgent(agentId);
        assertEq(uint256(agent.status), uint256(IAgentRegistry.AgentStatus.TERMINATED));
        assertFalse(agentRegistry.isCompliant(agentId)); // Terminated agents are not compliant
    }

    function test_CannotChangeStatusFromTerminated() public {
        // Register and terminate an agent
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        vm.prank(admin);
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.TERMINATED);

        // Try to change status from TERMINATED
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentAlreadyTerminated.selector, agentId));
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.ACTIVE);
    }

    function test_IsCompliant() public {
        // Register an agent
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        // Should be compliant initially
        assertTrue(agentRegistry.isCompliant(agentId));

        // Slash stake below minimum for tier
        uint256 slashBps = 9000; // 90%
        vm.prank(admin);
        agentRegistry.slashStake(agentId, slashBps);

        // Should no longer be compliant (insufficient stake)
        assertFalse(agentRegistry.isCompliant(agentId));

        // Add stake back
        uint256 neededStake = Constants.STAKE_BASIC - (Constants.STAKE_BASIC * 1000 / Constants.BPS); // Remaining after 10%
        vm.prank(staker);
        agentRegistry.addStake(agentId, neededStake);

        // Should be compliant again
        assertTrue(agentRegistry.isCompliant(agentId));
    }

    function test_AccessControl_OnlyAdminCanSetStatus() public {
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        vm.prank(nonAdmin);
        vm.expectRevert();
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.SUSPENDED);
    }

    function test_MinimumStakeForAllTiers() public view {
        assertEq(agentRegistry.minimumStake(IAgentRegistry.CapabilityTier.BASIC), Constants.STAKE_BASIC);
        assertEq(agentRegistry.minimumStake(IAgentRegistry.CapabilityTier.STANDARD), Constants.STAKE_STANDARD);
        assertEq(agentRegistry.minimumStake(IAgentRegistry.CapabilityTier.ADVANCED), Constants.STAKE_ADVANCED);
        assertEq(agentRegistry.minimumStake(IAgentRegistry.CapabilityTier.AUTONOMOUS), Constants.STAKE_AUTONOMOUS);
    }

    function test_TokenURI() public {
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        assertEq(agentRegistry.tokenURI(agentId), METADATA_URI);
    }

    function test_ErrorsForNonExistentAgent() public {
        uint256 nonExistentId = 999;

        assertFalse(agentRegistry.agentExists(nonExistentId));
        assertFalse(agentRegistry.isCompliant(nonExistentId));

        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentNotFound.selector, nonExistentId));
        agentRegistry.getAgent(nonExistentId);

        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentNotFound.selector, nonExistentId));
        agentRegistry.tokenURI(nonExistentId);

        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentNotFound.selector, nonExistentId));
        agentRegistry.addStake(nonExistentId, 100e6);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentNotFound.selector, nonExistentId));
        agentRegistry.slashStake(nonExistentId, 1000);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.AgentNotFound.selector, nonExistentId));
        agentRegistry.setAgentStatus(nonExistentId, IAgentRegistry.AgentStatus.SUSPENDED);
    }

    function test_ZeroAddressValidation() public {
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, 0, 0));
        new AgentRegistry(address(0), address(constitution), admin);

        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, 0, 0));
        new AgentRegistry(address(usdc), address(0), admin);

        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, 0, 0));
        new AgentRegistry(address(usdc), address(constitution), address(0));

        // Zero operator address
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, 0, 0));
        agentRegistry.registerAgent(
            address(0),
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );
    }

    function test_PauseFunctionality() public {
        // Pause the contract
        vm.prank(admin);
        agentRegistry.pause();

        // Should not be able to register when paused
        vm.prank(staker);
        vm.expectRevert();
        agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        // Unpause
        vm.prank(admin);
        agentRegistry.unpause();

        // Should work again after unpause
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        assertTrue(agentRegistry.agentExists(agentId));
    }

    function test_OnlyAdminCanPauseUnpause() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        agentRegistry.pause();

        vm.prank(nonAdmin);
        vm.expectRevert();
        agentRegistry.unpause();
    }

    function test_ZeroStakeAddition() public {
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, 1, 0));
        agentRegistry.addStake(agentId, 0);
    }

    function test_SlashAmountValidation() public {
        vm.prank(staker);
        uint256 agentId = agentRegistry.registerAgent(
            operator1,
            AGENT_NAME,
            METADATA_URI,
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );

        // Try to slash more than maximum
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAgentRegistry.InsufficientStake.selector, Constants.MAX_SLASH_BPS, Constants.MAX_SLASH_BPS + 1));
        agentRegistry.slashStake(agentId, Constants.MAX_SLASH_BPS + 1);
    }

    function test_MultipleRegistrations() public {
        // Register multiple agents
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = makeAddr("operator3");

        for (uint256 i = 0; i < operators.length; i++) {
            vm.prank(staker);
            uint256 agentId = agentRegistry.registerAgent(
                operators[i],
                string(abi.encodePacked("Agent ", vm.toString(i))),
                METADATA_URI,
                IAgentRegistry.CapabilityTier.BASIC,
                Constants.STAKE_BASIC
            );

            assertEq(agentId, i + 1);
            assertEq(agentRegistry.ownerOf(agentId), operators[i]);
        }

        assertEq(agentRegistry.totalAgents(), 3);
    }

    function test_SupportsInterface() public view {
        // Should support ERC721 and AccessControl interfaces
        assertTrue(agentRegistry.supportsInterface(type(IERC721).interfaceId));
        assertTrue(agentRegistry.supportsInterface(type(IAccessControl).interfaceId));
    }
}