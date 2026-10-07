// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title 1 Million Dolar (1MD)
/// @notice Fixed supply ERC-20. The immediate constructor caller receives the entire supply.
contract Token is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Historical constructor caller; this address has no administrative privileges.
    address public immutable deployer;

    constructor() ERC20("1 Million Dolar", "1MD") {
        deployer = msg.sender;
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
