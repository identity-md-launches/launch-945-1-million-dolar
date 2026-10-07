# Additional 1MD tests

These tests extend the existing suite without changing the implementation or its dependencies.

## Properties and permissions

- Each token has exactly `1_000_000_000 * 10**18` minor units. Constructor minting credits the immediate caller.
- A factory deployment mints to that factory, then forwards the entire supply to the chosen recipient. The factory records its immediate caller as creator, independently of transaction origin.
- The deployer and creator have no spending authority over a holder without approval. Approvals belong to an individual owner/spender pair and token.
- Transfers conserve supply and deliver the exact amount; finite allowances decrease by the amount spent, including self-transfers. Infinite allowances persist until replaced or revoked.
- Rejected operations preserve balances, allowances, creation nonces, and creator records. A reverted batch must also roll back earlier deployments within that batch.

## Added coverage

`Token.edges.t.sol` pins zero, one minor unit, full supply, supply plus one, and maximum integer boundaries. Six fuzz properties run 1,000 inputs each, covering failed-call rollback, allowance isolation, and transfer round trips.

`TokenFactory.edges.t.sol` covers contract callers, recipients with reverting fallbacks, deployment rollback, and successful deployment after repeated invalid requests.

`TokenFactory.model.invariant.t.sol` uses four actors, two factories, and up to six independent tokens. Nine handler actions mix creation, approval, direct and delegated transfers, and deliberately rejected calls. Ghost balances and allowances are derived from requested operations, not copied from token getters. All tracked balances and approval pairs are compared after random calls. A funded-actor action ensures positive delegated transfers are exercised. Each invariant runs 256 sequences of depth 64, with unexpected handler reverts treated as failures.

The actor universe is closed: no handler sends tokens outside the four tracked holders. Zero factory balances therefore describe the tested creation and transfer flows, not a claim that unsolicited donations are impossible. The six-token cap bounds deployment cost and accounting work.

## Checks and limits

Run `forge build` and `forge test` from the repository root. The tests require no network, environment variables, forks, FFI, or additional dependencies.

Slither was run with `slither . --filter-paths 'test/|lib/' --exclude-dependencies`. Its sole finding was `reentrancy-events` in `TokenFactory.createToken`. This is a false positive: the call target is the concrete, freshly created `Token`, and its transfer does not call the recipient or otherwise permit reentry. Aderyn was not available in the environment.

The supplied protected launch harness was reviewed as an acceptance reference. Its external pool implementation, launch support contracts, and deployment environment are not present in this project, so the local suite does not claim to execute its pool seed/swap integration. The factory's defensive `SupplyTransferFailed` branch is unreachable through the actual token's successful transfer; these tests do not replace token code or mock a false return to manufacture coverage.
