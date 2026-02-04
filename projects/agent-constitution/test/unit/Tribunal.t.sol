// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/core/Tribunal.sol";
import "../../src/core/Constitution.sol";
import "../../src/core/AgentRegistry.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockIdentityRegistry.sol";
import "../../src/libraries/Constants.sol";

contract TribunalTest is Test {
    Tribunal public tribunal;
    Constitution public constitution;
    AgentRegistry public agentRegistry;
    MockUSDC public usdc;
    MockIdentityRegistry public identity;

    address public admin = makeAddr("admin");
    address public judge = makeAddr("judge");
    address public reporter1 = makeAddr("reporter1");
    address public reporter2 = makeAddr("reporter2");
    address public operator1 = makeAddr("operator1");
    address public staker = makeAddr("staker");
    address public nonJudge = makeAddr("nonJudge");

    bytes32 public constant TEST_RULE = keccak256("TEST_RULE");
    string constant EVIDENCE_URI = "ipfs://evidence-hash";
    string constant VIOLATION_DESCRIPTION = "Agent violated transparency rules";
    string constant RESOLUTION_TEXT = "Violation confirmed with evidence";
    bytes32 public constant EVIDENCE_HASH = keccak256("evidence-data");

    uint256 public agentId;

    function setUp() public {
        // Deploy contracts
        usdc = new MockUSDC();
        constitution = new Constitution(admin);
        identity = new MockIdentityRegistry();
        agentRegistry = new AgentRegistry(address(usdc), address(identity), admin);
        tribunal = new Tribunal(address(constitution), address(agentRegistry), address(usdc));

        // Grant JUDGE_ROLE to judge address on tribunal
        tribunal.grantRole(tribunal.JUDGE_ROLE(), judge);

        // Grant TRIBUNAL_ROLE to tribunal on the agent registry so it can slash
        vm.startPrank(admin);
        agentRegistry.grantRole(agentRegistry.TRIBUNAL_ROLE(), address(tribunal));
        vm.stopPrank();

        // Create a test rule in constitution
        vm.startPrank(admin);
        constitution.proposeRule(
            TEST_RULE,
            "Test transparency rule",
            IConstitution.RuleSeverity.HIGH,
            2000 // 20% slash
        );
        constitution.activateRule(TEST_RULE);
        vm.stopPrank();

        // Mint USDC to accounts
        usdc.mint(staker, 500_000e6);
        usdc.mint(reporter1, 10_000e6);
        usdc.mint(reporter2, 10_000e6);

        // Register an agent
        vm.startPrank(staker);
        usdc.approve(address(agentRegistry), type(uint256).max);
        agentId = agentRegistry.registerAgent(
            operator1,
            "Test Agent",
            "ipfs://test-metadata",
            IAgentRegistry.CapabilityTier.BASIC,
            Constants.STAKE_BASIC
        );
        vm.stopPrank();

        // Approve tribunal to spend USDC for reporters
        vm.prank(reporter1);
        usdc.approve(address(tribunal), type(uint256).max);
        vm.prank(reporter2);
        usdc.approve(address(tribunal), type(uint256).max);
    }

    // ── Report creation ────────────────────────────────────────────

    function test_ReportViolation() public {
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );

        assertEq(reportId, 1);

        ITribunal.ViolationReport memory r = tribunal.getReport(reportId);
        assertEq(r.agentId, agentId);
        assertEq(r.reporter, reporter1);
        assertEq(r.ruleId, TEST_RULE);
        assertEq(uint256(r.status), uint256(ITribunal.ReportStatus.SUBMITTED));
        assertEq(r.reporterStake, Constants.REPORTER_STAKE);
        assertGt(r.submittedAt, 0);
    }

    function test_ReportViolation_RequiresActiveRule() public {
        bytes32 inactiveRule = keccak256("INACTIVE_RULE");
        vm.prank(reporter1);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.RuleNotActive.selector, inactiveRule));
        tribunal.reportViolation(
            agentId, inactiveRule, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );
    }

    function test_ReportViolation_RequiresActiveAgent() public {
        vm.prank(reporter1);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.AgentNotActive.selector, 999));
        tribunal.reportViolation(
            999, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );
    }

    function test_ReporterStakeTransferred() public {
        uint256 balBefore = usdc.balanceOf(reporter1);
        vm.prank(reporter1);
        tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );
        assertEq(usdc.balanceOf(reporter1), balBefore - Constants.REPORTER_STAKE);
        assertEq(usdc.balanceOf(address(tribunal)), Constants.REPORTER_STAKE);
    }

    function test_ReporterStakeRequirement_InsufficientBalance() public {
        address broke = makeAddr("broke");
        usdc.mint(broke, 1e6); // only 1 USDC, need 50
        vm.startPrank(broke);
        usdc.approve(address(tribunal), type(uint256).max);
        vm.expectRevert(); // ERC20InsufficientBalance
        tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );
        vm.stopPrank();
    }

    // ── Resolution: accept ─────────────────────────────────────────

    function test_ResolveReport_AsViolation() public {
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );

        uint256 agentStakeBefore = agentRegistry.getAgent(agentId).stakedAmount;
        uint256 reporterBalBefore = usdc.balanceOf(reporter1);

        vm.prank(judge);
        tribunal.resolveReport(reportId, true, RESOLUTION_TEXT);

        // Report marked accepted
        ITribunal.ViolationReport memory r = tribunal.getReport(reportId);
        assertEq(uint256(r.status), uint256(ITribunal.ReportStatus.ACCEPTED));
        assertGt(r.resolvedAt, 0);

        // Agent slashed (20% of stake)
        uint256 expectedSlash = (agentStakeBefore * 2000) / Constants.BPS;
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        assertEq(agent.stakedAmount, agentStakeBefore - expectedSlash);
        assertEq(agent.violationCount, 1);

        // Reporter got stake back + reward (10% of slashed amount)
        uint256 reward = (expectedSlash * Constants.REPORTER_REWARD_BPS) / Constants.BPS;
        assertEq(usdc.balanceOf(reporter1), reporterBalBefore + Constants.REPORTER_STAKE + reward);
    }

    // ── Resolution: reject ─────────────────────────────────────────

    function test_ResolveReport_AsRejected() public {
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );

        uint256 agentStakeBefore = agentRegistry.getAgent(agentId).stakedAmount;
        uint256 reporterBalBefore = usdc.balanceOf(reporter1);

        vm.prank(judge);
        tribunal.resolveReport(reportId, false, "Rejected - insufficient evidence");

        // Report marked rejected
        ITribunal.ViolationReport memory r = tribunal.getReport(reportId);
        assertEq(uint256(r.status), uint256(ITribunal.ReportStatus.REJECTED));

        // Agent not slashed
        assertEq(agentRegistry.getAgent(agentId).stakedAmount, agentStakeBefore);

        // Reporter lost stake (no refund)
        assertEq(usdc.balanceOf(reporter1), reporterBalBefore);
    }

    // ── Slash calculation ──────────────────────────────────────────

    function test_CalculateSlash_BaseAmount() public view {
        (, uint256 slashBps) = tribunal.calculateSlash(agentId, TEST_RULE);
        assertEq(slashBps, 2000); // 20%
    }

    function test_CalculateSlash_WithRepeatOffenderMultiplier() public {
        // First violation
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );
        vm.prank(judge);
        tribunal.resolveReport(reportId, true, RESOLUTION_TEXT);

        // After 1 violation: base 2000 + (1 * 500) = 2500
        (, uint256 slashBps) = tribunal.calculateSlash(agentId, TEST_RULE);
        assertEq(slashBps, 2500);
    }

    function test_CalculateSlash_CappedAtMaximum() public {
        // Create high-slash rule
        bytes32 highSlashRule = keccak256("HIGH_SLASH_RULE");
        vm.startPrank(admin);
        constitution.proposeRule(highSlashRule, "High slash", IConstitution.RuleSeverity.CRITICAL, 8000);
        constitution.activateRule(highSlashRule);
        vm.stopPrank();

        // Create multiple violations to push multiplier high
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(reporter1);
            uint256 rid = tribunal.reportViolation(
                agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
                EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
            );
            vm.prank(judge);
            tribunal.resolveReport(rid, true, RESOLUTION_TEXT);

            // Top up stake to keep agent viable
            vm.prank(staker);
            agentRegistry.addStake(agentId, 50e6);
        }

        // 8000 + (5 * 500) = 10500, but capped at MAX_SLASH_BPS (9000)
        (, uint256 slashBps) = tribunal.calculateSlash(agentId, highSlashRule);
        assertEq(slashBps, Constants.MAX_SLASH_BPS);
    }

    // ── Access control ─────────────────────────────────────────────

    function test_AccessControl_OnlyJudgeCanResolve() public {
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );

        vm.prank(nonJudge);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        tribunal.resolveReport(reportId, true, RESOLUTION_TEXT);
    }

    // ── Error handling ─────────────────────────────────────────────

    function test_ErrorHandling_ReportNotFound() public {
        vm.prank(judge);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.ReportNotFound.selector, 999));
        tribunal.resolveReport(999, true, RESOLUTION_TEXT);
    }

    function test_ErrorHandling_ReportAlreadyResolved() public {
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION
        );

        vm.prank(judge);
        tribunal.resolveReport(reportId, true, RESOLUTION_TEXT);

        vm.prank(judge);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.ReportAlreadyResolved.selector, reportId));
        tribunal.resolveReport(reportId, false, "New resolution");
    }

    // ── Multiple reports ───────────────────────────────────────────

    function test_MultipleReports() public {
        vm.prank(reporter1);
        uint256 r1 = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY,
            EVIDENCE_HASH, EVIDENCE_URI, "First violation"
        );
        vm.prank(reporter2);
        uint256 r2 = tribunal.reportViolation(
            agentId, TEST_RULE, ITribunal.EvidenceType.WITNESS,
            keccak256("second"), "ipfs://second", "Second violation"
        );

        assertEq(r1, 1);
        assertEq(r2, 2);

        vm.startPrank(judge);
        tribunal.resolveReport(r1, true, "Confirmed");
        tribunal.resolveReport(r2, false, "Rejected");
        vm.stopPrank();

        assertEq(uint256(tribunal.getReport(r1).status), uint256(ITribunal.ReportStatus.ACCEPTED));
        assertEq(uint256(tribunal.getReport(r2).status), uint256(ITribunal.ReportStatus.REJECTED));
        assertEq(tribunal.getAgentReportCount(agentId), 1); // only accepted
    }

    // ── All evidence types ─────────────────────────────────────────

    function test_AllEvidenceTypes() public {
        ITribunal.EvidenceType[4] memory types = [
            ITribunal.EvidenceType.TRANSACTION,
            ITribunal.EvidenceType.LOG_ENTRY,
            ITribunal.EvidenceType.EXTERNAL,
            ITribunal.EvidenceType.WITNESS
        ];

        for (uint256 i = 0; i < types.length; i++) {
            vm.prank(reporter1);
            uint256 rid = tribunal.reportViolation(
                agentId, TEST_RULE, types[i],
                keccak256(abi.encodePacked(i)),
                string(abi.encodePacked("ipfs://", vm.toString(i))),
                string(abi.encodePacked("Violation ", vm.toString(i)))
            );
            assertEq(uint256(tribunal.getReport(rid).evidenceType), uint256(types[i]));
        }
    }
}
