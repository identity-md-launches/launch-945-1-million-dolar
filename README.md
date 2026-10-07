# 1 Million Dolar (1MD)

A fixed supply ERC-20 and a separate, permissionless factory for creating independent
instances. Solidity is pinned to **0.8.26**, targeting Cancun, with optimizer runs set
to 200 and `bytecode_hash = "none"` for reproducible runtime bytecode.

## Token

| Property | Value |
| --- | --- |
| Contract | `src/Token.sol:Token` |
| Name | `1 Million Dolar` (spelling intentional) |
| Symbol | `1MD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor recipient | `msg.sender`, the immediate deployer |

The constructor mints the entire supply once. `deployer()` records its immediate caller
permanently and grants no permissions. A direct deployment mints to the deploying
account; a contract deployment mints to that contract, including a CREATE2 launch.
There is no use of `tx.origin`.

Transfers follow the vendored OpenZeppelin ERC-20 implementation. They have no fees,
burns, rebasing, restrictions specific to pools, or receiver callbacks. The token has
no owner, mint entry point, pause, blacklist, seizure, upgrade, or initialization
mechanism. Zero-value and self-transfers are supported; transfers to zero revert.
Only the holder or an approved spender can transfer a holder's balance.

`approve` replaces the previous allowance. Finite allowances decrease when spent;
the ERC-20 maximum allowance remains unchanged. Users should approve only needed
amounts and revoke obsolete allowances. Changing an existing nonzero allowance can
be subject to transaction ordering; revoke it first when that matters. Neither the
token nor the factory accepts ordinary native-currency payments.

## Factory and the meaning of “changing the deployer”

The task's factory wording is interpreted as deploying through **another factory
contract**, changing the immediate constructor caller for new tokens. This is not a
mutable deployment role on an existing token: historical deployment cannot change.

`src/TokenFactory.sol:TokenFactory` has no constructor arguments or administrator.
Anyone can call `createToken(address recipient)` with zero native value:

1. It rejects the zero address and its own address as recipient.
2. It creates a fresh `Token`; the token mints all `10^27` units to the factory.
3. It records `creatorOf(token)` as the caller, then transfers the full supply to
   `recipient` in the same transaction.
4. It emits `TokenCreated(token, creator, recipient)` and returns the token address.

The transaction is atomic: a failure rolls back the creation, mapping, and transfers.
The token's mint and forwarding `Transfer` events precede `TokenCreated`. The factory
calls only its freshly deployed, fixed token implementation, which cannot invoke a
receiver callback. That is why its final event is safe after the transfer; the local
lint exception documents this fact.

Each call creates an independent token with its own fixed supply. A second factory
produces tokens whose `deployer()` is that second factory. Neither creating a factory
nor creating more tokens changes an existing token's supply, deployer, or balances.
Repeated names and symbols do not establish identity: applications must use the
verified token address and chain ID. `creatorOf` is provenance, not an access role.

The factory retains no initial token balance or approval. There is no general
withdrawal, arbitrary execution, or rescue function. Do not send assets to the factory
outside `createToken`; such assets cannot be recovered through it. Choose a recipient
whose keys you control or a contract that can manage ERC-20 balances. A contract
recipient is not automatically validated as capable of spending its tokens.

## Deployment parameters and launch integration

The two independent deployment artifacts are:

| Artifact | Constructor parameters | Effect at construction |
| --- | --- | --- |
| `src/Token.sol:Token` | None | Mints full supply to immediate caller |
| `src/TokenFactory.sol:TokenFactory` | None | Creates no token and moves no funds |

For a standalone factory deployment, deploy `TokenFactory`, call
`createToken(recipient)`, and obtain the token address from `TokenCreated` (a Solidity
caller also receives it as a return value). For a direct token deployment, deploy
`Token` and the immediate constructor caller holds the entire supply. No initialization
transaction is needed in either case. The recipient is a call parameter, never an
environment-dependent default. This repository includes no broadcasting script or key
configuration.

For the IdentityMD custom-token launch, the launch system must deploy `Token`
**directly from its ProjectFactory** using the token's creation code and empty
constructor arguments. It may separately deploy `TokenFactory` as an application
with empty constructor arguments. This preserves the launch factory's full initial
balance. Do not substitute `TokenFactory.createToken` for the platform's launch path:
that function creates a different token and forwards its supply immediately.

The platform remains responsible for its distributor, the mandatory 10% swarm
allocation, pool initialization/seeding, swaps, and forwarding the requester remainder.
The token makes those transfers exactly, without tax or exemptions. It intentionally
does not duplicate those platform responsibilities. The task provides no chain,
paired-currency address, pool fee/tick settings, market cap, pool allocation, or
requester wallet; those must come from the actual launch job. No addresses or economics
have been invented, and no `launch.json` is supplied.

The deployment operator must select a Cancun-compatible chain, verify the recipient
and artifact settings, check the resulting token address, metadata, supply, and mint
event, and verify source on the target explorer. No administrator, keeper, or
post-deployment maintenance transaction is required by these contracts. There is no
privileged account that can recover holder balances or repair a mistaken transfer.
Independent adversarial review and the platform's full launch checks remain release
responsibilities; passing this local suite is not a security audit. No transaction was
broadcast as part of this assignment.

## Build and verification

With Foundry and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
```

All imported libraries and their licenses are ordinary files under `lib/`; no install,
submodule, network, environment variables, FFI, or filesystem cheatcode permissions are
required by the tests. Dependency versions and integrity hashes are documented in
`DEPENDENCIES.md` and `dependencies.sha256`.

The suite covers metadata, constructor events and CREATE2 caller provenance, exact
transfers and distribution claims, allowances and revocation, zero-address and
insufficient-balance failures, rollback of spent allowances, rejected admin calls,
runtime opcode restrictions, factory provenance and event order, independent factories
and repeated deployments, invalid recipients, rejected native value, fuzzed amounts and
recipients, and stateful balance/supply conservation. Invariants run 128 sequences of
64 actions; each parameterized fuzz test runs 256 cases. Tests use isolated state and
do not read or write process environment variables.

The supplied protected suite was read as an integration specification. It depends on
the host launch contracts (`LaunchLiquidity`, `PoolInitializationGuard`, `HookFlags`),
Uniswap v4, and resolved launch settings absent from this empty project. The local suite
checks portable token/factory requirements; it does not claim to run that harness or
validate a real pool's initialization, seed, and swaps. Those remain part of the
platform's independent launch verification. Slither and Mythril were not run.
