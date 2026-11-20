# Vendored files

Unmodified copies, used by the tests and by the evidence run only. None of them is part of the specification or of the filing package.

| Path | Source | Commit |
| --- | --- | --- |
| `aid/AIDRegistry.sol`, `aid/interfaces/` | `garyyang-finchip/aid-standard`, `assets/erc-aid/contracts/` | `7f3559a` |
| `kya/IKYARegistry.sol`, `kya/IKYATypes.sol` | `garyyang-finchip/kya-standard`, `assets/erc-kya/contracts/interfaces/` | `062b625` |
| `task/ITaskTender.sol` | `garyyang-finchip/task-token-standard`, `contracts/interfaces/` | `a2c2ea0` |

The address-anchored identity registry is deployed in the tests so that the related-object extension runs against the real binding rules. The two interface files are compiled only to show that the narrow views the example evaluator reads have the same selectors as the full interfaces.
