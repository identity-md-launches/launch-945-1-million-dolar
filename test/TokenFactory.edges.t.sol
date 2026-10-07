// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Token} from "src/Token.sol";
import {TokenFactory} from "src/TokenFactory.sol";

contract FactoryCallerProbe {
    function create(TokenFactory factory, address recipient) external returns (Token) {
        return factory.createToken(recipient);
    }

    function createThenFail(TokenFactory factory, address recipient) external {
        factory.createToken(recipient);
        factory.createToken(address(factory));
    }
}

contract RejectingRecipientProbe {
    fallback() external {
        revert("recipient must not be called");
    }

    function send(Token token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract TokenFactoryEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    TokenFactory internal factory;

    function setUp() public {
        factory = new TokenFactory();
    }

    function test_contractCreatorIsRecordedInsteadOfTransactionOrigin() public {
        FactoryCallerProbe caller = new FactoryCallerProbe();
        vm.prank(ALICE, BOB);
        Token created = caller.create(factory, ALICE);
        assertEq(factory.creatorOf(address(created)), address(caller));
        assertEq(created.deployer(), address(factory));
        assertEq(created.balanceOf(ALICE), SUPPLY);
        assertEq(created.balanceOf(address(caller)), 0);
        assertEq(created.balanceOf(BOB), 0);
        assertEq(created.balanceOf(address(factory)), 0);
    }

    function test_contractRecipientNeedsNoCallbackAndCanTransferWholeSupply() public {
        RejectingRecipientProbe recipient = new RejectingRecipientProbe();
        Token created = factory.createToken(address(recipient));
        assertEq(created.balanceOf(address(recipient)), SUPPLY);
        assertTrue(recipient.send(created, ALICE, SUPPLY));
        assertEq(created.balanceOf(ALICE), SUPPLY);
        assertEq(created.balanceOf(address(recipient)), 0);
        assertEq(created.balanceOf(address(factory)), 0);
        assertEq(created.totalSupply(), SUPPLY);
    }

    function test_failedBatchRollsBackMintRegistryAndCreationNonce() public {
        FactoryCallerProbe caller = new FactoryCallerProbe();
        uint64 nonce = vm.getNonce(address(factory));
        address predicted = vm.computeCreateAddress(address(factory), nonce);
        vm.expectRevert(abi.encodeWithSelector(TokenFactory.InvalidRecipient.selector, address(factory)));
        caller.createThenFail(factory, ALICE);
        assertEq(predicted.code.length, 0);
        assertEq(factory.creatorOf(predicted), address(0));
        assertEq(vm.getNonce(address(factory)), nonce);

        vm.prank(BOB);
        Token recovered = factory.createToken(ALICE);
        assertEq(address(recovered), predicted);
        assertEq(factory.creatorOf(predicted), BOB);
        assertEq(recovered.balanceOf(ALICE), SUPPLY);
        assertEq(recovered.balanceOf(address(factory)), 0);
    }

    function test_repeatedRejectionsPreserveEarlierTokenAndNextDeployment() public {
        vm.prank(ALICE);
        Token earlier = factory.createToken(ALICE);
        vm.prank(ALICE);
        earlier.approve(BOB, 19);
        uint64 nonce = vm.getNonce(address(factory));
        address predicted = vm.computeCreateAddress(address(factory), nonce);
        for (uint256 i; i < 4; ++i) {
            address invalid = i % 2 == 0 ? address(0) : address(factory);
            vm.expectRevert(abi.encodeWithSelector(TokenFactory.InvalidRecipient.selector, invalid));
            vm.prank(BOB);
            factory.createToken(invalid);
        }
        assertEq(vm.getNonce(address(factory)), nonce);
        assertEq(factory.creatorOf(predicted), address(0));
        assertEq(predicted.code.length, 0);
        vm.prank(BOB);
        Token later = factory.createToken(BOB);
        assertEq(address(later), predicted);
        assertEq(factory.creatorOf(address(earlier)), ALICE);
        assertEq(factory.creatorOf(address(later)), BOB);
        assertEq(earlier.balanceOf(ALICE), SUPPLY);
        assertEq(earlier.allowance(ALICE, BOB), 19);
        assertEq(later.balanceOf(BOB), SUPPLY);
        assertEq(later.allowance(ALICE, BOB), 0);
        assertEq(earlier.totalSupply(), SUPPLY);
        assertEq(later.totalSupply(), SUPPLY);
    }
}
