// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "src/Token.sol";

/// forge-config: default.fuzz.runs = 1000
contract TokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    Token internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Token();
        token.transfer(ALICE, SUPPLY);
    }

    function test_oneWeiThenRemainingSupplyCanBeSpentExactlyOnce() public {
        vm.prank(ALICE);
        token.approve(SPENDER, SUPPLY);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), SUPPLY - 1);
        assertTrue(token.transferFrom(ALICE, BOB, SUPPLY - 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, SPENDER), 0);
        _assertBalances(0, SUPPLY);
    }

    function test_maximumTransferRevertsWithoutOverflowOrMinting() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, type(uint256).max)
        );
        vm.prank(ALICE);
        token.transfer(BOB, type(uint256).max);
        _assertBalances(SUPPLY, 0);
    }

    function test_supplyPlusOneRevertsEvenOnSelfTransfer() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, SUPPLY + 1)
        );
        vm.prank(ALICE);
        token.transfer(ALICE, SUPPLY + 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_maximumDelegatedTransferCannotSpendBeyondBalance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, type(uint256).max)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, type(uint256).max);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        _assertBalances(SUPPLY, 0);
    }

    function test_maximumMinusOneApprovalIsFinite() public {
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, SUPPLY));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max - 1 - SUPPLY);
        _assertBalances(0, SUPPLY);
    }

    function test_delegatedSelfTransferConsumesAllowanceButKeepsBalance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, ALICE, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, ALICE, SUPPLY));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_ownerCannotBypassTransferFromAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1);
        vm.prank(ALICE);
        token.approve(ALICE, 1);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(ALICE, ALICE, 1));
        assertEq(token.allowance(ALICE, ALICE), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroDelegatedTransferNeedsNeitherBalanceNorApproval() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(BOB, ALICE, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(BOB, ALICE, 0));
        assertEq(token.allowance(BOB, SPENDER), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 0);
        assertEq(token.allowance(ALICE, address(0)), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_infiniteAllowanceCanBeReplacedAndRevoked() public {
        vm.startPrank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, 1);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 2);
        assertEq(token.allowance(ALICE, SPENDER), 1);
        vm.prank(ALICE);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_failedTransferDoesNotChangeBalances(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        vm.prank(ALICE);
        token.transfer(BOB, SUPPLY - held);
        amount = bound(amount, held + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        _assertBalances(held, SUPPLY - held);
    }

    function testFuzz_failedSpendRestoresFiniteAllowance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max - 1);
        vm.prank(ALICE);
        token.transfer(BOB, SUPPLY - held);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), amount);
        _assertBalances(held, SUPPLY - held);
    }

    function testFuzz_insufficientAllowanceIsAtomic(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY - 1);
        amount = bound(amount, approval + 1, SUPPLY);
        vm.prank(ALICE);
        token.approve(SPENDER, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approval, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_zeroReceiverRestoresAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approval = infinite ? type(uint256).max : amount;
        vm.prank(ALICE);
        token.approve(SPENDER, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_allowancesAreIsolatedByOwnerAndSpender(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY);
        amount = bound(amount, 0, approval);
        vm.startPrank(ALICE);
        token.approve(SPENDER, approval);
        token.approve(BOB, type(uint256).max);
        vm.stopPrank();
        // A holder with no tokens can approve future spending without moving any value.
        vm.prank(BOB);
        token.approve(SPENDER, 17);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.allowance(ALICE, SPENDER), approval - amount);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max);
        assertEq(token.allowance(BOB, SPENDER), 17);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        _assertBalances(SUPPLY - amount, amount);
    }

    function testFuzz_roundTripRestoresBalancesWithoutTouchingApproval(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        vm.startPrank(ALICE);
        token.approve(SPENDER, approval);
        assertTrue(token.transfer(BOB, amount));
        vm.stopPrank();
        assertEq(token.balanceOf(BOB), amount);
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.allowance(ALICE, SPENDER), approval);
        _assertBalances(SUPPLY, 0);
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance) internal view {
        assertEq(token.balanceOf(ALICE), aliceBalance);
        assertEq(token.balanceOf(BOB), bobBalance);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
