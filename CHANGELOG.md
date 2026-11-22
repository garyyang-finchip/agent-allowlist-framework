# Changelog

## 0.2.1 (2026-11-23)

Sepolia evidence.

- Revision 0.2.0 deployed on Sepolia on 2026-11-22 and the three worked cases executed end to end: 87 transactions in blocks 12190415 to 12190525, every step with the result the specification gives, final state read back and checked. `AAFRegistry` at 0xBCD17Ac576A675a29F78176209289B72c1b122C7, `AAFGuard` at 0x1e977Eae5dc102bDc72c6E6aE14654257ec787b7.
- `deployments/sepolia/evidence.json` as written by the run; `docs/sepolia-evidence.md` with addresses, accounts, phases, results, cost and how to read the state back; README deployments table; the discussion post carries the deployment.
- Measured cost under Sepolia's state-creation pricing: about 107,400,000 gas for the run, of which about 92,100,000 for the deployer's eleven deployments and adoptions; the runbook's estimate is replaced by the measured figures.

## 0.2.0 (2026-11-23)

Number and names.

- The proposal is ERC-8507. Specification at `ERCS/erc-8507.md`, assets under `assets/erc-8507/`; the placeholder files are removed.
- The title is Agent Allowlist Framework, as an editor suggested, and the rest of the naming follows it. The short name is AAF. Interfaces and contracts are `IAAFRegistry`, `IAAFGuard`, `IAAFEvaluator`, `IAAFRelationSource`, `IAAFSubjectResolver`, `AAFRegistry`, `AAFGuard`, `AAFTypes.sol`, `AAFCredentialHistoryEvaluator`, `AAFBoundAnchorRelation`, `AAFExampleConsumer`. Identifier tags are `AAF.Scope.v1` and so on; subject kinds, actions, relations and dimensions are `aaf.*`; documents carry `"aaf": "1"`; schema files are `aaf-*.schema.json`; the tool is `tools/aaf.mjs`. The names of revision 0.1 had AWF and `awf` in these places.
- Every identifier that hashes a tag or a name changed, and so did every vector and every example document. Function selectors and interface identifiers do not depend on these names.
- The repository is renamed from `agent-whitelist-framework` to `agent-allowlist-framework`. The plan of the Sepolia run records the documents under the new name.
- The text uses allowlist and denylist and names the older words once.
- `ercs-pr-package/` is no longer kept in the repository. `scripts/make-filing-package.py` writes it on demand.

Changes after review on the discussion topic. They change the interface identifiers of `IAAFRegistry` and `IAAFGuard`.

- Reuse is declared per action: `ActionRule.once` is replaced by `ActionRule.reuse` with `NONE` (the zero value), `WHILE_CURRENT` and `ADMISSION`. An assessment carries a validity only for an action declared `WHILE_CURRENT`.
- A result that rests on something that can change without the state of its list changing holds for its call only. `AAFCredentialHistoryEvaluator` returns a validity of zero instead of the expiry of the credential. Criteria documents state how long a result holds (`evaluation.resultValidity`).
- An entry about an account can be tied to the code of the account (`EntryInput.codeHash`, `Entry.codeHash`, reason `CODE_CHANGED`, error `CodePinNotSupported`). `EntryAdded` carries the code hash.
- `PROCEED_RESTRICTED` is declared only with a binding document that states the limit (`rules.restriction`); a guard refuses the declaration without one. The example consumer applies a limit.
- Relying on an earlier assessment requires the same controller.
- Specification: Sections 6.4, 6.6, 6.8, 6.9, 6.10, 8.2, 8.4, 8.7, 8.8 and 8.9 revised; fourteen invariants; test cases for reuse, entries tied to code and proceeding within a limit; Case A has twelve steps, with a revocation before expiry.
- 145 Foundry tests. The evidence run has 87 transactions on a local node and includes the revocation.
- Reply to the reviews in `docs/magicians-replies.md`.

## 0.1.2 (2026-11-20)

- The specification is filed as pull request 2192 against the ERCs repository. The README and the post draft carry its link.

## 0.1.1 (2026-11-20)

- The discussion topic is open on Ethereum Magicians (topic 30456). `discussions-to` of the specification, the filing package, the README and the post draft carry its link.

## 0.1.0 (2026-11-20)

First package.

- Specification draft `ERCS/erc-9999.md` with placeholder number: four objects of a list (Scope, List, Criteria, Entry), typed subjects, four membership modes (enumerated, committed, predicate, derived), bindings adopted by consumers, standing, three-valued match results, four outcomes and separate dispositions, three separately versioned things (rules, list state, binding), twelve invariants.
- Reference implementation: `AWFRegistry` and `AWFGuard`, with all four modes, committed sets with membership and non-membership proofs, pinned modules, related-object extension, admissions for work in progress.
- Two example modules (`AWFCredentialHistoryEvaluator`, `AWFBoundAnchorRelation`) and an example consumer.
- 134 Foundry tests: registry, committed sets, predicate lists, derived lists, guard, three worked cases, vectors.
- JSON Schemas of the six document kinds, the vocabulary of dimensions, nineteen example documents, vectors from an independent implementation (`tools/awf.mjs`).
- Evidence run for a live network (`script/AWFEvidence.s.sol`, `scripts/evidence-run.sh`), rehearsed on a local node (83 transactions), and the plan for Sepolia.
- Filing package builder with consistency checks (`scripts/make-filing-package.py`), filing and Sepolia runbooks, discussion post draft, decision log.
