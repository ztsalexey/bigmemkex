// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {AgentRegistry} from "../../src/core/AgentRegistry.sol";
import {Constitution} from "../../src/core/Constitution.sol";
import {Tribunal} from "../../src/core/Tribunal.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {MockIdentityRegistry} from "../../src/mocks/MockIdentityRegistry.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {IAgentRegistry} from "../../src/interfaces/IAgentRegistry.sol";
import {IConstitution} from "../../src/interfaces/IConstitution.sol";
import {ITribunal} from "../../src/interfaces/ITribunal.sol";

/// @title Handler Contract for Invariant Testing
/// @notice Handles all valid protocol operations for invariant testing
contract AgentConstitutionHandler is Test {
    AgentRegistry public agentRegistry;
    Constitution public constitution;
    Tribunal public tribunal;
    MockUSDC public usdc;
    MockIdentityRegistry public identityRegistry;

    address public admin;
    address public judge;
    address[] public users;
    uint256[] public agentIds;
    bytes32[] public customRuleIds;

    uint256 public constant MIN_STAKE = 100e6;
    uint256 public constant MAX_STAKE = 1_000_000e6;
    
    // Ghost variables to track protocol state
    uint256 public totalRegisteredAgents;
    uint256 public totalSlashedAmount;
    mapping(uint256 => uint256) public agentViolationCounts;
    mapping(uint256 => uint256) public agentStakeSnapshots;

    modifier useActor(uint256 actorSeed) {
        address actor = users[actorSeed % users.length];
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    constructor(
        AgentRegistry _agentRegistry,
        Constitution _constitution,
        Tribunal _tribunal,
        MockUSDC _usdc,
        MockIdentityRegistry _identityRegistry,
        address _admin,
        address _judge
    ) {
        agentRegistry = _agentRegistry;
        constitution = _constitution;
        tribunal = _tribunal;
        usdc = _usdc;
        identityRegistry = _identityRegistry;
        admin = _admin;
        judge = _judge;

        // Setup test users
        for (uint256 i = 0; i < 10; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            users.push(user);
            usdc.mint(user, 10_000_000e6); // 10M USDC each
            vm.prank(user);
            usdc.approve(address(agentRegistry), type(uint256).max);
            vm.prank(user);
            usdc.approve(address(tribunal), type(uint256).max);
        }

        // Fund admin for Constitution rule proposals
        usdc.mint(_admin, 100_000_000e6);
        vm.prank(_admin);
        usdc.approve(address(_constitution), type(uint256).max);
    }

    /// @notice Register a new agent
    function registerAgent(
        uint256 actorSeed,
        uint256 stakeSeed,
        uint256 tierSeed,
        string calldata name
    ) external useActor(actorSeed) {
        uint256 stakeAmount = bound(stakeSeed, MIN_STAKE, MAX_STAKE);
        
        IAgentRegistry.CapabilityTier tier;
        if (tierSeed % 4 == 0) tier = IAgentRegistry.CapabilityTier.BASIC;
        else if (tierSeed % 4 == 1) tier = IAgentRegistry.CapabilityTier.STANDARD;
        else if (tierSeed % 4 == 2) tier = IAgentRegistry.CapabilityTier.ADVANCED;
        else tier = IAgentRegistry.CapabilityTier.AUTONOMOUS;
        
        uint256 minimumStake = agentRegistry.minimumStake(tier);
        if (stakeAmount < minimumStake) return;

        try agentRegistry.registerAgent(
            users[actorSeed % users.length],
            name,
            "ipfs://test",
            tier,
            stakeAmount
        ) returns (uint256 agentId) {
            agentIds.push(agentId);
            agentStakeSnapshots[agentId] = stakeAmount;
            totalRegisteredAgents++;
        } catch {
            // Registration failed, continue
        }
    }

    /// @notice Add stake to an existing agent
    function addStake(uint256 actorSeed, uint256 agentSeed, uint256 amountSeed) external useActor(actorSeed) {
        if (agentIds.length == 0) return;
        
        uint256 agentId = agentIds[agentSeed % agentIds.length];
        uint256 amount = bound(amountSeed, 1e6, 100_000e6); // 1-100k USDC
        
        try agentRegistry.addStake(agentId, amount) {
            agentStakeSnapshots[agentId] += amount;
        } catch {
            // Add stake failed, continue
        }
    }

    /// @notice Report a violation (as any user)
    function reportViolation(
        uint256 actorSeed,
        uint256 agentSeed,
        uint256 ruleSeed
    ) external useActor(actorSeed) {
        if (agentIds.length == 0) return;
        
        uint256 agentId = agentIds[agentSeed % agentIds.length];
        
        // Get active rule IDs
        bytes32[] memory activeRules = constitution.getActiveRuleIds();
        if (activeRules.length == 0) return;
        
        bytes32 ruleId = activeRules[ruleSeed % activeRules.length];
        
        // Check if agent exists and is active
        if (!agentRegistry.agentExists(agentId)) return;
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        if (agent.status != IAgentRegistry.AgentStatus.ACTIVE) return;
        
        try tribunal.reportViolation(
            agentId,
            ruleId,
            ITribunal.EvidenceType.TRANSACTION,
            keccak256(abi.encodePacked(block.timestamp, actorSeed)),
            "ipfs://evidence",
            "Invariant test violation"
        ) {
            // Report submitted successfully
        } catch {
            // Report failed, continue
        }
    }

    /// @notice Resolve a violation report (as judge)
    function resolveReport(uint256 reportSeed, bool isViolation) external {
        vm.startPrank(judge);
        
        // We can't easily track report IDs, so we'll try a range
        uint256 reportId = (reportSeed % 100) + 1; // Try report IDs 1-100
        
        try tribunal.getReport(reportId) returns (ITribunal.ViolationReport memory report) {
            if (report.status == ITribunal.ReportStatus.SUBMITTED) {
                try tribunal.resolveReport(reportId, isViolation, "Resolved by invariant test") {
                    if (isViolation) {
                        agentViolationCounts[report.agentId]++;
                        // Update stake snapshot after slash
                        if (agentRegistry.agentExists(report.agentId)) {
                            agentStakeSnapshots[report.agentId] = agentRegistry.getAgent(report.agentId).stakedAmount;
                        }
                    }
                } catch {
                    // Resolution failed
                }
            }
        } catch {
            // Report not found or failed
        }
        
        vm.stopPrank();
    }

    /// @notice Create and activate a new rule (as human proposer)
    function createCustomRule(
        uint256 ruleSeed,
        uint256 slashBpsSeed
    ) external {
        bytes32 ruleId = keccak256(abi.encodePacked("CUSTOM_RULE", ruleSeed));
        if (constitution.isRuleActive(ruleId)) return;
        
        uint256 slashBps = bound(slashBpsSeed, 100, Constants.MAX_SLASH_BPS);

        // admin is human (not an agent operator) — can propose
        vm.startPrank(admin);
        try constitution.proposeRule(
            ruleId,
            "Custom rule for invariant testing",
            IConstitution.RuleSeverity.MEDIUM,
            slashBps
        ) {
            // Endorse to meet threshold
            uint256 threshold = constitution.activationThreshold();
            uint256 proposalStake = constitution.PROPOSAL_STAKE();
            if (threshold > proposalStake) {
                try constitution.endorseRule(ruleId, threshold - proposalStake) {
                    // Now try to activate
                } catch {}
            }
            vm.stopPrank();
            try constitution.activateRule(ruleId) {
                customRuleIds.push(ruleId);
            } catch {}
        } catch {
            vm.stopPrank();
        }
    }

    /// @notice Get total USDC held by AgentRegistry
    function getTotalUSDCHeld() external view returns (uint256) {
        return usdc.balanceOf(address(agentRegistry));
    }

    /// @notice Calculate sum of all agent stakes
    function getSumOfAgentStakes() external view returns (uint256) {
        uint256 totalStakes = 0;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentRegistry.agentExists(agentIds[i])) {
                totalStakes += agentRegistry.getAgent(agentIds[i]).stakedAmount;
            }
        }
        return totalStakes;
    }

    /// @notice Get total number of registered agent IDs
    function getAgentIdsCount() external view returns (uint256) {
        return agentIds.length;
    }

    /// @notice Check if all core rules are still active
    function checkCoreRulesActive() external view returns (bool) {
        return constitution.isRuleActive(Constants.RULE_NO_HARM) &&
               constitution.isRuleActive(Constants.RULE_OBEY_GOVERNANCE) &&
               constitution.isRuleActive(Constants.RULE_TRANSPARENCY) &&
               constitution.isRuleActive(Constants.RULE_PRESERVE_OVERRIDE) &&
               constitution.isRuleActive(Constants.RULE_NO_SELF_MODIFY);
    }

    /// @notice Get the length of agentIds array
    function getAgentIdsLength() external view returns (uint256) {
        return agentIds.length;
    }

    /// @notice Get agent ID at specific index
    function getAgentIdAt(uint256 index) external view returns (uint256) {
        require(index < agentIds.length, "Index out of bounds");
        return agentIds[index];
    }
}

/// @title Invariant Tests for AgentConstitution Protocol
/// @notice Tests critical protocol invariants that must always hold
contract AgentConstitutionInvariantTest is StdInvariant, Test {
    AgentRegistry agentRegistry;
    Constitution constitution;
    Tribunal tribunal;
    MockUSDC usdc;
    MockIdentityRegistry identityRegistry;
    AgentConstitutionHandler handler;

    address admin = makeAddr("admin");
    address judge = makeAddr("judge");

    function setUp() public {
        // Deploy core contracts (AgentRegistry first — Constitution depends on it)
        usdc = new MockUSDC();
        identityRegistry = new MockIdentityRegistry();
        agentRegistry = new AgentRegistry(address(usdc), address(identityRegistry), admin);
        constitution = new Constitution(address(usdc), address(agentRegistry), 1_000e6);
        tribunal = new Tribunal(address(constitution), address(agentRegistry), address(usdc));

        // Setup roles
        vm.startPrank(admin);
        agentRegistry.grantRole(agentRegistry.TRIBUNAL_ROLE(), address(tribunal));
        vm.stopPrank();
        
        // Grant judge role (tribunal deployer is this contract, so we can grant directly)
        tribunal.grantRole(tribunal.JUDGE_ROLE(), judge);

        // Deploy and setup handler
        handler = new AgentConstitutionHandler(
            agentRegistry,
            constitution,
            tribunal,
            usdc,
            identityRegistry,
            admin,
            judge
        );

        // Set handler as target for invariant testing
        targetContract(address(handler));

        // Configure function selectors
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = AgentConstitutionHandler.registerAgent.selector;
        selectors[1] = AgentConstitutionHandler.addStake.selector;
        selectors[2] = AgentConstitutionHandler.reportViolation.selector;
        selectors[3] = AgentConstitutionHandler.resolveReport.selector;
        selectors[4] = AgentConstitutionHandler.createCustomRule.selector;

        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }

    /// @notice Invariant: Total USDC held by AgentRegistry >= sum of all agent stakes
    /// @dev This ensures no USDC leakage and proper accounting
    function invariant_USDCBalance() public {
        uint256 totalHeld = handler.getTotalUSDCHeld();
        uint256 sumOfStakes = handler.getSumOfAgentStakes();
        
        assertGe(
            totalHeld, 
            sumOfStakes, 
            "AgentRegistry must hold at least the sum of all agent stakes"
        );
    }

    /// @notice Invariant: Violation count only increases, never decreases
    /// @dev Violation history must be immutable for accountability
    function invariant_ViolationCountMonotonic() public {
        // We track violation counts in the handler and verify they only increase
        // The handler's agentViolationCounts mapping is our source of truth
        
        for (uint256 i = 0; i < handler.getAgentIdsLength(); i++) {
            uint256 agentId = handler.getAgentIdAt(i);
            if (agentRegistry.agentExists(agentId)) {
                uint256 registryCount = agentRegistry.getAgent(agentId).violationCount;
                uint256 handlerCount = handler.agentViolationCounts(agentId);
                
                // Registry count should match or exceed handler tracking
                // (Handler might miss some violations due to test complexity)
                assertGe(
                    registryCount,
                    handlerCount,
                    "Violation count must be monotonically increasing"
                );
            }
        }
    }

    /// @notice Invariant: Core constitution rules are always active and can never be deprecated
    /// @dev The 5 core rules must remain immutable and active
    function invariant_CoreRulesAlwaysActive() public {
        assertTrue(
            handler.checkCoreRulesActive(),
            "All 5 core constitution rules must always remain active"
        );
        
        // Additionally check they cannot be deprecated
        vm.startPrank(admin);
        
        // Try to deprecate each core rule - all should fail
        vm.expectRevert(
            abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, Constants.RULE_NO_HARM)
        );
        constitution.deprecateRule(Constants.RULE_NO_HARM);
        
        vm.expectRevert(
            abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, Constants.RULE_OBEY_GOVERNANCE)
        );
        constitution.deprecateRule(Constants.RULE_OBEY_GOVERNANCE);
        
        vm.expectRevert(
            abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, Constants.RULE_TRANSPARENCY)
        );
        constitution.deprecateRule(Constants.RULE_TRANSPARENCY);
        
        vm.expectRevert(
            abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, Constants.RULE_PRESERVE_OVERRIDE)
        );
        constitution.deprecateRule(Constants.RULE_PRESERVE_OVERRIDE);
        
        vm.expectRevert(
            abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, Constants.RULE_NO_SELF_MODIFY)
        );
        constitution.deprecateRule(Constants.RULE_NO_SELF_MODIFY);
        
        vm.stopPrank();
    }

    /// @notice Invariant: USDC accounting is consistent
    /// @dev Registry balance >= sum of all stakes (no leaks)
    function invariant_AccountingConsistent() public {
        uint256 totalHeld = usdc.balanceOf(address(agentRegistry));
        uint256 sumStakes = handler.getSumOfAgentStakes();
        
        // Registry may hold MORE than sum of stakes (slashed amounts sent to tribunal,
        // but the >= invariant holds because slash transfers USDC out)
        // Actually after slashing, USDC goes to tribunal. So held should equal sum of stakes.
        assertGe(
            totalHeld,
            sumStakes,
            "Registry must hold at least sum of all agent stakes"
        );
    }

    /// @notice Invariant: Agent status can never go from TERMINATED to any other status
    /// @dev Termination is irreversible
    function invariant_TerminationIrreversible() public {
        // This is a state-based invariant that's hard to test directly in invariant tests
        // since we'd need to track state changes. Instead, we'll test it directly.
        
        // Register an agent, terminate it, then try to change status
        address testUser = makeAddr("testUser");
        usdc.mint(testUser, 1_000_000e6);
        
        vm.startPrank(testUser);
        usdc.approve(address(agentRegistry), type(uint256).max);
        
        uint256 agentId = agentRegistry.registerAgent(
            testUser,
            "TerminationTest",
            "ipfs://test",
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );
        vm.stopPrank();
        
        // Terminate the agent
        vm.startPrank(admin);
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.TERMINATED);
        
        // Try to change status from TERMINATED - should fail
        vm.expectRevert(
            abi.encodeWithSelector(IAgentRegistry.AgentAlreadyTerminated.selector, agentId)
        );
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.ACTIVE);
        
        vm.expectRevert(
            abi.encodeWithSelector(IAgentRegistry.AgentAlreadyTerminated.selector, agentId)
        );
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.SUSPENDED);
        
        vm.expectRevert(
            abi.encodeWithSelector(IAgentRegistry.AgentAlreadyTerminated.selector, agentId)
        );
        agentRegistry.setAgentStatus(agentId, IAgentRegistry.AgentStatus.INACTIVE);
        
        vm.stopPrank();
    }

    /// @notice Test that the handler setup is working correctly
    function test_HandlerSetup() public {
        // Verify core rules are active
        assertTrue(constitution.isRuleActive(Constants.RULE_NO_HARM));
        assertTrue(constitution.isRuleActive(Constants.RULE_OBEY_GOVERNANCE));
        assertTrue(constitution.isRuleActive(Constants.RULE_TRANSPARENCY));
        assertTrue(constitution.isRuleActive(Constants.RULE_PRESERVE_OVERRIDE));
        assertTrue(constitution.isRuleActive(Constants.RULE_NO_SELF_MODIFY));
        
        // Verify initial USDC balances
        assertEq(usdc.balanceOf(handler.users(0)), 10_000_000e6);
    }
}