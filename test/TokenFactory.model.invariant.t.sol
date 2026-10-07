// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "src/Token.sol";
import {TokenFactory} from "src/TokenFactory.sol";

/// @dev Closed actor universe: every possible recipient is tracked. Expectations come from
/// requested operations, never from balanceOf/allowance, so incorrect results cannot reset the oracle.
contract FactoryTokenModelHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 internal constant MAX_TOKENS = 6;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCAFE), address(0xD00D)];
    TokenFactory[2] public factories;
    Token[] public tokens;
    mapping(uint256 => uint256) public deployingFactory;
    mapping(uint256 => address) public creator;
    mapping(uint256 => mapping(address => uint256)) public expectedBalance;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public expectedAllowance;

    constructor() {
        factories[0] = new TokenFactory();
        factories[1] = new TokenFactory();
        _create(0, actors[0], actors[1]);
        _create(1, actors[2], actors[3]);
    }

    function tokenCount() external view returns (uint256) {
        return tokens.length;
    }

    function create(uint256 factorySeed, uint256 creatorSeed, uint256 recipientSeed) external {
        // Bound deployment cost and the size of the accounting universe, not transfer amounts.
        if (tokens.length == MAX_TOKENS) return;
        _create(factorySeed % 2, _actor(creatorSeed), _actor(recipientSeed));
    }

    function transfer(uint256 tokenSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 id = tokenSeed % tokens.length;
        address from = _fundedActor(id, fromSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[id][from]);
        vm.prank(from);
        assertTrue(tokens[id].transfer(to, amount));
        _move(id, from, to, amount);
    }

    function approve(uint256 tokenSeed, uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 amount;
        uint256 mode = amountSeed % 5;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = 1;
        else if (mode == 2) amount = type(uint256).max;
        else if (mode == 3) amount = type(uint256).max - 1;
        else amount = bound(amountSeed, 0, SUPPLY);
        _approve(tokenSeed % tokens.length, _actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 tokenSeed, uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed)
        external
    {
        uint256 id = tokenSeed % tokens.length;
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 available = expectedBalance[id][from];
        uint256 allowed = expectedAllowance[id][from][spender];
        if (allowed < available) available = allowed;
        _spend(id, from, _actor(toSeed), spender, bound(amountSeed, 0, available));
    }

    function approveAndSpend(
        uint256 tokenSeed,
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        uint256 id = tokenSeed % tokens.length;
        address owner = _fundedActor(id, ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = actors[(spenderSeed % actors.length + 1) % actors.length];
        // This action always spends a positive amount, avoiding a campaign of zero transfers.
        uint256 amount = bound(amountSeed, 1, expectedBalance[id][owner]);
        _approve(id, owner, spender, infinite ? type(uint256).max : amount);
        _spend(id, owner, recipient, spender, amount);
    }

    function rejectTransfer(uint256 tokenSeed, uint256 ownerSeed, uint256 amountSeed, bool zeroRecipient) external {
        uint256 id = tokenSeed % tokens.length;
        address owner = _actor(ownerSeed);
        uint256 held = expectedBalance[id][owner];
        if (zeroRecipient) {
            uint256 amount = bound(amountSeed, 0, held);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            tokens[id].transfer(address(0), amount);
        } else {
            uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
            vm.prank(owner);
            tokens[id].transfer(actors[(ownerSeed % actors.length + 1) % actors.length], amount);
        }
        // No ghost updates: all balances and approvals must still match after a rejected call.
    }

    function rejectSpend(uint256 tokenSeed, uint256 ownerSeed, uint256 spenderSeed, uint256 modeSeed) external {
        uint256 id = tokenSeed % tokens.length;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 held = expectedBalance[id][owner];
        uint256 mode = modeSeed % 3;
        if (mode == 0) {
            _approve(id, owner, spender, 0);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
            vm.prank(spender);
            tokens[id].transferFrom(owner, spender, 1);
        } else if (mode == 1) {
            uint256 amount = held + 1;
            _approve(id, owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
            vm.prank(spender);
            tokens[id].transferFrom(owner, spender, amount);
        } else {
            _approve(id, owner, spender, held);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            tokens[id].transferFrom(owner, address(0), held);
        }
        assertEq(tokens[id].allowance(owner, spender), expectedAllowance[id][owner][spender]);
    }

    function rejectApproval(uint256 tokenSeed, uint256 ownerSeed, uint256 amount) external {
        uint256 id = tokenSeed % tokens.length;
        address owner = _actor(ownerSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        tokens[id].approve(address(0), amount);
        assertEq(tokens[id].allowance(owner, address(0)), 0);
    }

    function rejectCreation(uint256 factorySeed, uint256 callerSeed, bool zeroRecipient) external {
        TokenFactory factory = factories[factorySeed % 2];
        address recipient = zeroRecipient ? address(0) : address(factory);
        uint64 nonce = vm.getNonce(address(factory));
        address predicted = vm.computeCreateAddress(address(factory), nonce);
        vm.expectRevert(abi.encodeWithSelector(TokenFactory.InvalidRecipient.selector, recipient));
        vm.prank(_actor(callerSeed));
        factory.createToken(recipient);
        assertEq(vm.getNonce(address(factory)), nonce);
        assertEq(factory.creatorOf(predicted), address(0));
        assertEq(predicted.code.length, 0);
    }

    function _create(uint256 factoryId, address caller, address recipient) internal {
        vm.prank(caller);
        Token created = factories[factoryId].createToken(recipient);
        uint256 id = tokens.length;
        tokens.push(created);
        deployingFactory[id] = factoryId;
        creator[id] = caller;
        expectedBalance[id][recipient] = SUPPLY;
        assertEq(created.balanceOf(recipient), SUPPLY);
        for (uint256 i; i < id; ++i) {
            assertNotEq(address(tokens[i]), address(created));
        }
    }

    function _approve(uint256 id, address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(tokens[id].approve(spender, amount));
        expectedAllowance[id][owner][spender] = amount;
        assertEq(tokens[id].allowance(owner, spender), amount);
    }

    function _spend(uint256 id, address from, address to, address spender, uint256 amount) internal {
        vm.prank(spender);
        assertTrue(tokens[id].transferFrom(from, to, amount));
        if (expectedAllowance[id][from][spender] != type(uint256).max) {
            expectedAllowance[id][from][spender] -= amount;
        }
        _move(id, from, to, amount);
        assertEq(tokens[id].allowance(from, spender), expectedAllowance[id][from][spender]);
    }

    function _move(uint256 id, address from, address to, uint256 amount) internal {
        expectedBalance[id][from] -= amount;
        expectedBalance[id][to] += amount;
        assertEq(tokens[id].balanceOf(from), expectedBalance[id][from]);
        assertEq(tokens[id].balanceOf(to), expectedBalance[id][to]);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _fundedActor(uint256 id, uint256 seed) internal view returns (address) {
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(seed % actors.length + i) % actors.length];
            if (expectedBalance[id][candidate] > 0) return candidate;
        }
        revert("model lost the fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract FactoryTokenModelInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    FactoryTokenModelHandler internal handler;

    function setUp() public {
        handler = new FactoryTokenModelHandler();
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.create.selector;
        selectors[1] = handler.transfer.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.approveAndSpend.selector;
        selectors[5] = handler.rejectTransfer.selector;
        selectors[6] = handler.rejectSpend.selector;
        selectors[7] = handler.rejectApproval.selector;
        selectors[8] = handler.rejectCreation.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariant_balancesMatchIndependentLedgerAndSupplyIsConserved() public view {
        for (uint256 id; id < handler.tokenCount(); ++id) {
            Token token = handler.tokens(id);
            uint256 sum;
            for (uint256 i; i < 4; ++i) {
                address actor = handler.actors(i);
                uint256 balance = token.balanceOf(actor);
                assertEq(balance, handler.expectedBalance(id, actor));
                sum += balance;
            }
            assertEq(sum, SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.balanceOf(address(handler)), 0);
            assertEq(token.balanceOf(address(handler.factories(0))), 0);
            assertEq(token.balanceOf(address(handler.factories(1))), 0);
        }
    }

    function invariant_allAllowancesMatchIndependentLedger() public view {
        for (uint256 id; id < handler.tokenCount(); ++id) {
            Token token = handler.tokens(id);
            for (uint256 i; i < 4; ++i) {
                address owner = handler.actors(i);
                for (uint256 j; j < 4; ++j) {
                    address spender = handler.actors(j);
                    assertEq(token.allowance(owner, spender), handler.expectedAllowance(id, owner, spender));
                }
                assertEq(token.allowance(owner, address(handler.factories(0))), 0);
                assertEq(token.allowance(owner, address(handler.factories(1))), 0);
            }
        }
    }

    function invariant_factoryProvenanceAndTokenMetadataRemainIndependent() public view {
        for (uint256 id; id < handler.tokenCount(); ++id) {
            Token token = handler.tokens(id);
            uint256 factoryId = handler.deployingFactory(id);
            TokenFactory factory = handler.factories(factoryId);
            assertEq(token.deployer(), address(factory));
            assertEq(factory.creatorOf(address(token)), handler.creator(id));
            assertEq(handler.factories(1 - factoryId).creatorOf(address(token)), address(0));
            assertEq(token.name(), "1 Million Dolar");
            assertEq(token.symbol(), "1MD");
            assertEq(token.decimals(), 18);
            assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        }
    }
}
