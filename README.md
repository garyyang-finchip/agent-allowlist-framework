# Agent Allowlist Framework (AAF)

Scoped allow and deny lists for agents and other objects: who admits or refuses what, for which activity, on which grounds, with what result.

AAF defines allowlists and denylists (whitelists and blacklists) together. Both are lists of one kind that differ only in polarity, `ALLOW` or `DENY`. A list has typed members (accounts, registered agent identities, groups, runtime instances, artefacts such as a model or tool version, named services). A list has no effect on anybody until a consumer binds it for its own actions.

AAF fixes how admission and refusal are expressed, checked and given effect. It does not fix whom to admit, which evidence to require, or what makes an agent good or bad.

The proposal was first discussed as Agent Whitelist Framework (AWF). Revision 0.2.0 renamed it throughout: the title, the short name, the interfaces and contracts (`IAWF...` to `IAAF...`), the identifier tags and names (`AWF.` and `awf.` to `AAF.` and `aaf.`), the schema files and this repository, which was `agent-whitelist-framework`.

| | |
| --- | --- |
| Status | Draft, version 0.2.0 |
| Specification | [ERCS/erc-8507.md](ERCS/erc-8507.md), ERC-8507 |
| Pull request | [ethereum/ERCs#2192](https://github.com/ethereum/ERCs/pull/2192) |
| Discussion | [Ethereum Magicians, topic 30456](https://ethereum-magicians.org/t/erc-8507-agent-allowlist-framework-aaf/30456) |
| Requires | ERC-165 |
| Author | Gary Yang ([@garyyang-finchip](https://github.com/garyyang-finchip)) |
| License | CC0-1.0 |

## What it defines

- **Four objects of a list.** Scope (where a rule is meant to apply), List (members with a polarity and a manager), Criteria (one immutable version of the rules, with the code and configuration of the module that computes them pinned) and Entry (one subject in an enumerated list, with its basis, validity window and status). An entry about an account can be tied to the code the account runs.
- **Typed subjects.** A reference carries its kind, chain, namespace and identifier. Six kinds are defined; further kinds need no registration.
- **Four ways to have members.** Written by the manager, shown by proofs against a committed set (with proofs of absence for sorted sets), computed from criteria by an evaluator, or derived from another list, either as a plain reference or by extension to objects related to a listed one.
- **Binding.** A consumer, or the adopter it named, declares which lists it uses on the `ALLOW` and on the `DENY` side, for which actions, what happens on a conflict, on no match and on the undetermined, and whether a decision on an action may be used again. Nothing is assumed in favour of a request, and no decision is reusable unless the binding says so.
- **One standard result.** A list answers `MATCH`, `NO_MATCH` or `UNDETERMINED`. A binding answers `ALLOW`, `DENY`, `NOT_APPLICABLE` or `INDETERMINATE`. The adopter's disposition (`PROCEED`, `REFUSE`, `DEFER`, `PROCEED_RESTRICTED`) is kept apart from both. Proceeding within a limit is declared only together with the document that states the limit, by a consumer that applies it.
- **Standing.** `ALLOW` is never returned for an actor unless the caller was verified as entitled to act for the subject.
- **Three versions and a validity.** Rules, list state and binding are versioned separately, and an assessment names all three, so that an earlier result can be recognised as no longer current. A result that rests on something that can change without any list changing, such as a credential that can be revoked, holds for its call only.
- **Dimensions of evidence.** An open vocabulary (identity, credential, principal, runtime, inference, performance, relation, activity, safety, dispute, reputation, liveness, other lists, designation) and one form every piece of evidence is stated in. No list has to use any of them.

Out of scope: scores and rankings, identity and assertion systems, proof systems, the terms of an operation such as its amount or target, what a refusal means for work already done or for payment, verification of other chains.

## Repository layout

| Path | Content |
| --- | --- |
| `ERCS/erc-8507.md` | The specification |
| `assets/erc-8507/contracts/interfaces/` | Types and the interfaces `IAAFRegistry`, `IAAFGuard`, `IAAFEvaluator`, `IAAFRelationSource`, `IAAFSubjectResolver` |
| `assets/erc-8507/contracts/` | Reference implementation: `AAFRegistry`, `AAFGuard` |
| `assets/erc-8507/contracts/adapters/` | Two example modules: an evaluator (credential and delivery history) and a relation source (account bound to an agent identity) |
| `assets/erc-8507/contracts/examples/` | An example consumer |
| `assets/erc-8507/schemas/` | JSON Schemas of the documents and the vocabulary of dimensions |
| `assets/erc-8507/examples/` | Documents of the three worked cases |
| `assets/erc-8507/vectors/` | Constants, identifiers, set proofs, outcome tables, interface identifiers |
| `test/` | Foundry tests, including the worked cases and the vectors; stand-ins and vendored files they need |
| `script/`, `scripts/` | The on-chain evidence run and its driver, library setup, filing package builder |
| `tools/` | Documents, identifiers, schema checks and vector generation (Node) |
| `deployments/` | Plans of evidence runs, with their documents |
| `docs/` | Decision log, filing and Sepolia runbooks, text of the discussion topic and of the replies to its reviews |

## What the reference implementation covers

| Part of the specification | Implemented | Reported through ERC-165 |
| --- | --- | --- |
| Registry: scopes, criteria, enumerated lists and entries, notice, objection, management | yes | yes |
| Committed sets with membership and non-membership proofs | yes | yes |
| Predicate lists with pinned evaluators | yes | yes |
| Derived lists: reference, pin, related-object extension | yes | yes |
| Guard: bindings, standing, assessment, reuse per action, admissions, state digest | yes | yes |
| Entries tied to the code of an account | yes | yes |
| Zero-knowledge set proofs | no | no |
| Signed assessment receipts | no | no |
| Standing and evidence for objects on other chains | no, such results are undetermined | no |

Registry and guard have no owner, no upgrade path and no privileged account. Limits: chains of derived lists up to 4, fan-out of a relation up to 8, 1,500,000 gas per module call, 8 lists on one side of a binding, 16 actions per binding.

The two example modules read an assertion registry, a task ledger and an address-anchored identity registry through narrow views. The tests run the relation source against the reference registry of address-anchored agent identities (vendored, unmodified) and check that the views of the evaluator have the selectors of the full interfaces of the assertion registry and the task tender kernel. See [test/vendor/README.md](test/vendor/README.md).

## Build and test

Requires [Foundry](https://github.com/foundry-rs/foundry) (tested with 1.7.1), Node 20 or later and Python 3.

```sh
bash scripts/setup.sh          # fetches forge-std into lib/
forge test                     # 145 tests: unit, worked cases, fuzz, vectors
cd tools && npm install && node aaf.mjs check && cd ..
python3 scripts/make-filing-package.py --check
```

`node tools/aaf.mjs check` validates every example document against its schema, recomputes every identifier and confirms that examples and vectors are what the rules produce. The tool is written from the specification and uses none of the Solidity code; the Solidity tests replay its vectors, so identifiers, set proofs and outcome rules are implemented twice.

`python3 scripts/make-filing-package.py --check` verifies that the specification quotes the interfaces exactly, that every value it quotes is in the vectors, that the tables it works out follow from the rules, and that every asset is linked. Without `--check` it also writes `ercs-pr-package/`, the files that go to the ERCs repository; that directory is generated and not kept here.

## The three worked cases

**Case A, who may bid for a task is decided by criteria.** A task board binds one `ALLOW` list whose members are computed: a credential of level 2 bound to the controller of the agent identity, and two accepted deliveries by that controller within ninety days. A qualified agent bids. An agent with a lower credential, a bid without history, a bid by somebody else in the name of the qualified identity, a bid by a new owner of the identity, a bid after the credential expired and a bid after the issuer revoked a credential that had twenty-nine days left are refused, each for its own reason and none by being put on a deny list. Every bid is decided on its own, because no list changes when a credential is revoked. An unreadable source defers the bid instead of refusing it.

**Case B, a group refuses listed agents, with notice.** A group binds a `DENY` list with a notice period. An entry that states a fact commits to its evidence, is on record during the notice period without effect, can be objected to, and then takes effect. The account bound to the refused identity is another object: it is refused only after the group adopts, in its binding, a second list derived by that relation. Naming an uninvolved account as successor relates nobody; taking the identity over and binding to it does. When the entry is revoked the derived refusal ends with it.

**Case C, a service combines an allow list with two deny lists.** One of the deny lists is a committed set, for which the caller proves absence. The case covers a conflict, no match, an undetermined side, a borrowed identity, an earlier result that may be relied on while it is current and no longer after a revocation, and an earlier proof after a new commitment. A second binding of the same service refuses an excluded tool version without concluding anything about the agent that asked.

All three are tests (`test/AAFCases.t.sol`) and all three are what the evidence run executes on a live network.

## Gas

Measured on a local node with the gas rules in force before state creation was repriced (EIP-8037, which Sepolia has used since October 2026). Under that pricing deployments cost several times more; the evidence run takes its limits from the node.

| Operation | Gas |
| --- | --- |
| Deploy `AAFRegistry` | 3,161,649 |
| Deploy `AAFGuard` | 3,116,149 |
| Declare a scope | 94,304 to 94,676 |
| Register criteria with a module | 173,177 to 188,759 |
| Create a list | 107,632 to 169,856 |
| Add an entry | 120,360 to 142,311 |
| Revoke an entry | 50,078 to 52,962 |
| Commit a set | 51,282 to 85,494 |
| Adopt a binding (one to three lists) | 388,558 to 587,895 |
| Amend a binding | 191,670 |
| A gated action through the example consumer, one enumerated list | 117,083 to 133,944 |
| A gated action, evaluator with credential and two deliveries | 189,170 |
| A gated action, three lists with a proof of absence | 209,585 |
| A gated action, derived list with a relation | 208,829 |
| All three worked cases, 87 transactions | 21,658,108 |

Assessments are views; `assess` costs nothing when called off chain. The figures for gated actions include the consumer's own bookkeeping and the `Assessed` event.

## Deployments

None yet. The plan of the Sepolia run, with its accounts and documents, is in [deployments/sepolia](deployments/sepolia); how the run is made is in [docs/sepolia-runbook.md](docs/sepolia-runbook.md).

## Documents

- [docs/decision-log.md](docs/decision-log.md): the design decisions behind the specification, including those of revision 0.2.0
- [docs/filing-runbook.md](docs/filing-runbook.md): how the specification is filed with the ERCs repository
- [docs/sepolia-runbook.md](docs/sepolia-runbook.md): how the on-chain evidence run is made
- [docs/magicians-post.md](docs/magicians-post.md): text of the discussion topic
- [docs/magicians-replies.md](docs/magicians-replies.md): replies to the reviews on the discussion topic
- [CHANGELOG.md](CHANGELOG.md)

## Acknowledgements

Revision 0.2.0 follows review on the discussion topic. Secrypta raised the reuse of a decision across operations, the code behind an account's address and the conditions under which proceeding within a limit is meaningful. Revinand raised the validity of results that rest on a revocable credential.

## License

[CC0-1.0](LICENSE).
