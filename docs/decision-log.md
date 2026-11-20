# Decision log

The decisions behind version 0.1.0, in the order they were taken. Each entry gives the decision and what it means in the specification and the code.

## Name

The proposal is the **Agent Whitelist Framework (AWF)**. It defines whitelists and blacklists together from the abstract onward. The text uses `ALLOW` and `DENY` for the two polarities.

## D1. What is being defined

A scoped relation of admission and refusal: who adopts, in what scope, for which object and which action, under which version of which rules and evidence, with what result. The standards are chosen by the parties; the framework fixes how the relation is expressed, checked and given effect. Of the four questions asked about an agent (who is it, what is known about it, do I admit it for this, what can it then do) the framework covers the third and feeds the fourth.

## D2. One object with a polarity

Whitelists and blacklists share structure, interface and lifecycle. Polarity is fixed at creation and is part of the list identifier, so that no entry or proof can come to mean its opposite. Not matching one polarity never creates membership in the other.

## D3. Membership modes

Enumerated lists are the required minimum. Committed, predicate and derived lists are optional parts of the specification; the reference implementation has all four and runs a predicate case end to end. A registry that lacks a mode refuses to create lists of it. Mixed rules are expressed by combining lists in a binding, not by a hybrid mode.

## D4. Algorithms are pluggable, meanings are not

The core has no scoring or policy engine. What is uniform: the input of an evaluator (list, rule, subject, request, evidence), its output (three-valued result, reason, validity, basis), what failure means (undetermined, with a reason), and that its code hash and configuration hash are pinned by the criteria. `check` stays as the simple query; `matchOf` takes the request and the evidence. Three things are kept apart everywhere: the match result of a list, the outcome of a binding, and the lifecycle status of an entry.

## D5. No default precedence

A binding declares its conflict rule, its default for no match, and its dispositions for the indeterminate and the not applicable. Nothing is assumed in favour of a request: the zero value of each declaration is the indeterminate or the refusing one, and a binding without a rule for no match is refused. Composition is fixed as two sides with thresholds (any, all, or k of n) joined by the conflict rule; "A except B" is the conflict rule read in one direction. Unknown inputs propagate by one rule: the outcome is determined only if every resolution of the unknown gives the same outcome.

## D6. Related-object extension

Named neutrally and kept optional. An extension is a derived list of its own: the source list is never extended, and a consumer is reached only if its binding names the derived list. The criteria state the relation type, its direction, the evidence, the time (the relation has to hold when asked) and the fan-out; one relation hop is the limit. Derived results are computed when asked, never stored, and carry their origin.

The reference relation is "the account bound as the anchor of an agent identity". It holds only on acts of both sides: the account bound itself, and the identity names the account as owner or wallet. A retiring anchor that names a successor relates nobody; this is a test and a step of the evidence run. Succession declared by one side is deliberately not offered as a relation.

## D7. Committed sets

Merkle commitments with membership proofs are in. Proofs of absence are specified for sorted sets with two sentinels and need no zero-knowledge system. A set that supports membership only answers a negative query with undetermined; so does a missing proof and a proof against an earlier root. Zero-knowledge proofs are left to evaluators or later set kinds.

## D8. Objection and appeal

Notice period, objection and appeal are optional. The list enforces the notice period; an objection is an attributed record that changes nothing; where an entry can be contested is named in the documents. Whether an entry has effect during an objection is the manager's rule, stated in the list document.

## D9. Dependencies

Decided by what the core actually uses, which is ERC-165. Identity, assertion, task and anchor registries are reached through modules, which are informative examples. A signed-receipt path would add its own dependencies and is not in this version.

## D10. Chains

Evaluation and enforcement are on one chain. A subject reference carries kind, chain, namespace and identifier from the start, so objects elsewhere can be named. Naming is not verifying: standing and evidence for objects on other chains are undetermined in this version.

## D11. Verification of principals

Source documents and numbers stay off chain and out of every document of the proposal. A rule asks for the result of a verification, its issuer, its validity, its revocation status and its binding to the subject. Signed assertions, on-chain assertions and proofs of predicates are all acceptable. A bare hash is not treated as a protection.

## D12. Worked cases

Three cases, each a test and a part of the evidence run:

- A: bidding for a task under criteria (credential and delivery history), with expiry, change of controller, missing and insufficient evidence, an unreadable source.
- B: a group's deny list with a notice period and an objection, and the extension to bound accounts under D6.
- C: an allow list and two deny lists behind one guard: conflict, no match, the undetermined, an earlier result after revocation, an earlier proof after a new commitment, a borrowed identity; and a deny list of tool versions under the object role.

## Additions made while building

- **Binding.** The four objects of a list stay as they are. Adoption is a fifth structure held by the guard, not a further registry: consumer and adopting authority, scope and actions, lists with pins, thresholds and rules, and the rule for work in progress.
- **Standing.** A list result is of use only to a caller entitled to use it. The guard establishes whether the presenter may act for the subject, with built-in rules for accounts and registry entries and a resolver for everything else. `ALLOW` is never returned for an actor without it.
- **Roles.** A subject is either the actor of a request or its object. The object role covers tools, models and other things that do not act.
- **Three versions.** Criteria identifier, list revision with state hash, binding version with configuration hash. An assessment carries a digest of the last two and a validity; `isCurrent` tells whether an earlier assessment still stands.
- **Snapshots and current checks combine.** A membership can rest on a fixed snapshot and still require a check for revocation or change of controller at each use. The criteria choose; an entry cannot choose a weaker check.
- **Entries tied to a controller.** An entry can hold only while a named account controls the subject.
- **Basis of an entry.** `DESIGNATION` is the manager's own choice and a sufficient ground. `EVIDENCED` states a fact and commits to its evidence. The two are never presented as each other.
- **Work in progress.** An action is decided at every use or once per context. A list change stops new work at once; admitted work continues under the rule the adopter declared until the adopter withdraws the admission. Nothing in the framework touches what was earned or is owed.
- **References between lists.** A source has to exist when a derived list is created, which rules out cycles; chains are bounded; a source that cannot answer makes the derived result undetermined; a derived list can hold to one state of its source.
- **Closed lists.** A closed list answers undetermined, not "nobody is listed".

## Open for the next revision

1. Whether the two-sided form with thresholds is enough, or nested combinations are needed.
2. Whether an entry should be able to name the venue of an appeal on chain, beyond the documents.
3. Which relation types beyond the bound anchor are worth a reference module, and what evidence each needs.
4. Signed assessment receipts for use off chain.
5. Evidence about objects on other chains.
