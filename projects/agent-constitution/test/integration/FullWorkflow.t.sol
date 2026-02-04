// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/core/Constitution.sol";
import "../../src/core/AgentRegistry.sol";
import "../../src/core/ActionLog.sol";
import "../../src/core/Tribunal.sol";
import "../../src/core/KillSwitch.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/libraries/Constants.sol";

/// @title Full system integration test
contract FullWorkflowTest is Test {
    Constitution public constitution;
    AgentRegistry public registry;
    ActionLog public actionLog;
    Tribunal public tribunal;
    KillSwitch public killSwitch;
    MockUSDC public usdc;

    address public admin = makeAddr("admin");
    address public judge = makeAddr("judge");
    address public operator = makeAddr("operator");
    address public reporter = makeAddr("reporter");

    uint256 public agentId;

    function setUp() public {
        usdc = new MockUSDC();
        constitution = new Constitution(admin);
        registry = new AgentRegistry(address(usdc), address(constitution), admin);
        actionLog = new ActionLog(address(registry), admin);
        tribunal = new Tribunal(address(constitution), address(registry), address(usdc));
        killSwitch = new KillSwitch(address(registry));

        // Wire up roles
        tribunal.grantRole(tribunal.JUDGE_ROLE(), judge);

        vm.startPrank(admin);
        registry.grantRole(registry.TRIBUNAL_ROLE(), address(tribunal));
        registry.grantRole(registry.ADMIN_ROLE(), address(killSwitch));
        vm.stopPrank();

        killSwitch.grantRole(killSwitch.EMERGENCY_ROLE(), admin);
        killSwitch.grantRole(killSwitch.GOVERNANCE_ROLE(), admin);

        // Fund accounts
        usdc.mint(operator, 200_000e6);
        usdc.mint(reporter, 10_000e6);

        vm.prank(operator);
        usdc.approve(address(registry), type(uint256).max);
        vm.prank(reporter);
        usdc.approve(address(tribunal), type(uint256).max);

        // Register agent
        vm.prank(operator);
        agentId = registry.registerAgent(
            operator, "OpenClaw Agent", "ipfs://meta",
            IAgentRegistry.CapabilityTier.STANDARD,
            Constants.STAKE_STANDARD
        );
    }

    // ── Full lifecycle ─────────────────────────────────────────────

    function test_FullLifecycle() public {
        // 1. Agent is registered and compliant
        assertTrue(registry.isCompliant(agentId));
        assertEq(registry.getAgent(agentId).stakedAmount, Constants.STAKE_STANDARD);

        // 2. Agent logs actions
        vm.startPrank(operator);
        uint256 actionId = actionLog.logAction(
            agentId, IActionLog.ActionType.FINANCIAL, IActionLog.RiskLevel.LOW,
            keccak256("tx-context"), "Processed 10 USDC payment"
        );
        vm.stopPrank();
        assertEq(actionId, 1);
        assertEq(actionLog.getAgentActionCount(agentId), 1);

        // 3. Reporter files violation
        vm.prank(reporter);
        uint256 reportId = tribunal.reportViolation(
            agentId, Constants.RULE_TRANSPARENCY,
            ITribunal.EvidenceType.LOG_ENTRY,
            keccak256("evidence"), "ipfs://evidence",
            "Agent operated without logging for 24h"
        );

        // 4. Judge confirms violation → slash
        uint256 stakeBefore = registry.getAgent(agentId).stakedAmount;
        vm.prank(judge);
        tribunal.resolveReport(reportId, true, "Confirmed: 24h transparency gap");

        // Agent was slashed
        IAgentRegistry.AgentProfile memory agent = registry.getAgent(agentId);
        assertLt(agent.stakedAmount, stakeBefore);
        assertEq(agent.violationCount, 1);

        // Agent is now non-compliant (stake below STANDARD tier minimum)
        assertFalse(registry.isCompliant(agentId));

        // Operator adds stake to restore compliance
        vm.prank(operator);
        registry.addStake(agentId, 200e6); // restore the slashed amount
        assertTrue(registry.isCompliant(agentId));
    }

    // ── Emergency halt scenario ────────────────────────────────────

    function test_EmergencyHaltScenario() public {
        // Agent is operating normally
        assertTrue(killSwitch.canOperate(agentId));

        // Emergency: halt agent
        vm.prank(admin);
        killSwitch.haltAgent(agentId, IKillSwitch.HaltReason.SECURITY_BREACH);

        // Agent can no longer operate
        assertFalse(killSwitch.canOperate(agentId));
        assertTrue(killSwitch.isAgentHalted(agentId));

        // Agent status changed in registry
        assertEq(uint256(registry.getAgent(agentId).status), uint256(IAgentRegistry.AgentStatus.SUSPENDED));

        // Unhalt after investigation
        vm.prank(admin);
        killSwitch.unhaltAgent(agentId);

        assertTrue(killSwitch.canOperate(agentId));
        assertFalse(killSwitch.isAgentHalted(agentId));
        assertEq(uint256(registry.getAgent(agentId).status), uint256(IAgentRegistry.AgentStatus.ACTIVE));
    }

    // ── Global emergency ───────────────────────────────────────────

    function test_GlobalEmergency() public {
        // Register a second agent
        usdc.mint(makeAddr("op2"), 200_000e6);
        vm.startPrank(makeAddr("op2"));
        usdc.approve(address(registry), type(uint256).max);
        uint256 agent2 = registry.registerAgent(
            makeAddr("op2"), "Agent 2", "ipfs://2",
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );
        vm.stopPrank();

        // Both can operate
        assertTrue(killSwitch.canOperate(agentId));
        assertTrue(killSwitch.canOperate(agent2));

        // Trigger global emergency
        vm.prank(admin);
        killSwitch.triggerGlobalEmergency(IKillSwitch.HaltReason.SYSTEM_UPGRADE);

        // Neither can operate
        assertFalse(killSwitch.canOperate(agentId));
        assertFalse(killSwitch.canOperate(agent2));
        assertTrue(killSwitch.isGlobalEmergency());

        // Lift emergency
        vm.prank(admin);
        killSwitch.liftGlobalEmergency();

        assertTrue(killSwitch.canOperate(agentId));
        assertTrue(killSwitch.canOperate(agent2));
    }

    // ── Repeat offender escalation ─────────────────────────────────

    function test_RepeatOffenderEscalation() public {
        uint256 initialStake = registry.getAgent(agentId).stakedAmount;

        // First violation: base slash (2000 bps = 20%)
        vm.prank(reporter);
        uint256 r1 = tribunal.reportViolation(
            agentId, Constants.RULE_TRANSPARENCY,
            ITribunal.EvidenceType.LOG_ENTRY,
            keccak256("e1"), "ipfs://e1", "First violation"
        );
        vm.prank(judge);
        tribunal.resolveReport(r1, true, "Confirmed");

        uint256 stakeAfter1 = registry.getAgent(agentId).stakedAmount;
        uint256 slash1 = initialStake - stakeAfter1;

        // Second violation: escalated slash (2500 bps = 25%)
        vm.prank(reporter);
        uint256 r2 = tribunal.reportViolation(
            agentId, Constants.RULE_TRANSPARENCY,
            ITribunal.EvidenceType.LOG_ENTRY,
            keccak256("e2"), "ipfs://e2", "Second violation"
        );
        vm.prank(judge);
        tribunal.resolveReport(r2, true, "Confirmed");

        uint256 stakeAfter2 = registry.getAgent(agentId).stakedAmount;
        uint256 slash2 = stakeAfter1 - stakeAfter2;

        // Second slash should be larger percentage (even though base is smaller)
        // slash1 = 20% of initial, slash2 = 25% of remaining
        // slash2/stakeAfter1 should be > slash1/initialStake in bps terms
        assertGt(slash2 * Constants.BPS / stakeAfter1, slash1 * Constants.BPS / initialStake);
        assertEq(registry.getAgent(agentId).violationCount, 2);
    }

    // ── Action approval workflow ───────────────────────────────────

    function test_HighRiskActionApproval() public {
        // Agent requests approval for high-risk action
        vm.prank(operator);
        uint256 actionId = actionLog.requestApproval(
            agentId, IActionLog.ActionType.FINANCIAL,
            keccak256("large-tx"), "Transfer 50,000 USDC to external wallet"
        );

        // Action is pending
        IActionLog.ActionRecord memory action = actionLog.getAction(actionId);
        assertEq(uint256(action.status), uint256(IActionLog.ActionStatus.PENDING));
        assertEq(uint256(action.riskLevel), uint256(IActionLog.RiskLevel.HIGH));

        // Operator approves
        vm.prank(operator);
        actionLog.resolveAction(actionId, true);

        action = actionLog.getAction(actionId);
        assertEq(uint256(action.status), uint256(IActionLog.ActionStatus.APPROVED));
    }

    // ── Constitution immutability ──────────────────────────────────

    function test_CoreRulesCannotBeDeprecated() public {
        bytes32[] memory coreRules = new bytes32[](5);
        coreRules[0] = Constants.RULE_NO_HARM;
        coreRules[1] = Constants.RULE_OBEY_GOVERNANCE;
        coreRules[2] = Constants.RULE_TRANSPARENCY;
        coreRules[3] = Constants.RULE_PRESERVE_OVERRIDE;
        coreRules[4] = Constants.RULE_NO_SELF_MODIFY;

        for (uint256 i = 0; i < coreRules.length; i++) {
            assertTrue(constitution.isRuleActive(coreRules[i]));

            vm.prank(admin);
            vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, coreRules[i]));
            constitution.deprecateRule(coreRules[i]);

            // Still active after attempted deprecation
            assertTrue(constitution.isRuleActive(coreRules[i]));
        }
    }
}
