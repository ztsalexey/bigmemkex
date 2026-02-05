// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/core/Constitution.sol";
import "../../src/core/AgentRegistry.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockIdentityRegistry.sol";
import "../../src/libraries/Constants.sol";

contract ConstitutionTest is Test {
    Constitution public constitution;
    AgentRegistry public agentRegistry;
    MockUSDC public usdc;
    MockIdentityRegistry public identity;

    address public alice = makeAddr("alice");    // human proposer
    address public bob = makeAddr("bob");        // human endorser
    address public charlie = makeAddr("charlie"); // another human
    address public agentOp = makeAddr("agentOp"); // agent operator (will be blocked)
    address public admin = makeAddr("admin");

    uint256 public constant THRESHOLD = 1_000e6; // 1000 USDC

    bytes32 public constant TEST_RULE_1 = keccak256("TEST_RULE_1");
    bytes32 public constant TEST_RULE_2 = keccak256("TEST_RULE_2");

    function setUp() public {
        usdc = new MockUSDC();
        identity = new MockIdentityRegistry();

        // Deploy AgentRegistry first (Constitution depends on it)
        agentRegistry = new AgentRegistry(address(usdc), address(identity), admin);

        // Deploy Constitution — no admin, fully open
        constitution = new Constitution(address(usdc), address(agentRegistry), THRESHOLD);

        // Fund humans
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(charlie, 100_000e6);
        usdc.mint(agentOp, 100_000e6);

        // Approve Constitution for all
        vm.prank(alice);
        usdc.approve(address(constitution), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(constitution), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(constitution), type(uint256).max);
        vm.prank(agentOp);
        usdc.approve(address(constitution), type(uint256).max);
        vm.prank(agentOp);
        usdc.approve(address(agentRegistry), type(uint256).max);

        // Register agentOp as an agent operator (making them non-human)
        vm.prank(agentOp);
        agentRegistry.registerAgent(
            agentOp, "TestBot", "ipfs://bot",
            IAgentRegistry.CapabilityTier.BASIC, Constants.STAKE_BASIC
        );
    }

    // ── Core immutable rules ───────────────────────────────────────

    function test_CoreRulesActiveAtGenesis() public {
        assertEq(constitution.version(), 1);
        assertTrue(constitution.isRuleActive(Constants.RULE_NO_HARM));
        assertTrue(constitution.isRuleActive(Constants.RULE_OBEY_GOVERNANCE));
        assertTrue(constitution.isRuleActive(Constants.RULE_TRANSPARENCY));
        assertTrue(constitution.isRuleActive(Constants.RULE_PRESERVE_OVERRIDE));
        assertTrue(constitution.isRuleActive(Constants.RULE_NO_SELF_MODIFY));

        assertEq(constitution.ruleCount(), 5);

        bytes32[] memory active = constitution.getActiveRuleIds();
        assertEq(active.length, 5);
    }

    function test_CoreRulesAreImmutable() public {
        IConstitution.Rule memory r = constitution.getRule(Constants.RULE_NO_HARM);
        assertTrue(r.immutable_);
        assertEq(r.totalEndorsed, type(uint256).max);
        assertEq(r.proposer, address(0)); // genesis, no human proposer
    }

    function test_CoreRulesCannotBeOpposed() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, Constants.RULE_NO_HARM));
        constitution.opposeRule(Constants.RULE_NO_HARM, 100e6);
    }

    function test_CoreRuleSlashAmounts() public {
        assertEq(constitution.getRule(Constants.RULE_NO_HARM).slashBps, Constants.MAX_SLASH_BPS);
        assertEq(constitution.getRule(Constants.RULE_OBEY_GOVERNANCE).slashBps, 5000);
        assertEq(constitution.getRule(Constants.RULE_TRANSPARENCY).slashBps, 2000);
        assertEq(constitution.getRule(Constants.RULE_PRESERVE_OVERRIDE).slashBps, Constants.MAX_SLASH_BPS);
        assertEq(constitution.getRule(Constants.RULE_NO_SELF_MODIFY).slashBps, Constants.MAX_SLASH_BPS);
    }

    // ── Proposing rules ────────────────────────────────────────────

    function test_HumanCanProposeRule() public {
        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "No rug pulls", IConstitution.RuleSeverity.HIGH, 3000);

        IConstitution.Rule memory r = constitution.getRule(TEST_RULE_1);
        assertEq(r.id, TEST_RULE_1);
        assertEq(r.proposer, alice);
        assertEq(uint256(r.status), uint256(IConstitution.RuleStatus.PROPOSED));
        assertEq(r.totalEndorsed, constitution.PROPOSAL_STAKE());
        assertEq(r.slashBps, 3000);
        assertFalse(r.immutable_);
        assertFalse(constitution.isRuleActive(TEST_RULE_1));

        // USDC deducted
        assertEq(usdc.balanceOf(alice), balBefore - constitution.PROPOSAL_STAKE());

        // Proposer's endorsement tracked
        assertEq(constitution.getEndorsement(TEST_RULE_1, alice), constitution.PROPOSAL_STAKE());
    }

    function test_AgentCannotProposeRule() public {
        vm.prank(agentOp);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.AgentsCannotGovern.selector));
        constitution.proposeRule(TEST_RULE_1, "Evil rule", IConstitution.RuleSeverity.LOW, 500);
    }

    function test_CannotProposeDuplicateRule() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "First", IConstitution.RuleSeverity.LOW, 500);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleAlreadyExists.selector, TEST_RULE_1));
        constitution.proposeRule(TEST_RULE_1, "Second", IConstitution.RuleSeverity.HIGH, 1000);
    }

    function test_CannotProposeWithInvalidSlash() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.InvalidSlashBps.selector));
        constitution.proposeRule(TEST_RULE_1, "Bad", IConstitution.RuleSeverity.LOW, Constants.MAX_SLASH_BPS + 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.InvalidSlashBps.selector));
        constitution.proposeRule(TEST_RULE_1, "Zero", IConstitution.RuleSeverity.LOW, 0);
    }

    // ── Endorsing rules ────────────────────────────────────────────

    function test_HumanCanEndorseProposedRule() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        vm.prank(bob);
        constitution.endorseRule(TEST_RULE_1, 500e6);

        IConstitution.Rule memory r = constitution.getRule(TEST_RULE_1);
        assertEq(r.totalEndorsed, constitution.PROPOSAL_STAKE() + 500e6);
        assertEq(constitution.getEndorsement(TEST_RULE_1, bob), 500e6);
    }

    function test_AgentCannotEndorse() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        vm.prank(agentOp);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.AgentsCannotGovern.selector));
        constitution.endorseRule(TEST_RULE_1, 100e6);
    }

    function test_CannotEndorseZero() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.ZeroAmount.selector));
        constitution.endorseRule(TEST_RULE_1, 0);
    }

    // ── Activating rules ───────────────────────────────────────────

    function test_RuleActivatesWhenThresholdMet() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        // Endorse enough to meet threshold
        uint256 remaining = THRESHOLD - constitution.PROPOSAL_STAKE();
        vm.prank(bob);
        constitution.endorseRule(TEST_RULE_1, remaining);

        uint256 vBefore = constitution.version();

        // Anyone can trigger activation
        constitution.activateRule(TEST_RULE_1);

        assertTrue(constitution.isRuleActive(TEST_RULE_1));
        assertEq(constitution.version(), vBefore + 1);

        IConstitution.Rule memory r = constitution.getRule(TEST_RULE_1);
        assertEq(uint256(r.status), uint256(IConstitution.RuleStatus.ACTIVE));
        assertGt(r.activatedAt, 0);
    }

    function test_CannotActivateBelowThreshold() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        // Only PROPOSAL_STAKE endorsed (100 USDC) — threshold is 1000 USDC
        vm.expectRevert(
            abi.encodeWithSelector(
                IConstitution.ThresholdNotMet.selector,
                TEST_RULE_1,
                constitution.PROPOSAL_STAKE(),
                THRESHOLD
            )
        );
        constitution.activateRule(TEST_RULE_1);
    }

    function test_CannotActivateNonProposedRule() public {
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotFound.selector, TEST_RULE_1));
        constitution.activateRule(TEST_RULE_1);
    }

    function test_CannotActivateAlreadyActiveRule() public {
        _proposeAndActivate(TEST_RULE_1, "Test", 2000);

        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotProposed.selector, TEST_RULE_1));
        constitution.activateRule(TEST_RULE_1);
    }

    // ── Opposing / Deprecating rules ───────────────────────────────

    function test_HumanCanOpposeActiveRule() public {
        _proposeAndActivate(TEST_RULE_1, "Test", 2000);

        vm.prank(charlie);
        constitution.opposeRule(TEST_RULE_1, 500e6);

        IConstitution.Rule memory r = constitution.getRule(TEST_RULE_1);
        assertEq(r.totalOpposed, 500e6);
    }

    function test_AgentCannotOppose() public {
        _proposeAndActivate(TEST_RULE_1, "Test", 2000);

        vm.prank(agentOp);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.AgentsCannotGovern.selector));
        constitution.opposeRule(TEST_RULE_1, 100e6);
    }

    function test_CannotOpposeProposedRule() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotActive.selector, TEST_RULE_1));
        constitution.opposeRule(TEST_RULE_1, 100e6);
    }

    function test_RuleDeprecatesWhenOppositionExceedsEndorsement() public {
        _proposeAndActivate(TEST_RULE_1, "Test", 2000);

        IConstitution.Rule memory r = constitution.getRule(TEST_RULE_1);
        uint256 endorsed = r.totalEndorsed;

        // Oppose with more than endorsed
        vm.prank(charlie);
        constitution.opposeRule(TEST_RULE_1, endorsed + 1);

        uint256 vBefore = constitution.version();

        // Anyone can trigger deprecation
        constitution.deprecateRule(TEST_RULE_1);

        assertFalse(constitution.isRuleActive(TEST_RULE_1));
        assertEq(constitution.version(), vBefore + 1);
    }

    function test_CannotDeprecateWhenOppositionTooLow() public {
        _proposeAndActivate(TEST_RULE_1, "Test", 2000);

        IConstitution.Rule memory r = constitution.getRule(TEST_RULE_1);

        // Oppose with less than endorsed
        vm.prank(charlie);
        constitution.opposeRule(TEST_RULE_1, r.totalEndorsed - 1);

        vm.expectRevert();
        constitution.deprecateRule(TEST_RULE_1);
    }

    function test_CannotDeprecateImmutableRule() public {
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, Constants.RULE_NO_HARM));
        constitution.deprecateRule(Constants.RULE_NO_HARM);
    }

    // ── Withdrawing endorsements ───────────────────────────────────

    function test_CanWithdrawFromProposedRule() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        constitution.withdrawEndorsement(TEST_RULE_1);

        assertEq(usdc.balanceOf(alice), balBefore + constitution.PROPOSAL_STAKE());
        assertEq(constitution.getEndorsement(TEST_RULE_1, alice), 0);
    }

    function test_CanWithdrawFromDeprecatedRule() public {
        _proposeAndActivate(TEST_RULE_1, "Test", 2000);

        IConstitution.Rule memory r = constitution.getRule(TEST_RULE_1);

        // Deprecate it
        vm.prank(charlie);
        constitution.opposeRule(TEST_RULE_1, r.totalEndorsed + 1);
        constitution.deprecateRule(TEST_RULE_1);

        // Now endorsers can withdraw
        uint256 aliceEndorsement = constitution.getEndorsement(TEST_RULE_1, alice);
        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        constitution.withdrawEndorsement(TEST_RULE_1);

        assertEq(usdc.balanceOf(alice), balBefore + aliceEndorsement);
    }

    function test_CannotWithdrawFromActiveRule() public {
        _proposeAndActivate(TEST_RULE_1, "Test", 2000);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleStillActive.selector, TEST_RULE_1));
        constitution.withdrawEndorsement(TEST_RULE_1);
    }

    function test_CannotWithdrawWithNoEndorsement() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        vm.prank(charlie); // charlie never endorsed
        vm.expectRevert(abi.encodeWithSelector(IConstitution.NoEndorsement.selector, TEST_RULE_1, charlie));
        constitution.withdrawEndorsement(TEST_RULE_1);
    }

    // ── Multiple rules ─────────────────────────────────────────────

    function test_MultipleRulesCoexist() public {
        _proposeAndActivate(TEST_RULE_1, "Rule 1", 2000);
        _proposeAndActivate(TEST_RULE_2, "Rule 2", 1000);

        assertTrue(constitution.isRuleActive(TEST_RULE_1));
        assertTrue(constitution.isRuleActive(TEST_RULE_2));

        bytes32[] memory active = constitution.getActiveRuleIds();
        assertEq(active.length, 7); // 5 core + 2 custom
    }

    // ── View functions ─────────────────────────────────────────────

    function test_ActivationThreshold() public view {
        assertEq(constitution.activationThreshold(), THRESHOLD);
    }

    function test_GetEndorsement() public {
        vm.prank(alice);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.MEDIUM, 2000);

        assertEq(constitution.getEndorsement(TEST_RULE_1, alice), constitution.PROPOSAL_STAKE());
        assertEq(constitution.getEndorsement(TEST_RULE_1, bob), 0);
    }

    // ── Helpers ────────────────────────────────────────────────────

    function _proposeAndActivate(bytes32 ruleId, string memory desc, uint256 slashBps) internal {
        vm.prank(alice);
        constitution.proposeRule(ruleId, desc, IConstitution.RuleSeverity.MEDIUM, slashBps);

        // Endorse to meet threshold
        uint256 remaining = THRESHOLD - constitution.PROPOSAL_STAKE();
        vm.prank(bob);
        constitution.endorseRule(ruleId, remaining);

        constitution.activateRule(ruleId);
    }
}
