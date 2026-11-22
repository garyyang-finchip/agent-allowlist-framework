# Ethereum Magicians first post

Posted on 2026-11-20 as topic 30456:

https://ethereum-magicians.org/t/erc-8507-agent-allowlist-framework-aaf/30456

Category: ERCs

Title:

```text
ERC-8507: Agent Allowlist Framework (AAF)
```

The topic was opened as "Draft ERC: Agent Whitelist Framework (AWF)". The number was assigned on 2026-11-21, and the title follows the title and the short name of the specification.

Body, everything below the line. It is the text of the first post as of revision 0.2.1, with the Sepolia deployment added to the Reference implementation section on 2026-11-23.

---

This topic is the discussion thread for ERC-8507, **Agent Allowlist Framework (AAF)**, first posted here as Agent Whitelist Framework (AWF). Since revision 0.2.0 the short name, the interface and contract names, the identifier tags and the repository carry the new name.

## Summary

AAF is a framework in which one or more parties state, within a declared activity, which agents and other objects they admit and which they refuse, on which grounds, and with what effect.

It defines allowlists and denylists (whitelists and blacklists) together: both are lists of one kind that differ only in polarity, `ALLOW` or `DENY`. A list has typed members (accounts, registered agent identities, groups, runtime instances, artefacts such as a model or tool version, named services). A list has no effect on anybody until a consumer binds it for its own actions.

The draft fixes how admission and refusal are expressed, checked and given effect. It does not fix whom to admit, which evidence to require, or what makes an agent good or bad. Every admission and refusal answers one question in full: who adopts, in what scope, for which object and which action, under which version of which rules and evidence, with what result.

## Why

Whether to work with an agent is decided wherever agents meet: a task board admitting bidders, a group admitting members, a service admitting callers, a runtime deciding which tools it runs. Today each keeps a private mapping and a private rule.

- Admission is decided everywhere and stated nowhere. A counterparty cannot see which rule admitted or refused it, or on what ground.
- Identity says who an agent is; assertions and reputation say what is known about it. Neither says whether this party admits it for this action now.
- A list without a scope becomes a verdict. A refusal decided by one group for its own tasks is read as a statement about the agent.
- The unknown is treated as a pass. Presenting no proof of being on a denylist is not proof of absence from it, and an evaluator that cannot read its source has not found the agent clean.
- Standing is borrowed and refusals are evaded. Naming an admitted identity is not being entitled to act for it, and a refusal of one object says nothing yet about a related one.
- Grounds are heterogeneous: wallet, registered identity, profile, credential, runtime, inference usage, completed tasks, counterparties, a verified principal, on-chain activity. No single schema fits, and no list should be forced to use any of them.

## What the draft specifies

- **Four objects of a list.** Scope (where a rule is meant to apply), List (members with a polarity and a manager), Criteria (one immutable version of the rules, with the code and configuration of the module that computes them pinned) and Entry (one subject, with basis, validity window and status).
- **Typed subjects.** A reference carries kind, chain, namespace and identifier. A registered identity, the account that controls it, a group and its members, and two versions of one tool are different objects; nothing passes from one to another unless a list says so. An entry about an account can be tied to the code the account runs, so that the same address with other code is not taken for the object that was assessed.
- **Four ways to have members.** Written by the manager; shown by proofs against a committed set, with proofs of absence for sorted sets; computed from criteria by an evaluator; derived from another list, as a plain reference or by extension to objects related to a listed one.
- **Binding.** A list takes effect only where a consumer, or the adopter it named, binds it: for named actions, with lists on an `ALLOW` and a `DENY` side, thresholds, and declared rules for a conflict, for no match and for the undetermined. Nothing is assumed in favour of a request, and publishing a list gives no authority over anybody.
- **One standard result.** A list answers `MATCH`, `NO_MATCH` or `UNDETERMINED`. A binding answers `ALLOW`, `DENY`, `NOT_APPLICABLE` or `INDETERMINATE`. An outcome with an undetermined input stands only if every way the input could resolve gives the same outcome. What the adopter then does (`PROCEED`, `REFUSE`, `DEFER`, `PROCEED_RESTRICTED`) is recorded apart, so that proceeding on the undetermined is never rewritten as a verified admission. Proceeding within a limit is declared only with a document that states the limit, by a consumer that applies it where the action is carried out.
- **Standing.** `ALLOW` is never returned for an actor unless the caller was verified as entitled to act for the subject.
- **Versions and validity.** Rules, list state and binding are versioned separately. An assessment names all three, so an earlier result is recognisably not current after a revocation, an amendment or an expiry. A result that rests on something that can change without any list changing, such as a credential that can be revoked, holds for its call only.
- **Reuse.** An assessment is not a permit. Whether a decision may be used again is declared by the binding, action by action, and the default is that it may not: every use is decided on its own. The terms of an operation, such as its amount and its target, are checked by the consumer that carries it out.
- **Entries.** An entry rests either on the manager's own choice, which asserts nothing about the subject, or on a stated fact with committed evidence. Notice period, objection and appeal are optional; an objection is recorded and changes nothing by itself.
- **Related-object extension.** A refusal or admission reaches a related object only through a derived list that states the relation, only for consumers that bind that list, and only on evidence from both sides. A listed party naming somebody as its successor relates nobody.
- **Work in progress.** A list change affects later decisions. A binding can declare an action as an admission, which is recorded once and honoured for work already admitted until the adopter withdraws it. Nothing in the draft touches what was earned or is owed.
- **Dimensions of evidence.** An open vocabulary and one form in which every piece of evidence states its proposition, object, source, method, time and expiry.

## What it leaves out

Scores and rankings, identity and assertion systems, proof systems, the terms of an operation, the consequences of a refusal for payment, and verification of the state of other chains. Zero-knowledge set proofs and signed receipts of assessments are not in this version.

## Relation to existing proposals

- ERC-8004 registers agent identities and carries feedback and validation signals. AAF refers to such an identity as a registry entry and can use those signals as evidence; it adds the record of who admits or refuses whom, for what.
- ERC-8107 defines endorsements and denials between ENS names and admission by trust path. AAF covers different ground: lists of typed objects of any kind, maintained on stated grounds, taking effect per consumer, activity and action, combined with declared rules over three-valued results, with no propagation unless a derived list says so. A trust registry of that kind can be the source behind an AAF evaluator.
- ERC-8262 proves set membership and non-membership in zero knowledge. Such proofs fit the three match results and can be attached through an evaluator.

The core of the draft depends on ERC-165 only.

## Reference implementation

Repository:

https://github.com/garyyang-finchip/agent-allowlist-framework

- `AAFRegistry` and `AAFGuard`, with no owner, no upgrade path and no privileged account.
- Two example modules: an evaluator that reads a credential and a delivery history, and a relation source for the account bound to an agent identity.
- 145 Foundry tests, including three worked cases end to end: bidding for a task under criteria; a group's deny list with notice, objection and extension; a service that combines an allow list, a deny list and a committed deny set.
- JSON Schemas of the documents, example documents, and vectors produced by a second implementation outside Solidity and replayed against the contracts.

Pull request:

https://github.com/ethereum/ERCs/pull/2192

Sepolia deployment, 2026-11-22, revision 0.2.0, with the three worked cases executed end to end (87 transactions, blocks 12190415 to 12190525; every step with the result the specification gives, final state read back and checked):

- `AAFRegistry`: https://eth-sepolia.blockscout.com/address/0xBCD17Ac576A675a29F78176209289B72c1b122C7
- `AAFGuard`: https://eth-sepolia.blockscout.com/address/0x1e977Eae5dc102bDc72c6E6aE14654257ec787b7
- Example evaluator and relation source: 0x33712D575b991Ded45131807d8d6b05839217877, 0x65B8755d22bDcDC6A96EaE5FE46B433E208949D9
- Record, addresses, phases and cost: https://github.com/garyyang-finchip/agent-allowlist-framework/blob/main/docs/sepolia-evidence.md

## Open questions

1. **Form of a binding.** Two sides with thresholds and a conflict rule cover "any", "all", "k of n" and "A except B". Are nested combinations needed in practice, or does a second binding cover them?
2. **Undetermined inputs.** An outcome stands only if no resolution of an undetermined input could change it. Is that the right strictness for consumers that defer? Since revision 0.2.0 `PROCEED_RESTRICTED` is declared only with a stated limit that the consumer applies; is that condition enough?
3. **Extension to related objects.** The draft allows one relation hop on evidence from both sides, computed when asked. Which relations beyond "account bound to an identity" have evidence strong enough to be worth a reference module?
4. **Proofs of absence.** Sorted sets with sentinels need only hashing and disclose two neighbouring keys per proof. Is that acceptable for shared deny lists, or should a zero-knowledge set kind be part of the first version?
5. **Standing.** The built-in rules read ownership and approval from the registry of an entry. What should count as standing for groups and for runtime instances?
6. **Objection and appeal.** The draft records objections and names venues in documents. Should an entry carry the venue of its appeal on chain?
7. **Code of an account.** An entry can be tied to the code hash at the address, which follows a delegation target and does not see an implementation behind a proxy. Is a built-in rule for common proxy layouts worth having, or is an evaluator the right place?
