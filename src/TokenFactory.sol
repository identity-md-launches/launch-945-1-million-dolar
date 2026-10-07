// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Token} from "./Token.sol";

/// @title Separate deployment factory for 1MD tokens
/// @notice Anyone may create an independent token. This factory is its constructor deployer.
/// @dev Construction of the factory itself deploys no token and moves no existing supply.
contract TokenFactory {
    error InvalidRecipient(address recipient);
    error SupplyTransferFailed();

    event TokenCreated(address indexed token, address indexed creator, address indexed recipient);

    /// @notice Records the caller that requested each token. Zero means not created here.
    mapping(address token => address creator) public creatorOf;

    /// @notice Mints to this factory through the token constructor, then forwards the whole supply.
    /// @param recipient Receives the supply after construction; cannot be zero or this factory.
    /// @return token A new, independent 1MD token whose immutable deployer is this factory.
    function createToken(address recipient) external returns (Token token) {
        if (recipient == address(0) || recipient == address(this)) {
            revert InvalidRecipient(recipient);
        }

        token = new Token();
        creatorOf[address(token)] = msg.sender;
        // Only the concrete Token deployed above is called; it has no receiver callback.
        if (!token.transfer(recipient, token.totalSupply())) revert SupplyTransferFailed();
        // Token cannot call back, so these logs always follow the mint and forwarding transfer.
        // forge-lint: disable-next-line(reentrancy-events)
        emit TokenCreated(address(token), msg.sender, recipient);
    }
}
