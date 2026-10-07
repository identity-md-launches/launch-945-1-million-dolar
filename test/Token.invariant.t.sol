// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

contract TokenHandler is Test {
    Token internal immutable token;
    address[4] internal actors = [address(0xA11CE), address(0xB0B), address(0xCAFE), address(0xD00D)];

    constructor(Token token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = token.balanceOf(from);
        uint256 allowance = token.allowance(from, spender);
        if (allowance < available) available = allowance;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.allowance(from, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }
}

contract TokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    Token internal token;

    function setUp() public {
        token = new Token();
        token.transfer(address(0xA11CE), SUPPLY);
        TokenHandler handler = new TokenHandler(token);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndAllBalancesAreConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 balances = token.balanceOf(address(0xA11CE)) + token.balanceOf(address(0xB0B))
            + token.balanceOf(address(0xCAFE)) + token.balanceOf(address(0xD00D));
        assertEq(balances, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
