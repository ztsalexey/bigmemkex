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
    address public ruleProposer = makeAddr("ruleProposer"); // human who proposes rules
    address public nonJudge = makeAddr("nonJudge");

    uint256 constant THRESHOLD = 1_000e6;

    bytes32 public constant TEST_RULE = keccak256("TEST_RULE");
    string constant EVIDENCE_URI = "ipfs://evidence-hash";
    string constant VIOLATION_DESCRIPTION = "Agent violated transparency rules";
    string constant RESOLUTION_TEXT = "Violation confirmed with evidence";
    bytes32 public constant EVIDENCE_HASH = keccak256("evidence-data");

    uint256 public agentId;

    function setUp() public {
        usdc = new MockUSDC();
        identity = new MockIdentityRegistry();
        agentRegistry = new AgentRegistry(address(usdc), address(identity), admin);
        constitution = new Constitution(address(usdc), address(agentRegistry), THRESHOLD);
        tribunal = new Tribunal(address(constitution), address(agentRegistry), address(usdc));

        // Roles
        tribunal.grantRole(tribunal.JUDGE_ROLE(), judge);
        vm.startPrank(admin);
        agentRegistry.grantRole(agentRegistry.TRIBUNAL_ROLE(), address(tribunal));
        vm.stopPrank();

        // Fund accounts
        usdc.mint(staker, 500_000e6);
        usdc.mint(reporter1, 10_000e6);
        usdc.mint(reporter2, 10_000e6);
        usdc.mint(ruleProposer, 100_000e6);

        // Approvals
        vm.prank(staker);
        usdc.approve(address(agentRegistry), type(uint256).max);
        vm.prank(reporter1);
        usdc.approve(address(tribunal), type(uint256).max);
        vm.prank(reporter2);
        usdc.approve(address(tribunal), type(uint256).max);
        vm.prank(ruleProposer);
        usdc.approve(address(constitution), type(uint256).max);

        // Create and activate a test rule via endorsement
        _createAndActivateRule(TEST_RULE, "Test transparency rule", 2000);

        // Register an agent
        vm.prank(staker);
        agentId = agentRegistry.registerAgent(
            operator1, "Test Agent", "ipfs://test-metadata",
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );
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
        bytes32 fake = keccak256("FAKE");
        vm.prank(reporter1);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.RuleNotActive.selector, fake));
        tribunal.reportViolation(agentId, fake, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);
    }

    function test_ReportViolation_RequiresActiveAgent() public {
        vm.prank(reporter1);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.AgentNotActive.selector, 999));
        tribunal.reportViolation(999, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);
    }

    function test_ReporterStakeTransferred() public {
        uint256 balBefore = usdc.balanceOf(reporter1);
        vm.prank(reporter1);
        tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);
        assertEq(usdc.balanceOf(reporter1), balBefore - Constants.REPORTER_STAKE);
    }

    function test_ReporterStake_InsufficientBalance() public {
        address broke = makeAddr("broke");
        usdc.mint(broke, 1e6);
        vm.startPrank(broke);
        usdc.approve(address(tribunal), type(uint256).max);
        vm.expectRevert();
        tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);
        vm.stopPrank();
    }

    // ── Resolution: accept ─────────────────────────────────────────

    function test_ResolveReport_AsViolation() public {
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);

        uint256 agentStakeBefore = agentRegistry.getAgent(agentId).stakedAmount;
        uint256 reporterBalBefore = usdc.balanceOf(reporter1);

        vm.prank(judge);
        tribunal.resolveReport(reportId, true, RESOLUTION_TEXT);

        ITribunal.ViolationReport memory r = tribunal.getReport(reportId);
        assertEq(uint256(r.status), uint256(ITribunal.ReportStatus.ACCEPTED));
        assertGt(r.resolvedAt, 0);

        uint256 expectedSlash = (agentStakeBefore * 2000) / Constants.BPS;
        IAgentRegistry.AgentProfile memory agent = agentRegistry.getAgent(agentId);
        assertEq(agent.stakedAmount, agentStakeBefore - expectedSlash);
        assertEq(agent.violationCount, 1);

        uint256 reward = (expectedSlash * Constants.REPORTER_REWARD_BPS) / Constants.BPS;
        assertEq(usdc.balanceOf(reporter1), reporterBalBefore + Constants.REPORTER_STAKE + reward);
    }

    // ── Resolution: reject ─────────────────────────────────────────

    function test_ResolveReport_AsRejected() public {
        vm.prank(reporter1);
        uint256 reportId = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);

        uint256 agentStakeBefore = agentRegistry.getAgent(agentId).stakedAmount;
        uint256 reporterBalBefore = usdc.balanceOf(reporter1);

        vm.prank(judge);
        tribunal.resolveReport(reportId, false, "Rejected");

        assertEq(uint256(tribunal.getReport(reportId).status), uint256(ITribunal.ReportStatus.REJECTED));
        assertEq(agentRegistry.getAgent(agentId).stakedAmount, agentStakeBefore);
        assertEq(usdc.balanceOf(reporter1), reporterBalBefore); // stake forfeited
    }

    // ── Slash calculation ──────────────────────────────────────────

    function test_CalculateSlash_BaseAmount() public view {
        (, uint256 bps) = tribunal.calculateSlash(agentId, TEST_RULE);
        assertEq(bps, 2000);
    }

    function test_CalculateSlash_WithRepeatOffender() public {
        vm.prank(reporter1);
        uint256 rid = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);
        vm.prank(judge);
        tribunal.resolveReport(rid, true, RESOLUTION_TEXT);

        (, uint256 bps) = tribunal.calculateSlash(agentId, TEST_RULE);
        assertEq(bps, 2500); // 2000 + 500
    }

    function test_CalculateSlash_CappedAtMax() public {
        bytes32 highRule = keccak256("HIGH");
        _createAndActivateRule(highRule, "High slash", 8000);

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(reporter1);
            uint256 rid = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);
            vm.prank(judge);
            tribunal.resolveReport(rid, true, RESOLUTION_TEXT);
            vm.prank(staker);
            agentRegistry.addStake(agentId, 50e6);
        }

        (, uint256 bps) = tribunal.calculateSlash(agentId, highRule);
        assertEq(bps, Constants.MAX_SLASH_BPS);
    }

    // ── Access control ─────────────────────────────────────────────

    function test_OnlyJudgeCanResolve() public {
        vm.prank(reporter1);
        uint256 rid = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);

        vm.prank(nonJudge);
        vm.expectRevert();
        tribunal.resolveReport(rid, true, RESOLUTION_TEXT);
    }

    // ── Error handling ─────────────────────────────────────────────

    function test_ReportNotFound() public {
        vm.prank(judge);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.ReportNotFound.selector, 999));
        tribunal.resolveReport(999, true, RESOLUTION_TEXT);
    }

    function test_ReportAlreadyResolved() public {
        vm.prank(reporter1);
        uint256 rid = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, VIOLATION_DESCRIPTION);
        vm.prank(judge);
        tribunal.resolveReport(rid, true, RESOLUTION_TEXT);

        vm.prank(judge);
        vm.expectRevert(abi.encodeWithSelector(ITribunal.ReportAlreadyResolved.selector, rid));
        tribunal.resolveReport(rid, false, "Nope");
    }

    // ── Multiple reports ───────────────────────────────────────────

    function test_MultipleReports() public {
        vm.prank(reporter1);
        uint256 r1 = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.LOG_ENTRY, EVIDENCE_HASH, EVIDENCE_URI, "First");
        vm.prank(reporter2);
        uint256 r2 = tribunal.reportViolation(agentId, TEST_RULE, ITribunal.EvidenceType.WITNESS, keccak256("2"), "ipfs://2", "Second");

        assertEq(r1, 1);
        assertEq(r2, 2);

        vm.startPrank(judge);
        tribunal.resolveReport(r1, true, "Confirmed");
        tribunal.resolveReport(r2, false, "Rejected");
        vm.stopPrank();

        assertEq(uint256(tribunal.getReport(r1).status), uint256(ITribunal.ReportStatus.ACCEPTED));
        assertEq(uint256(tribunal.getReport(r2).status), uint256(ITribunal.ReportStatus.REJECTED));
        assertEq(tribunal.getAgentReportCount(agentId), 1);
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
                string(abi.encodePacked("v", vm.toString(i)))
            );
            assertEq(uint256(tribunal.getReport(rid).evidenceType), uint256(types[i]));
        }
    }

    // ── Helpers ────────────────────────────────────────────────────

    function _createAndActivateRule(bytes32 ruleId, string memory desc, uint256 slashBps) internal {
        vm.prank(ruleProposer);
        constitution.proposeRule(ruleId, desc, IConstitution.RuleSeverity.HIGH, slashBps);

        // Endorse to meet threshold
        uint256 remaining = THRESHOLD - constitution.PROPOSAL_STAKE();
        vm.prank(ruleProposer);
        constitution.endorseRule(ruleId, remaining);

        constitution.activateRule(ruleId);
    }
}
