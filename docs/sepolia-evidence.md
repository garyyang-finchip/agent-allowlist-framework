# Sepolia evidence run of 2026-11-22

The reference implementation of revision 0.2.0 was deployed on Sepolia and the three worked cases of the specification were executed against it, with the driver and the plan in this repository (`scripts/evidence-run.sh sepolia`, `deployments/sepolia/plan.json`). The run ended with the read-back of the final state, which passed every check the driver makes, and wrote [deployments/sepolia/evidence.json](../deployments/sepolia/evidence.json).

| | |
| --- | --- |
| Chain | Sepolia, chain id 11155111 |
| Blocks | 12190415 to 12190525 (2026-11-22, 18:16:48 to 18:39:24 UTC) |
| Transactions | 87, every one successful; none was retried and nothing was redeployed |
| Deployer and adopter of the three consumers | `0xcdd5b0439B3bcEEb8DF51cCC5567d0e4D3dab060` |
| Source | This repository at revision 0.2.0, solc 0.8.28, optimizer 200 runs, `via_ir`, EVM version cancun, no metadata hash |
| Documents | Anchored by hash; served from [deployments/sepolia/documents](../deployments/sepolia/documents) |

Every step of a gated action was computed by the driver before it was sent and compared with the result the specification gives; a step that computed another result would have stopped the run. The read-back at block 12190525 then checked the counters of the three consumers, the state of the Case B entry, the version of the amended binding, the derived results after the revocation, and the earlier assessment and proof of Case C against the current state.

## Contracts

| Contract | Address |
| --- | --- |
| `AAFRegistry` | [0xBCD17Ac576A675a29F78176209289B72c1b122C7](https://eth-sepolia.blockscout.com/address/0xBCD17Ac576A675a29F78176209289B72c1b122C7) |
| `AAFGuard` | [0x1e977Eae5dc102bDc72c6E6aE14654257ec787b7](https://eth-sepolia.blockscout.com/address/0x1e977Eae5dc102bDc72c6E6aE14654257ec787b7) |
| `AAFCredentialHistoryEvaluator` (Case A) | [0x33712D575b991Ded45131807d8d6b05839217877](https://eth-sepolia.blockscout.com/address/0x33712D575b991Ded45131807d8d6b05839217877) |
| `AAFBoundAnchorRelation` (Case B) | [0x65B8755d22bDcDC6A96EaE5FE46B433E208949D9](https://eth-sepolia.blockscout.com/address/0x65B8755d22bDcDC6A96EaE5FE46B433E208949D9) |
| `AAFExampleConsumer` "Task board" (Case A) | [0xD0ded5d9E11dE80eb5607447f090fB87d6B03713](https://eth-sepolia.blockscout.com/address/0xD0ded5d9E11dE80eb5607447f090fB87d6B03713) |
| `AAFExampleConsumer` "Swarm alpha membership" (Case B) | [0xC44740Dbf5E0D26197Fc618a523DA12D08B81351](https://eth-sepolia.blockscout.com/address/0xC44740Dbf5E0D26197Fc618a523DA12D08B81351) |
| `AAFExampleConsumer` "Inference gateway" (Case C) | [0xD7161E5111320BE656333BE62fF7B008D20cdF51](https://eth-sepolia.blockscout.com/address/0xD7161E5111320BE656333BE62fF7B008D20cdF51) |
| Identity registry stand-in (`IdentityFixture`) | [0xc3aEe339676bbFe4320198E532dCBDE14F120c8C](https://eth-sepolia.blockscout.com/address/0xc3aEe339676bbFe4320198E532dCBDE14F120c8C) |
| Assertion registry stand-in (`AssertionFixture`) | [0x78e3B2D86c8560440Db5E25384373B875a6247Be](https://eth-sepolia.blockscout.com/address/0x78e3B2D86c8560440Db5E25384373B875a6247Be) |
| Task ledger stand-in (`TaskLedgerFixture`) | [0xCFA832d161Ba58695673AF7A17C24ddafbFDB74f](https://eth-sepolia.blockscout.com/address/0xCFA832d161Ba58695673AF7A17C24ddafbFDB74f) |
| Address-anchored identity registry (`AIDRegistry`, vendored) | [0x7D9dC571C3B9Ab12B58b7Fc1556a3142E5073Ae7](https://eth-sepolia.blockscout.com/address/0x7D9dC571C3B9Ab12B58b7Fc1556a3142E5073Ae7) |

The three stand-ins are the test fixtures of this repository: an identity registry of the ERC-721 shape, an assertion registry with the view the example evaluator reads, and a task ledger with the view it reads. The address-anchored identity registry is the unmodified reference registry listed in [test/vendor/README.md](../test/vendor/README.md). Registry and guard have no owner and no upgrade path; nothing about this deployment can be changed by anybody.

## Accounts

| Role | Address | Transactions |
| --- | --- | --- |
| deployer, adopter | `0xcdd5b0439B3bcEEb8DF51cCC5567d0e4D3dab060` | 28 |
| manager of every list | `0xFe3B4CFB718CF8dd49c684303c9414f991f06F39` | 16 |
| issuer of the credentials | `0x6FfD3452EAB3F378a53f2A5d6d7Ba9230bB057A6` | 5 |
| alice | `0x41ACFDef3A4F0b86e926555eE5A373a45ac4AFB7` | 11 |
| bob | `0x26319cC8a702970cE6480A1205aa067857E81aaD` | 12 |
| carol | `0x2c749e6697fD46B5C36c0B718f4Fd09949004841` | 3 |
| operator of the agent identity of Case B | `0x2F8E68a62b7cF5627f85EA5B51bf9c570a3d47D5` | 10 |
| mallory, who calls in the name of others | `0x64822E21aE9787AD632F908e080dB3Dff407531B` | 2 |

All eight keys were derived for this run and are not used for anything else.

## Phases

| Phase | Blocks | What happened |
| --- | --- | --- |
| `deploy` | 12190415 to 12190432 | Eleven contracts deployed, seven accounts funded |
| `caseA1` | 12190433 to 12190450 | Scope, criteria, predicate list and binding of Case A; two identities registered, credentialed and given delivery histories; steps 1 to 5 of Case A |
| `caseB1` | 12190451 to 12190461 | Scope, criteria of the extension, deny list with a notice period of 120 seconds, derived list and binding of Case B; the identity joins (step 1), is entered with an evidenced basis at 18:26:00 UTC with effect from 18:28:00 UTC (step 2), joins during the notice period (step 3), and the operator records an objection (step 4) |
| `caseA2` | 12190462 to 12190463 | A credential that lasts 240 seconds is issued and used (step 6) |
| wait | | 300 seconds |
| `caseA3` | 12190488 to 12190492 | The bid after the expiry is refused (step 7); a credential that lasts thirty days is issued and used (step 8); the issuer revokes it and the next bid is refused (step 9) |
| `caseB2` | 12190493 to 12190503 | Steps 5 to 10 of Case B: refused after the notice period; the bound account admitted; the binding amended to version 2 and the account refused; a named successor admitted; a new anchor refused; the entry revoked and the new anchor admitted |
| `caseC` | 12190504 to 12190525 | Scope, four lists, committed set and two bindings of Case C; steps 1 to 10, ending with the removal of the partner and a new commitment |
| `report` | read at 12190525 | Final state read back and checked |

Steps 10 to 12 of Case A in the specification need no transaction (an unreadable source, malformed evidence, a request outside the scope) and are covered by the tests, not by the run.

## Results

From `evidence.json`, as read at block 12190525:

| Case | Result |
| --- | --- |
| A | 3 bids recorded, 6 refused. The binding's state digest is the same before and after the revocation of step 9, and the bid after the revocation was refused because the credential is read at every use |
| B | 5 joins admitted, 3 refused. The entry has basis `EVIDENCED`, `listedAt` 1795371960 and `validFrom` 1795372080, 120 seconds later; it is revoked. The binding is at version 2. The derived list answers `NO_MATCH` with reason `NOT_RELATED` both for the new anchor after the revocation and for the account that was only named as a successor |
| C | 1 call served, 5 not served; 1 tool use refused, 1 carried out. The assessment of step 1 is not current: its state digest `0x532651ed...` differs from the current digest `0x91e32cf4...`. The proof of absence of step 1 yields `UNDETERMINED` with reason `PROOF_INVALID` against the new root `0xe2e51f42...`, and membership in the new set can be shown |

Identifiers of the lists, bindings and criteria are in the evidence file. They differ from those of the example documents because the chain, the registry and the manager differ; the documents and their hashes are the same.

## Cost

The base fee stayed near 16 wei and the driver paid a tip of 0.2 gwei, so every transaction cost about 0.2 gwei per gas. Spending by account, computed from the balances before and after the run:

| Account | Gas used, about |
| --- | --- |
| deployer (eleven deployments, adoptions, scopes, criteria) | 92,100,000 |
| manager | 5,430,000 |
| alice | 2,580,000 |
| bob | 3,290,000 |
| operator | 2,100,000 |
| issuer | 770,000 |
| carol | 710,000 |
| mallory | 380,000 |
| All | about 107,400,000 |

The same 87 transactions use 21,658,108 gas on a local node with the earlier gas rules; Sepolia prices state creation at 1,530 gas per byte (EIP-8037), which multiplies the cost of deployments by about six and of the other transactions by two to three. The run burnt about 0.0215 ETH. The deployer kept 0.0229 ETH of the 0.05 ETH it was funded with, and about 0.0056 ETH stays in the seven accounts.

## Reading the state back

Anyone can repeat the read-back with `cast` against a Sepolia endpoint. The identifiers are those in `evidence.json`.

```sh
REGISTRY=0xBCD17Ac576A675a29F78176209289B72c1b122C7
GUARD=0x1e977Eae5dc102bDc72c6E6aE14654257ec787b7
BOARD=0xD0ded5d9E11dE80eb5607447f090fB87d6B03713
BINDING_C=0x4b3ba53c41e22450caa15483d4a7c921a07d5a3ef5150395f65b77cae4acfe58
EARLIER_DIGEST=0x532651edc9ea13a0286ee0b7eaf93ecbfaa6d07e81828ae89e7816d4a9c2cb03

# the state digest of the Case C binding now, and whether the assessment of step 1 is still current
cast call $GUARD "stateDigestOf(bytes32)(bytes32)" $BINDING_C --rpc-url $SEPOLIA_RPC_URL
cast call $GUARD "isCurrent(bytes32,bytes32,uint64)(bool)" $BINDING_C $EARLIER_DIGEST 18446744073709551615 --rpc-url $SEPOLIA_RPC_URL

# the Case B entry: status 3 is REVOKED, basis 1 is EVIDENCED
LIST_B=0xb50a3635d68cbe67ed052444db3a57b5f90e191f721180d70d12b02696eccd25
IDENTITIES=0xc3aEe339676bbFe4320198E532dCBDE14F120c8C
KEY=$(cast call $REGISTRY "subjectKeyOf((bytes32,uint256,address,bytes32))(bytes32)" \
  "($(cast keccak aaf.subject.entry),11155111,$IDENTITIES,$(cast to-bytes32 3))" --rpc-url $SEPOLIA_RPC_URL)
cast call $REGISTRY "entryOf(bytes32,bytes32)((uint8,uint8,uint32,uint64,uint64,uint64,uint64,address,bytes32,bytes32,bytes32))" $LIST_B $KEY --rpc-url $SEPOLIA_RPC_URL

# the revision and state hash of a list
cast call $REGISTRY "stateOf(bytes32)(uint64,bytes32)" $LIST_B --rpc-url $SEPOLIA_RPC_URL
```

Results of the lists for the subjects of the run can be asked with `check(bytes32,(bytes32,uint256,address,bytes32))` on the registry and `assess(...)` on the guard; both are views and cost nothing. Note that the results of Case A depend on the credentials, which have expired or been revoked, and those of Case C on the partner entry, which is revoked: what the chain answers now is the state after the run, which is what the report checked.
