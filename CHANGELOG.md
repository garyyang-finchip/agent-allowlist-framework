# Changelog

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
