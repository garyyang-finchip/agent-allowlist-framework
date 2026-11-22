# Sepolia evidence run: how it is made

The run deploys the reference implementation and executes the three worked cases of the specification on Sepolia. It ends by reading the final state back, checking it against the specification, and writing `deployments/sepolia/evidence.json`.

The same run was rehearsed on a local node: 87 transactions, every step with the result the specification gives.

## What the run does

Eighty-seven transactions in seven phases and one wait:

| Phase | What happens | Sent by |
| --- | --- | --- |
| `deploy` | Registry, guard, the two example modules, three example consumers (task board, swarm membership, inference gateway) and the stand-ins the cases read from are deployed; seven accounts of the run receive gas money | deployer |
| `caseA1` | Case A: scope, criteria, predicate list, binding; two agent identities with credentials and delivery histories; one bid admitted and four refused (lower credential, no history presented, a caller who is not the owner, a new owner of the identity) | deployer, manager, issuer, alice, bob, carol, mallory |
| `caseB1` | Case B: deny list with a notice period of 120 seconds, the list derived from it, binding; an agent identity bound to its operator's account; the identity joins, is entered with an evidenced basis, joins again during the notice period, objects | deployer, manager, operator |
| `caseA2` | Case A: a credential that lasts 240 seconds is issued and used: the bid is admitted | issuer, bob |
| wait | 300 seconds, so that the notice period and the credential lifetime pass | |
| `caseA3` | Case A: the same bid after the expiry is refused; a credential that lasts thirty days is issued and a bid under it admitted; the issuer revokes it, no list and no state digest changes, and the next bid is refused | bob, issuer |
| `caseB2` | Case B: the identity is refused; the operator's account is admitted; the binding is amended to name the derived list and the account is refused; a named successor is admitted; an account that takes the identity over and binds to it is refused; the entry is revoked and that account is admitted | operator, deployer, carol, bob, manager |
| `caseC` | Case C: allow list, deny list, committed deny set, list of excluded tools, two bindings; a call admitted; calls deferred or refused for an undetermined side, a conflict, no match and a borrowed identity; a tool version refused and one run; removal from the allow list; a new commitment | deployer, manager, alice, bob, carol, mallory |
| `report` | Reads the state, checks it, writes `evidence.json` | read only |

Before each gated action is sent, the script computes its result and stops if it is not the one the specification gives.

## Accounts

Every account of the run is derived from the deployer key, so only one account is funded by hand.

| Role | Address |
| --- | --- |
| deployer (also the adopter of the three consumers) | `0xcdd5b0439B3bcEEb8DF51cCC5567d0e4D3dab060` |
| manager (of every list) | `0xFe3B4CFB718CF8dd49c684303c9414f991f06F39` |
| issuer (of the credentials of Case A) | `0x6FfD3452EAB3F378a53f2A5d6d7Ba9230bB057A6` |
| alice | `0x41ACFDef3A4F0b86e926555eE5A373a45ac4AFB7` |
| bob | `0x26319cC8a702970cE6480A1205aa067857E81aaD` |
| carol | `0x2c749e6697fD46B5C36c0B718f4Fd09949004841` |
| operator (of the agent identity of Case B) | `0x2F8E68a62b7cF5627f85EA5B51bf9c570a3d47D5` |
| mallory (calls in the name of others) | `0x64822E21aE9787AD632F908e080dB3Dff407531B` |

The deployer key is not in this repository. It is a throwaway key for this test network only.

A run that is started again deploys fresh contracts at other addresses.

## Cost

Sepolia prices state creation at 1,530 gas per byte (EIP-8037). The local rehearsal used 21,658,108 gas under the earlier rules. Under Sepolia's pricing the run is estimated at about 129,000,000 gas: about 83,000,000 for the eleven deployments, of which registry and guard are about 22,000,000 each, and the rest for the transactions of the cases. This is an estimate from the sizes of the contracts and the number of storage slots written; the driver takes every gas limit from the node.

The driver sends every transaction with a fixed tip (0.2 gwei unless `TIP_WEI` says otherwise) and a fee cap of twice the base fee plus the tip. Before sending anything it checks that the deployer holds 168,500,000 gas at that cap: 125,000,000 for its own transactions and 43,500,000 that it passes on to the seven accounts. With a base fee near zero that is about 0.034 ETH. **0.05 Sepolia ETH on the deployer is enough while the base fee is below 0.045 gwei.** If it is higher the driver prints the budget and sends nothing.

## Validity of the plan

`deployments/sepolia/plan.json` fixes the accounts, the document hashes and the committed set of the run. It does not expire. A new plan is needed only for another deployer key (`node tools/aaf.mjs plan sepolia` with `DEPLOYER_PK` set, then commit the regenerated `deployments/sepolia`).

The documents of the run are served from this repository under `deployments/sepolia/documents/`, in the canonical form whose hash is anchored. They have to be on the `main` branch before the run, because their locations are recorded on chain. The plan assumes the repository is `github.com/garyyang-finchip/agent-allowlist-framework`. Under another name, change the one line `recordBase` in `deployments/sepolia/plan.json` before the run; no hash depends on it.

## Steps

Requires Foundry (forge and cast, 1.7.1 or later) and git. Node is not needed for the run. The driver builds the contracts and the script without the test files, which takes about 460 MB of memory and half a minute.

```sh
git clone https://github.com/garyyang-finchip/agent-allowlist-framework.git
cd agent-allowlist-framework
forge --version
bash scripts/setup.sh
```

Create the environment file outside the repository. It holds two lines, the deployer key and the RPC endpoint:

```sh
printf 'export DEPLOYER_PK=%s\nexport SEPOLIA_RPC_URL=%s\n' '<deployer key>' '<Sepolia JSON-RPC endpoint>' > ~/aaf.env
chmod 600 ~/aaf.env
```

Run:

```sh
source ~/aaf.env
bash scripts/evidence-run.sh sepolia
```

The run takes about twenty-five minutes. It prints the phases as they go and, at the end, the content of `deployments/sepolia/evidence.json` between two marker lines. That block is the result to keep.

To rehearse on a local node first, start `anvil` in another terminal and run the driver with the first default key of the local node, for which `deployments/anvil/plan.json` was made:

```sh
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 RPC_URL=http://127.0.0.1:8545 bash scripts/evidence-run.sh anvil
```

## If something goes wrong

| What the driver prints | What to do |
| --- | --- |
| `the deployer balance is below the budget of this run; nothing was sent` | Nothing happened. Send more Sepolia ETH to the deployer, up to the printed budget, and run again |
| `the base fee ... is far above normal` | Nothing happened. Try again later |
| The build stops with `Killed` | The machine ran out of memory. Stop other services or add swap, then run again; nothing was sent |
| A phase stops with a timeout | A transaction was not included in ten minutes. Run again with a higher tip, for example `TIP_WEI=1000000000 bash scripts/evidence-run.sh sepolia`; the budget rises in proportion |
| `unexpected result for ...` | A step computed another result than the specification gives. Nothing of that step was sent. Keep the output |
| A phase stops with another error | Keep the output. Running the same command again starts over with fresh contracts, provided the deployer still holds the budget |
| `plan is for another deployer key` | `DEPLOYER_PK` is not the key the plan was made for |

## After the run

1. Keep the printed evidence block and commit it as `deployments/sepolia/evidence.json`.
2. The README deployments table and the discussion topic are updated with the addresses.
3. Optional: verify the contracts on a block explorer. The compiler settings are in `foundry.toml` (solc 0.8.28, optimizer 200 runs, `via_ir`, EVM version cancun, no metadata hash).
