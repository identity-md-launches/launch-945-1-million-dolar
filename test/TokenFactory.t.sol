// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "../src/Token.sol";
import {TokenFactory} from "../src/TokenFactory.sol";

contract TokenFactoryTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant RECIPIENT = address(0xA11CE);
    TokenFactory internal factory;

    function setUp() public {
        factory = new TokenFactory();
    }

    function test_factoryIsActualDeployerAndForwardsAllSupply() public {
        vm.recordLogs();
        vm.prank(CREATOR);
        Token token = factory.createToken(RECIPIENT);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // These are distinct operations: constructor mint to factory, then transfer to recipient.
        assertEq(logs.length, 3);
        bytes32 transferTopic = keccak256("Transfer(address,address,uint256)");
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics[0], transferTopic);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(factory)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(logs[1].emitter, address(token));
        assertEq(logs[1].topics[0], transferTopic);
        assertEq(logs[1].topics[1], logs[0].topics[2]);
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(RECIPIENT))));
        assertEq(abi.decode(logs[1].data, (uint256)), SUPPLY);
        assertEq(logs[2].emitter, address(factory));
        assertEq(logs[2].topics[0], keccak256("TokenCreated(address,address,address)"));
        assertEq(logs[2].topics[1], bytes32(uint256(uint160(address(token)))));
        assertEq(logs[2].topics[2], bytes32(uint256(uint160(CREATOR))));
        assertEq(logs[2].topics[3], bytes32(uint256(uint160(RECIPIENT))));

        assertEq(token.deployer(), address(factory));
        assertEq(factory.creatorOf(address(token)), CREATOR);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(RECIPIENT), SUPPLY);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.allowance(RECIPIENT, address(factory)), 0);
    }

    function test_anotherFactoryChangesDeployerForNewTokensOnly() public {
        Token first = factory.createToken(RECIPIENT);
        TokenFactory anotherFactory = new TokenFactory();
        Token second = anotherFactory.createToken(CREATOR);
        assertNotEq(address(first), address(second));
        assertEq(first.deployer(), address(factory));
        assertEq(second.deployer(), address(anotherFactory));
        assertEq(first.balanceOf(RECIPIENT), SUPPLY);
        assertEq(second.balanceOf(CREATOR), SUPPLY);
        assertEq(first.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(factory.creatorOf(address(second)), address(0));
        assertEq(anotherFactory.creatorOf(address(first)), address(0));
    }

    function test_permissionlessRepeatedDeploymentsAreIndependent() public {
        vm.prank(CREATOR);
        Token first = factory.createToken(CREATOR);
        vm.prank(RECIPIENT);
        Token second = factory.createToken(RECIPIENT);
        assertNotEq(address(first), address(second));
        assertEq(factory.creatorOf(address(first)), CREATOR);
        assertEq(factory.creatorOf(address(second)), RECIPIENT);
        vm.prank(CREATOR);
        first.transfer(RECIPIENT, 1);
        assertEq(first.balanceOf(RECIPIENT), 1);
        assertEq(second.balanceOf(RECIPIENT), SUPPLY);
        assertEq(first.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
    }

    function test_zeroRecipientRevertsBeforeCreatingToken() public {
        uint64 nonce = vm.getNonce(address(factory));
        vm.expectRevert(abi.encodeWithSelector(TokenFactory.InvalidRecipient.selector, address(0)));
        factory.createToken(address(0));
        assertEq(vm.getNonce(address(factory)), nonce);
        // Failure leaves the factory usable.
        assertEq(factory.createToken(RECIPIENT).balanceOf(RECIPIENT), SUPPLY);
    }

    function test_factoryCannotBeRecipient() public {
        uint64 nonce = vm.getNonce(address(factory));
        vm.expectRevert(abi.encodeWithSelector(TokenFactory.InvalidRecipient.selector, address(factory)));
        factory.createToken(address(factory));
        assertEq(vm.getNonce(address(factory)), nonce);
    }

    function test_factoryAndCreatorHaveNoAuthorityOverDistributedTokens() public {
        vm.prank(CREATOR);
        Token token = factory.createToken(RECIPIENT);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        vm.prank(address(factory));
        token.transferFrom(RECIPIENT, CREATOR, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, CREATOR, 0, 1));
        vm.prank(CREATOR);
        token.transferFrom(RECIPIENT, CREATOR, 1);
        vm.prank(RECIPIENT);
        token.transfer(CREATOR, SUPPLY);
        assertEq(token.balanceOf(CREATOR), SUPPLY);
    }

    function test_nativeCurrencyIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool succeeded,) = address(factory).call{value: 1}(abi.encodeCall(TokenFactory.createToken, (RECIPIENT)));
        assertFalse(succeeded);
        (succeeded,) = address(factory).call{value: 1}("");
        assertFalse(succeeded);
        assertEq(address(factory).balance, 0);
    }

    function testFuzz_chosenRecipientGetsExactSupply(address recipient) public {
        vm.assume(recipient != address(0) && recipient != address(factory));
        vm.prank(CREATOR);
        Token token = factory.createToken(recipient);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.deployer(), address(factory));
        assertEq(factory.creatorOf(address(token)), CREATOR);
    }
}
