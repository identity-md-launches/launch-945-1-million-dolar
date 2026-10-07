# Vendored dependencies

These files are included directly so verification needs no package registry, network,
Git metadata, or submodule initialization. No upstream package scripts are executed.

| Dependency | Version | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors, and LICENSE | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Complete `src/` tree and both license files | MIT OR Apache-2.0 |

Sources were copied without changes from these release archives:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`

`remappings.txt` resolves imports to the copies in `lib/`. OpenZeppelin is used by the
production token; forge-std is used only by tests. `dependencies.sha256` records every
vendored file and can be checked with `sha256sum -c dependencies.sha256`.
