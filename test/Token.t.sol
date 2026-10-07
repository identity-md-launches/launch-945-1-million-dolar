// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "../src/Token.sol";
import {TokenFactory} from "../src/TokenFactory.sol";

/// @dev Models the constructor caller used by the network's CREATE2 launch process.
contract ConstructorCaller {
    function deploy(bytes32 salt) external returns (Token) {
        return new Token{salt: salt}();
    }
}

contract TokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    Token internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Token();
    }

    function test_metadataAndExactSupply() public view {
        assertEq(token.name(), "1 Million Dolar");
        assertEq(token.symbol(), "1MD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.deployer(), address(this));
    }

    function test_constructorEmitsOneMintToImmediateCaller() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        Token created = new Token();
        assertEq(created.balanceOf(ALICE), SUPPLY);
        assertEq(created.deployer(), ALICE);
        assertEq(created.balanceOf(address(this)), 0);
    }

    function test_create2MintsToContractCallerAndNotTransactionOrigin() public {
        ConstructorCaller caller = new ConstructorCaller();
        vm.prank(ALICE, BOB);
        Token created = caller.deploy(bytes32(uint256(7)));
        assertEq(created.deployer(), address(caller));
        assertEq(created.balanceOf(address(caller)), SUPPLY);
        assertEq(created.balanceOf(ALICE), 0);
        assertEq(created.balanceOf(BOB), 0);
        assertEq(created.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 12e18);
        assertTrue(token.transfer(ALICE, 12e18));
        assertEq(token.balanceOf(ALICE), 12e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 12e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAndSelfTransfersPreserveSupply() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRejectsZeroRecipientEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRejectsInsufficientBalanceWithoutChangingBalances() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 5e18);
        assertTrue(token.approve(SPENDER, 5e18));
        assertEq(token.allowance(address(this), SPENDER), 5e18);
        assertTrue(token.approve(SPENDER, 2e18));
        assertEq(token.allowance(address(this), SPENDER), 2e18);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_approveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromConsumesExactAllowance() public {
        token.approve(SPENDER, 8e18);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 3e18));
        assertEq(token.balanceOf(ALICE), 3e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3e18);
        assertEq(token.allowance(address(this), SPENDER), 5e18);
    }

    function test_transferFromWithInfiniteAllowanceDoesNotDecreaseIt() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 3e18));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 3e18);
    }

    function test_transferFromRejectsInsufficientAllowance() public {
        token.approve(SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 2);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_failedTransferFromRestoresSpentAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRejectsZeroRecipientAndRestoresAllowance() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromRejectsZeroSender() public {
        // OpenZeppelin validates the allowance owner before reaching the transfer for amount zero.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_revokedApprovalCannotSpend() public {
        token.approve(SPENDER, 10);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_deployerCannotSpendHoldersTokensWithoutApproval() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
    }

    function test_launchDistributionAndClaimDeliverExactAmounts() public {
        address distributor = address(0xD157);
        uint256 swarm = SUPPLY / 10;
        assertTrue(token.transfer(distributor, swarm));
        assertEq(token.balanceOf(distributor), swarm);
        vm.prank(distributor);
        assertTrue(token.transfer(ALICE, swarm));
        assertEq(token.balanceOf(ALICE), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - swarm);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_applicationFactoryConstructorPreservesExistingLaunchSupply() public {
        ConstructorCaller caller = new ConstructorCaller();
        Token launched = caller.deploy(bytes32(0));
        TokenFactory factory = new TokenFactory();
        assertGt(address(factory).code.length, 0);
        assertLe(address(factory).code.length, 24_576);
        assertEq(launched.balanceOf(address(caller)), SUPPLY);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_noPostDeploymentMintOrAdministration() public {
        token.transfer(ALICE, 100);
        string[22] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1));
            (bool deployerSucceeded,) = address(token).call(data);
            assertFalse(deployerSucceeded, signatures[i]);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(data);
            assertFalse(strangerSucceeded, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function test_nativeCurrencyIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool succeeded,) = address(token).call{value: 1}("");
        assertFalse(succeeded);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConsumesAllowance(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY);
        amount = bound(amount, 0, approval);
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approval - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
