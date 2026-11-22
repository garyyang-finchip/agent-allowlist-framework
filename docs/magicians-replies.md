# Replies on the discussion topic

Topic 30456: https://ethereum-magicians.org/t/erc-8507-agent-allowlist-framework-aaf/30456

## Revision 0.2.0

One reply, to the reviews in posts 2 (Secrypta) and 3 (Revinand). Everything below the line.

---

**Revision 0.2.0**

The draft has its number, ERC-8507. Following an editor's suggestion its title is now Agent Allowlist Framework, and the rest of the naming follows the title: the short name is AAF, `IAWFRegistry` and `IAWFGuard` are now `IAAFRegistry` and `IAAFGuard`, tags and names such as `AWF.Scope.v1` and `awf.subject.account` are now `AAF.Scope.v1` and `aaf.subject.account`, and the repository is `agent-allowlist-framework`. Function selectors do not depend on these names; every identifier that hashes a tag or a name changed. The points raised by @Secrypta and @Revinand are taken into the specification and the reference implementation in the same revision, which is in the pull request and in the repository.

**@Secrypta, binding `ALLOW` to the exact intent.** An assessment is not something a requester can present. `enforce` answers only the consumer of the binding, inside the consumer's own call, and Section 8.8 rules out accepting an earlier result shown by a requester. The gap was on the consumer's side: any assessment could be kept and relied on until its validity passed, for any action, and nothing in a binding said otherwise. What changed:

- A binding declares reuse per action: `NONE`, `WHILE_CURRENT` or `ADMISSION`. The zero value is `NONE`. Every use is then decided on its own, the assessment carries `validUntil = 0`, and `isCurrent` is false for it. `ActionRule.once` is replaced by `ActionRule.reuse`.
- An action through which value moves is to be declared `NONE` and decided in the execution that carries out the transfer, so that a decision is used by that operation and by no other. The record can name the operation: a commitment to it (target, value, calldata hash) can be passed as the context of the request.
- Target, value and calldata themselves stay with the consumer. AAF answers who may take part in an action and does not authorise an amount. The scope of the specification and Security Considerations ("An assessment is not a permit") now say so.

Not added: a register of single-use operation commitments inside the guard. With reuse `NONE` no decision is stored that could be used a second time, and protection against repeating the operation is the consumer's nonce.

**@Secrypta, code behind the address.** Adopted as proposed. An entry about an account on the chain of the registry can be tied to a code hash (`EntryInput.codeHash`). While the account has other code the result is `UNDETERMINED` with reason `CODE_CHANGED`, never `MATCH`, and every result of a tied entry has `validUntil = 0`, because code can change without the list changing. For an account that delegates under EIP-7702, `EXTCODEHASH` is the hash of the delegation designator, so the tie follows the delegation target; a tie to the hash of empty code means "this account while it has no code and no delegation". The limit is stated in the text: the tie sees the code at the address, not an implementation behind a proxy or an installed module. Lists that depend on those read them through an evaluator. Whether a built-in rule for common proxy layouts is worth having is added to the open questions.

**@Secrypta, `PROCEED_RESTRICTED`.** Agreed, and this settles the second half of open question 2. The disposition stays under three conditions. The limit is stated in the binding document (`rules.restriction`: what is limited, by how much, where it is applied). A guard refuses a binding that declares `PROCEED_RESTRICTED` without a binding document. A consumer that cannot apply the limit where the action is carried out declares `DEFER` or `REFUSE`. A guard cannot verify that a consumer applies its limit, and the text says that as well. The example consumer applies one use per subject, action and context and refuses beyond it.

**@Revinand, `validUntil` and revocation.** Correct, and the example evaluator was wrong: Section 6.4 said that a revocation is covered by the validity of a finding, while the evaluator reported the expiry of the credential. What changed:

- Section 6.8: an evaluator returns `validUntil = 0` whenever its result rests on anything that can change at a time it cannot read in advance, such as a revocable credential. An expiry is no guarantee where revocation is possible. Zero already meant "this call only" in the interface.
- `AAFCredentialHistoryEvaluator` returns 0. Results of the related-object extension already did, and criteria documents now state how long a result holds.
- No re-check of dependencies was added to `isCurrent`. Reading every dependency again on reuse is the evaluation under another name. A consumer that wants a decision to outlive its inputs declares the action an `ADMISSION`, which is explicit and can be withdrawn.
- Section 8.8: an assessment with `validUntil = 0` is never relied on again, and reuse requires that the controller found at the use is the controller named in the assessment.
- Case A has two more steps, in the tests and in the evidence run: a credential with thirty days left is revoked, no state digest changes, and the next bid is refused.

The interface identifiers of `IAAFRegistry` and `IAAFGuard` changed with the two structures. The repository has 145 tests. The Sepolia run has not been made yet; it will be made on this revision and added to the first post.

Thanks to both for the review.
