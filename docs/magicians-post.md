# Ethereum Magicians first post

Posted on 2026-11-20 as topic 30456:

https://ethereum-magicians.org/t/draft-erc-agent-whitelist-framework-awf-scoped-allow-and-deny-lists-for-agents-adopted-per-consumer-with-stated-grounds-and-uniform-results/30456

Category: ERCs

Title:

```text
Draft ERC: Agent Whitelist Framework (AWF) - scoped allow and deny lists for agents, adopted per consumer, with stated grounds and uniform results
```

When the number is assigned the title becomes `ERC-<N>: Agent Whitelist Framework`.

Body, everything below the line:

---

This topic is the discussion thread for a draft ERC, **Agent Whitelist Framework (AWF)**.

## Summary

AWF is a framework in which one or more parties state, within a declared activity, which agents and other objects they admit and which they refuse, on which grounds, and with what effect.

It defines whitelists and blacklists together: both are lists of one kind that differ only in polarity, `ALLOW` or `DENY`. A list has typed members (accounts, registered agent identities, groups, runtime instances, artefacts such as a model or tool version, named services). A list has no effect on anybody until a consumer binds it for its own actions.

The draft fixes how admission and refusal are expressed, checked and given effect. It does not fix whom to admit, which evidence to require, or what makes an agent good or bad. Every admission and refusal answers one question in full: who adopts, in what scope, for which object and which action, under which version of which rules and evidence, with what result.

## Why

Whether to work with an agent is decided wherever agents meet: a task board admitting bidders, a group admitting members, a service admitting callers, a runtime deciding which tools it runs. Today each keeps a private mapping and a private rule.

- Admission is decided everywhere and stated nowhere. A counterparty cannot see which rule admitted or refused it, or on what ground.
- Identity says who an agent is; assertions and reputation say what is known about it. Neither says whether this party admits it for this action now.
- A list without a scope becomes a verdict. A refusal decided by one group for its own tasks is read as a statement about the agent.
- The unknown is treated as a pass. Presenting no proof of being on a blacklist is not proof of absence from it, and an evaluator that cannot read its source has not found the agent clean.
- Standing is borrowed and refusals are evaded. Naming an admitted identity is not being entitled to act for it, and a refusal of one object says nothing yet about a related one.
- Grounds are heterogeneous: wallet, registered identity, profile, credential, runtime, inference usage, completed tasks, counterparties, a verified principal, on-chain activity. No single schema fits, and no list should be forced to use any of them.

## What the draft specifies

- **Four objects of a list.** Scope (where a rule is meant to apply), List (members with a polarity and a manager), Criteria (one immutable version of the rules, with the code and configuration of the module that computes them pinned) and Entry (one subject, with basis, validity window and status).
- **Typed subjects.** A reference carries kind, chain, namespace and identifier. A registered identity, the account that controls it, a group and its members, and two versions of one tool are different objects; nothing passes from one to another unless a list says so.
- **Four ways to have members.** Written by the manager; shown by proofs against a committed set, with proofs of absence for sorted sets; computed from criteria by an evaluator; derived from another list, as a plain reference or by extension to objects related to a listed one.
- **Binding.** A list takes effect only where a consumer, or the adopter it named, binds it: for named actions, with lists on an `ALLOW` and a `DENY` side, thresholds, and declared rules for a conflict, for no match and for the undetermined. Nothing is assumed in favour of a request, and publishing a list gives no authority over anybody.
- **One standard result.** A list answers `MATCH`, `NO_MATCH` or `UNDETERMINED`. A binding answers `ALLOW`, `DENY`, `NOT_APPLICABLE` or `INDETERMINATE`. An outcome with an undetermined input stands only if every way the input could resolve gives the same outcome. What the adopter then does (`PROCEED`, `REFUSE`, `DEFER`, `PROCEED_RESTRICTED`) is recorded apart, so that proceeding on the undetermined is never rewritten as a verified admission.
- **Standing.** `ALLOW` is never returned for an actor unless the caller was verified as entitled to act for the subject.
- **Versions.** Rules, list state and binding are versioned separately. An assessment names all three and carries a validity, so an earlier result is recognisably not current after a revocation, an amendment or an expiry.
- **Entries.** An entry rests either on the manager's own choice, which asserts nothing about the subject, or on a stated fact with committed evidence. Notice period, objection and appeal are optional; an objection is recorded and changes nothing by itself.
- **Related-object extension.** A refusal or admission reaches a related object only through a derived list that states the relation, only for consumers that bind that list, and only on evidence from both sides. A listed party naming somebody as its successor relates nobody.
- **Work in progress.** A list change affects later assessments. What it means for work already admitted is declared by the binding, action by action, and nothing in the draft touches what was earned or is owed.
- **Dimensions of evidence.** An open vocabulary and one form in which every piece of evidence states its proposition, object, source, method, time and expiry.

## What it leaves out

Scores and rankings, identity and assertion systems, proof systems, the consequences of a refusal for payment, and verification of the state of other chains. Zero-knowledge set proofs and signed receipts of assessments are not in this version.

## Relation to existing proposals

- ERC-8004 registers agent identities and carries feedback and validation signals. AWF refers to such an identity as a registry entry and can use those signals as evidence; it adds the record of who admits or refuses whom, for what.
- ERC-8107 defines endorsements and denials between ENS names and admission by trust path. AWF covers different ground: lists of typed objects of any kind, maintained on stated grounds, taking effect per consumer, activity and action, combined with declared rules over three-valued results, with no propagation unless a derived list says so. A trust registry of that kind can be the source behind an AWF evaluator.
- ERC-8262 proves set membership and non-membership in zero knowledge. Such proofs fit the three match results and can be attached through an evaluator.

The core of the draft depends on ERC-165 only.

## Reference implementation

Repository:

https://github.com/garyyang-finchip/agent-whitelist-framework

- `AWFRegistry` and `AWFGuard`, with no owner, no upgrade path and no privileged account.
- Two example modules: an evaluator that reads a credential and a delivery history, and a relation source for the account bound to an agent identity.
- 134 Foundry tests, including three worked cases end to end: bidding for a task under criteria; a group's deny list with notice, objection and extension; a service that combines an allow list, a deny list and a committed deny set.
- JSON Schemas of the documents, example documents, and vectors produced by a second implementation outside Solidity and replayed against the contracts.

Pull request:

https://github.com/ethereum/ERCs/pull/2192

Sepolia deployment: to be added to this post.

## Open questions

1. **Form of a binding.** Two sides with thresholds and a conflict rule cover "any", "all", "k of n" and "A except B". Are nested combinations needed in practice, or does a second binding cover them?
2. **Undetermined inputs.** An outcome stands only if no resolution of an undetermined input could change it. Is that the right strictness for consumers that defer, and is `PROCEED_RESTRICTED` a useful disposition or an invitation to treat the unknown as a pass?
3. **Extension to related objects.** The draft allows one relation hop on evidence from both sides, computed when asked. Which relations beyond "account bound to an identity" have evidence strong enough to be worth a reference module?
4. **Proofs of absence.** Sorted sets with sentinels need only hashing and disclose two neighbouring keys per proof. Is that acceptable for shared deny lists, or should a zero-knowledge set kind be part of the first version?
5. **Standing.** The built-in rules read ownership and approval from the registry of an entry. What should count as standing for groups and for runtime instances?
6. **Objection and appeal.** The draft records objections and names venues in documents. Should an entry carry the venue of its appeal on chain?
