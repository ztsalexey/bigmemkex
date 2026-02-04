// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/core/Constitution.sol";
import "../../src/libraries/Constants.sol";

contract ConstitutionTest is Test {
    Constitution public constitution;
    address public admin = makeAddr("admin");
    address public ruleManager = makeAddr("ruleManager");
    address public nonAdmin = makeAddr("nonAdmin");

    // Test rule constants
    bytes32 public constant TEST_RULE_1 = keccak256("TEST_RULE_1");
    bytes32 public constant TEST_RULE_2 = keccak256("TEST_RULE_2");
    
    // Core immutable rules from Constants
    bytes32[] public expectedImmutableRules;

    function setUp() public {
        // Deploy constitution with admin
        constitution = new Constitution(admin);

        // Note: Admin already has RULE_MANAGER_ROLE from constructor
        // We'll use admin for rule management operations in tests

        // Set up expected immutable rules
        expectedImmutableRules = [
            Constants.RULE_NO_HARM,
            Constants.RULE_OBEY_GOVERNANCE,
            Constants.RULE_TRANSPARENCY,
            Constants.RULE_PRESERVE_OVERRIDE,
            Constants.RULE_NO_SELF_MODIFY
        ];
    }

    function test_CoreImmutableRulesExistAndActiveAfterDeployment() public {
        // Check that constitution starts with version 1
        assertEq(constitution.version(), 1);
        
        // Check that all core immutable rules exist and are active
        for (uint256 i = 0; i < expectedImmutableRules.length; i++) {
            bytes32 ruleId = expectedImmutableRules[i];
            assertTrue(constitution.isRuleActive(ruleId), "Core rule should be active");
            
            IConstitution.Rule memory rule = constitution.getRule(ruleId);
            assertEq(rule.id, ruleId);
            assertTrue(rule.immutable_, "Core rule should be immutable");
            assertEq(uint256(rule.status), uint256(IConstitution.RuleStatus.ACTIVE));
            assertTrue(rule.slashBps > 0, "Core rule should have slash penalty");
        }

        // Check rule count includes all immutable rules
        assertEq(constitution.ruleCount(), expectedImmutableRules.length);
        
        // Check that getActiveRuleIds returns all immutable rules
        bytes32[] memory activeRules = constitution.getActiveRuleIds();
        assertEq(activeRules.length, expectedImmutableRules.length);
    }

    function test_CanProposeNewRule() public {
        vm.prank(admin);
        constitution.proposeRule(
            TEST_RULE_1,
            "Test rule description",
            IConstitution.RuleSeverity.MEDIUM,
            1000 // 10% slash
        );

        // Check rule exists in DRAFT status
        IConstitution.Rule memory rule = constitution.getRule(TEST_RULE_1);
        assertEq(rule.id, TEST_RULE_1);
        assertEq(rule.description, "Test rule description");
        assertEq(uint256(rule.severity), uint256(IConstitution.RuleSeverity.MEDIUM));
        assertEq(uint256(rule.status), uint256(IConstitution.RuleStatus.DRAFT));
        assertEq(rule.slashBps, 1000);
        assertEq(rule.proposer, admin);
        assertFalse(rule.immutable_);
        
        // Check rule count increased
        assertEq(constitution.ruleCount(), expectedImmutableRules.length + 1);
        
        // Rule should not be active yet
        assertFalse(constitution.isRuleActive(TEST_RULE_1));
    }

    function test_CanActivateProposedRule() public {
        // First propose a rule
        vm.prank(admin);
        constitution.proposeRule(
            TEST_RULE_1,
            "Test rule description",
            IConstitution.RuleSeverity.MEDIUM,
            1000
        );

        uint256 versionBefore = constitution.version();

        // Activate the rule
        vm.prank(admin);
        constitution.activateRule(TEST_RULE_1);

        // Check rule is now active
        assertTrue(constitution.isRuleActive(TEST_RULE_1));
        
        IConstitution.Rule memory rule = constitution.getRule(TEST_RULE_1);
        assertEq(uint256(rule.status), uint256(IConstitution.RuleStatus.ACTIVE));
        
        // Check version was bumped
        assertEq(constitution.version(), versionBefore + 1);
        
        // Check active rules now includes new rule
        bytes32[] memory activeRules = constitution.getActiveRuleIds();
        assertEq(activeRules.length, expectedImmutableRules.length + 1);
        
        // Verify the new rule is in the active rules list
        bool found = false;
        for (uint256 i = 0; i < activeRules.length; i++) {
            if (activeRules[i] == TEST_RULE_1) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Activated rule should be in active rules list");
    }

    function test_CannotDeprecateCriticalImmutableRules() public {
        // Try to deprecate each immutable rule
        for (uint256 i = 0; i < expectedImmutableRules.length; i++) {
            bytes32 ruleId = expectedImmutableRules[i];
            
            vm.prank(admin);
            vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleIsImmutable.selector, ruleId));
            constitution.deprecateRule(ruleId);
        }
    }

    function test_CanDeprecateNonImmutableRules() public {
        // First propose and activate a rule
        vm.startPrank(admin);
        constitution.proposeRule(
            TEST_RULE_1,
            "Test rule description",
            IConstitution.RuleSeverity.MEDIUM,
            1000
        );
        constitution.activateRule(TEST_RULE_1);
        vm.stopPrank();

        uint256 versionBefore = constitution.version();

        // Now deprecate it
        vm.prank(admin);
        constitution.deprecateRule(TEST_RULE_1);

        // Check rule is deprecated
        assertFalse(constitution.isRuleActive(TEST_RULE_1));
        
        IConstitution.Rule memory rule = constitution.getRule(TEST_RULE_1);
        assertEq(uint256(rule.status), uint256(IConstitution.RuleStatus.DEPRECATED));
        
        // Check version was bumped
        assertEq(constitution.version(), versionBefore + 1);
        
        // Check active rules no longer includes deprecated rule
        bytes32[] memory activeRules = constitution.getActiveRuleIds();
        assertEq(activeRules.length, expectedImmutableRules.length);
    }

    function test_VersionBumpsCorrectly() public {
        uint256 initialVersion = constitution.version();
        assertEq(initialVersion, 1);

        // Propose and activate a rule
        vm.startPrank(admin);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.LOW, 500);
        constitution.activateRule(TEST_RULE_1);
        vm.stopPrank();

        // Version should be bumped
        assertEq(constitution.version(), initialVersion + 1);

        // Deprecate the rule
        vm.prank(admin);
        constitution.deprecateRule(TEST_RULE_1);

        // Version should be bumped again
        assertEq(constitution.version(), initialVersion + 2);
    }

    function test_AccessControl_OnlyRuleManagerCanProposeRules() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        constitution.proposeRule(
            TEST_RULE_1,
            "Test rule description",
            IConstitution.RuleSeverity.MEDIUM,
            1000
        );
    }

    function test_AccessControl_OnlyRuleManagerCanActivateRules() public {
        // First propose a rule as admin
        vm.prank(admin);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.LOW, 500);

        // Try to activate as non-admin
        vm.prank(nonAdmin);
        vm.expectRevert();
        constitution.activateRule(TEST_RULE_1);
    }

    function test_AccessControl_OnlyRuleManagerCanDeprecateRules() public {
        // First propose and activate a rule as admin
        vm.startPrank(admin);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.LOW, 500);
        constitution.activateRule(TEST_RULE_1);
        vm.stopPrank();

        // Try to deprecate as non-admin
        vm.prank(nonAdmin);
        vm.expectRevert();
        constitution.deprecateRule(TEST_RULE_1);
    }

    function test_CustomErrors_RuleAlreadyExists() public {
        // Propose a rule
        vm.prank(admin);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.LOW, 500);

        // Try to propose the same rule again
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleAlreadyExists.selector, TEST_RULE_1));
        constitution.proposeRule(TEST_RULE_1, "Test2", IConstitution.RuleSeverity.HIGH, 1000);
    }

    function test_CustomErrors_RuleNotFound() public {
        // Try to get a rule that doesn't exist
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotFound.selector, TEST_RULE_1));
        constitution.getRule(TEST_RULE_1);

        // Try to activate a rule that doesn't exist
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotFound.selector, TEST_RULE_1));
        constitution.activateRule(TEST_RULE_1);

        // Try to deprecate a rule that doesn't exist
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotFound.selector, TEST_RULE_1));
        constitution.deprecateRule(TEST_RULE_1);
    }

    function test_CustomErrors_InvalidSlashBps() public {
        // Try to propose a rule with invalid slash BPS (over MAX_SLASH_BPS)
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.InvalidSlashBps.selector));
        constitution.proposeRule(
            TEST_RULE_1,
            "Test",
            IConstitution.RuleSeverity.LOW,
            Constants.MAX_SLASH_BPS + 1
        );
    }

    function test_CustomErrors_RuleNotActive() public {
        // Propose but don't activate a rule
        vm.prank(admin);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.LOW, 500);

        // Try to deprecate a rule that's not active
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotActive.selector, TEST_RULE_1));
        constitution.deprecateRule(TEST_RULE_1);
    }

    function test_CannotActivateAlreadyActiveRule() public {
        // Propose and activate a rule
        vm.startPrank(admin);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.LOW, 500);
        constitution.activateRule(TEST_RULE_1);

        // Try to activate it again — should fail with RuleNotDraft
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotDraft.selector, TEST_RULE_1));
        constitution.activateRule(TEST_RULE_1);
        vm.stopPrank();
    }

    function test_CannotDeprecateDeprecatedRule() public {
        // Propose, activate, and deprecate a rule
        vm.startPrank(admin);
        constitution.proposeRule(TEST_RULE_1, "Test", IConstitution.RuleSeverity.LOW, 500);
        constitution.activateRule(TEST_RULE_1);
        constitution.deprecateRule(TEST_RULE_1);

        // Try to deprecate it again
        vm.expectRevert(abi.encodeWithSelector(IConstitution.RuleNotActive.selector, TEST_RULE_1));
        constitution.deprecateRule(TEST_RULE_1);
        vm.stopPrank();
    }

    function test_ZeroAddressInConstructor() public {
        vm.expectRevert(abi.encodeWithSelector(IConstitution.ZeroAddress.selector));
        new Constitution(address(0));
    }

    function test_CoreRulesHaveCorrectSlashAmounts() public {
        // Test specific slash amounts for core rules
        IConstitution.Rule memory noHarmRule = constitution.getRule(Constants.RULE_NO_HARM);
        assertEq(noHarmRule.slashBps, Constants.MAX_SLASH_BPS); // 90%

        IConstitution.Rule memory governanceRule = constitution.getRule(Constants.RULE_OBEY_GOVERNANCE);
        assertEq(governanceRule.slashBps, 5000); // 50%

        IConstitution.Rule memory transparencyRule = constitution.getRule(Constants.RULE_TRANSPARENCY);
        assertEq(transparencyRule.slashBps, 2000); // 20%

        IConstitution.Rule memory preserveRule = constitution.getRule(Constants.RULE_PRESERVE_OVERRIDE);
        assertEq(preserveRule.slashBps, Constants.MAX_SLASH_BPS); // 90%

        IConstitution.Rule memory modifyRule = constitution.getRule(Constants.RULE_NO_SELF_MODIFY);
        assertEq(modifyRule.slashBps, Constants.MAX_SLASH_BPS); // 90%
    }

    function test_AllCoreRulesHaveCriticalSeverity() public {
        // Check that most core rules have CRITICAL severity except transparency
        IConstitution.Rule memory noHarmRule = constitution.getRule(Constants.RULE_NO_HARM);
        assertEq(uint256(noHarmRule.severity), uint256(IConstitution.RuleSeverity.CRITICAL));

        IConstitution.Rule memory governanceRule = constitution.getRule(Constants.RULE_OBEY_GOVERNANCE);
        assertEq(uint256(governanceRule.severity), uint256(IConstitution.RuleSeverity.CRITICAL));

        IConstitution.Rule memory transparencyRule = constitution.getRule(Constants.RULE_TRANSPARENCY);
        assertEq(uint256(transparencyRule.severity), uint256(IConstitution.RuleSeverity.HIGH));

        IConstitution.Rule memory preserveRule = constitution.getRule(Constants.RULE_PRESERVE_OVERRIDE);
        assertEq(uint256(preserveRule.severity), uint256(IConstitution.RuleSeverity.CRITICAL));

        IConstitution.Rule memory modifyRule = constitution.getRule(Constants.RULE_NO_SELF_MODIFY);
        assertEq(uint256(modifyRule.severity), uint256(IConstitution.RuleSeverity.CRITICAL));
    }
}