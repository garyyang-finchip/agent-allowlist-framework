#!/usr/bin/env node
// SPDX-License-Identifier: CC0-1.0
//
// Identifiers, documents, schema checks and test vectors for the Agent Whitelist Framework.
// This file computes everything from the rules of the specification, independently of the
// Solidity code; the Solidity tests replay what it writes.
//
//   node awf.mjs examples            writes the example documents under assets/.../examples
//   node awf.mjs vectors             writes the vectors under assets/.../vectors (needs `forge build`)
//   node awf.mjs check               validates the examples and confirms examples and vectors are current
//   node awf.mjs plan <network>      writes deployments/<network>/plan.json and its documents
//                                    (DEPLOYER_PK set; network is anvil or sepolia)

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AbiCoder, Wallet, getAddress, keccak256, solidityPacked, toUtf8Bytes, encodeBytes32String } from "ethers";
import Ajv2020 from "ajv/dist/2020.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ASSETS = path.join(ROOT, "assets", "erc-9999");
const coder = AbiCoder.defaultAbiCoder();
const ZERO32 = "0x" + "00".repeat(32);
const MAX32 = "0x" + "ff".repeat(32);
const ZERO_ADDRESS = "0x" + "00".repeat(20);

// ------------------------------------------------------------------ constants of the specification

const tag = (text) => keccak256(toUtf8Bytes(text));

export const TAGS = {
  SCOPE_TAG: tag("AWF.Scope.v1"),
  CRITERIA_TAG: tag("AWF.Criteria.v1"),
  LIST_TAG: tag("AWF.List.v1"),
  STATE_TAG: tag("AWF.ListState.v1"),
  SET_LEAF_TAG: tag("AWF.SetLeaf.v1"),
  BINDING_TAG: tag("AWF.Binding.v1"),
  DIGEST_TAG: tag("AWF.StateDigest.v1"),
};

const KIND_NAMES = ["account", "entry", "group", "instance", "digest", "name"].map((k) => `awf.subject.${k}`);
const ACTION_NAMES = ["bid", "join", "invoke", "use-tool"].map((a) => `awf.action.${a}`);
const RELATION_NAMES = ["awf.relation.bound-anchor"];

export const POLARITY = { NONE: 0, ALLOW: 1, DENY: 2 };
export const MODE = { NONE: 0, ENUMERATED: 1, COMMITTED: 2, PREDICATE: 3, DERIVED: 4 };
export const MATCH = { UNDETERMINED: 0, MATCH: 1, NO_MATCH: 2 };
export const OUTCOME = { INDETERMINATE: 0, ALLOW: 1, DENY: 2, NOT_APPLICABLE: 3 };
export const DISPOSITION = { REFUSE: 0, PROCEED: 1, DEFER: 2, PROCEED_RESTRICTED: 3 };
export const SET_KIND = { NONE: 0, MEMBERSHIP: 1, SORTED: 2 };
export const ROLE = { ACTOR: 0, OBJECT: 1 };

const REASONS = [
  "LISTED", "NOT_LISTED", "ENTRY_PENDING", "ENTRY_EXPIRED", "ENTRY_SUSPENDED", "ENTRY_REVOKED",
  "CONTROLLER_UNKNOWN", "CONTROLLER_CHANGED", "LIST_UNKNOWN", "LIST_CLOSED", "SET_MEMBER", "SET_NON_MEMBER",
  "SET_MISSING", "PROOF_MISSING", "PROOF_INVALID", "NEGATIVE_UNSUPPORTED", "MODULE_CHANGED", "MODULE_FAILED",
  "SOURCE_STATE_CHANGED", "EXTENSION_LIMIT", "RELATED", "NOT_RELATED", "RELATION_INCOMPLETE",
  "ALLOW_MATCH", "DENY_MATCH", "CONFLICT", "DEFAULT", "UNDETERMINED_INPUT", "BINDING_UNKNOWN", "BINDING_RETIRED",
  "CONSUMER_MISMATCH", "ACTION_NOT_COVERED", "CONTEXT_NOT_COVERED", "LIST_STATE_CHANGED", "REGISTRY_UNAVAILABLE",
  "POLARITY_MISMATCH", "PRESENTER_NOT_AUTHORIZED", "STANDING_UNVERIFIED", "ADMISSION_HONOURED",
];

// ------------------------------------------------------------------ canonical form and hashes

/** RFC 8785 for the values documents use: objects, arrays, strings, integers, booleans, null. */
export function canonical(value) {
  if (value === null || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) throw new Error("documents hold integers only");
    return String(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (typeof value === "object") {
    const keys = Object.keys(value).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + canonical(value[k])).join(",") + "}";
  }
  throw new Error("value has no canonical form");
}

export const documentHash = (doc) => keccak256(toUtf8Bytes(canonical(doc)));
const enc = (types, values) => coder.encode(types, values);
const hash = (types, values) => keccak256(enc(types, values));
const word = (n) => "0x" + BigInt(n).toString(16).padStart(64, "0");
const pad = (address) => word(BigInt(address));

// ------------------------------------------------------------------ identifiers

export const subjectRef = (kindName, chainId, namespace, id) => ({ kind: kindName, chainId, namespace, id });
export const accountRef = (chainId, address) => subjectRef("awf.subject.account", chainId, ZERO_ADDRESS, pad(address));
export const entryRef = (chainId, registry, id) => subjectRef("awf.subject.entry", chainId, registry, word(id));
export const digestRef = (digest) => subjectRef("awf.subject.digest", 0, ZERO_ADDRESS, digest);

export const subjectKey = (ref) =>
  hash(["bytes32", "uint256", "address", "bytes32"], [tag(ref.kind), ref.chainId, ref.namespace, ref.id]);

export const scopeId = (chainId, scope) =>
  hash(["bytes32", "uint256", "address", "bytes32", "bytes32"], [TAGS.SCOPE_TAG, chainId, scope.anchor, scope.context, scope.documentHash]);

export const criteriaId = (chainId, c) =>
  hash(
    ["bytes32", "uint256", "bytes32", "address", "bytes32", "bytes32", "bytes32", "uint8"],
    [TAGS.CRITERIA_TAG, chainId, c.documentHash, c.module, c.moduleCodeHash, c.moduleConfig, c.rule, c.fanout],
  );

export const listId = (chainId, registry, creator, config) =>
  hash(
    ["bytes32", "uint256", "address", "address", "uint8", "uint8", "bytes32", "bytes32"],
    [TAGS.LIST_TAG, chainId, registry, creator, config.polarity, config.mode, config.source, config.salt],
  );

export const stateHash = (s) =>
  hash(
    ["bytes32", "bytes32", "uint64", "address", "bool", "bytes32", "bytes32", "bytes32", "bytes32"],
    [TAGS.STATE_TAG, s.listId, s.revision, s.manager, s.closed, s.criteriaId, s.setRoot, s.sourcePin, s.sourceState],
  );

export const bindingId = (chainId, guard, consumer, scope, salt) =>
  hash(["bytes32", "uint256", "address", "address", "bytes32", "bytes32"], [TAGS.BINDING_TAG, chainId, guard, consumer, scope, salt]);

export const stateDigest = (binding, version, states) =>
  hash(["bytes32", "bytes32", "uint64", "bytes32[]"], [TAGS.DIGEST_TAG, binding, version, states]);

const BINDING_TYPE =
  "tuple(tuple(address anchor,bytes32 context,bytes32 documentHash) scope,uint8 role," +
  "tuple(bytes32 action,bool once)[] actions,tuple(address registry,bytes32 listId,bytes32 pin)[] allow,uint8 allowThreshold," +
  "tuple(address registry,bytes32 listId,bytes32 pin)[] deny,uint8 denyThreshold,uint8 onConflict,uint8 onNoMatch," +
  "uint8 onIndeterminate,uint8 onNotApplicable,address resolver,bytes32 documentHash)";

export const encodeBinding = (config) => enc([BINDING_TYPE], [config]);
export const bindingConfigHash = (config) => keccak256(encodeBinding(config));

// ------------------------------------------------------------------ committed sets

const setLeaf = (index, key) => hash(["bytes32", "uint256", "bytes32"], [TAGS.SET_LEAF_TAG, index, key]);
const node = (left, right) => hash(["bytes32", "bytes32"], [left, right]);

/** `keys` in the order of the leaves. A sorted set starts with the zero key and ends with the greatest key. */
export function buildSet(keys) {
  let depth = 0;
  while (2 ** depth < keys.length) depth += 1;
  const levels = [Array.from({ length: 2 ** depth }, (_, i) => (i < keys.length ? setLeaf(i, keys[i]) : ZERO32))];
  for (let l = 1; l <= depth; l += 1) {
    const below = levels[l - 1];
    levels.push(Array.from({ length: below.length / 2 }, (_, j) => node(below[2 * j], below[2 * j + 1])));
  }
  return { keys, levels, root: levels[depth][0], size: keys.length };
}

function pathOf(set, index) {
  const out = [];
  for (let l = 0; l < set.levels.length - 1; l += 1) {
    out.push(set.levels[l][index ^ 1]);
    index >>= 1;
  }
  return out;
}

const SET_PROOF = "tuple(bool member,uint256 index,bytes32[] path,bytes32 lowKey,bytes32 highKey,bytes32[] highPath)";
const encodeProof = (p) => enc([SET_PROOF], [p]);

export const memberProof = (set, index) =>
  encodeProof({ member: true, index, path: pathOf(set, index), lowKey: ZERO32, highKey: ZERO32, highPath: [] });

/** Proof that `key` lies strictly between two neighbouring leaves of a sorted set. */
export function absenceProof(set, key) {
  let low = 0;
  while (BigInt(set.keys[low + 1]) < BigInt(key)) low += 1;
  return encodeProof({
    member: false,
    index: low,
    path: pathOf(set, low),
    lowKey: set.keys[low],
    highKey: set.keys[low + 1],
    highPath: pathOf(set, low + 1),
  });
}

export const sortedSet = (memberKeys) =>
  buildSet([ZERO32, ...[...memberKeys].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1)), MAX32]);

// ------------------------------------------------------------------ outcome rules

/** Threshold over three-valued results. An empty side matches nothing. */
export function side(results, threshold) {
  if (results.length === 0) return MATCH.NO_MATCH;
  const matched = results.filter((r) => r === MATCH.MATCH).length;
  const open = results.filter((r) => r === MATCH.UNDETERMINED).length;
  if (matched >= threshold) return MATCH.MATCH;
  if (matched + open < threshold) return MATCH.NO_MATCH;
  return MATCH.UNDETERMINED;
}

/** The outcome is determined only if every way the undetermined sides could resolve gives the same one. */
export function combine(allowSide, denySide, onConflict, onNoMatch) {
  const ways = (s) => (s === MATCH.UNDETERMINED ? [true, false] : [s === MATCH.MATCH]);
  const seen = new Set();
  for (const a of ways(allowSide)) {
    for (const d of ways(denySide)) {
      seen.add(a && d ? onConflict : a ? OUTCOME.ALLOW : d ? OUTCOME.DENY : onNoMatch);
    }
  }
  return seen.size === 1 && !seen.has(OUTCOME.INDETERMINATE) ? [...seen][0] : OUTCOME.INDETERMINATE;
}

// ------------------------------------------------------------------ documents of the worked cases

const eip155 = (chainId, address) => `eip155:${chainId}:${getAddress(address)}`;

/**
 * The documents of the three worked cases. They name accounts and no contract, so that they can
 * be fixed before anything is deployed.
 */
export function documents({ chainId, manager, issuer, noticePeriod, schemeId }) {
  const d = {};
  const subjectsOf = (kinds, bindsTo, onChange, note) => (note ? { kinds, bindsTo, onChange, note } : { kinds, bindsTo, onChange });

  // ---- Case A: who may bid for a task is decided by criteria
  d["case-a/scope.json"] = {
    awf: "1",
    kind: "scope",
    name: "Tender 7",
    activity: "Bidding for task 7 on a task board. The context of the scope is the task number.",
    actions: [{ action: "awf.action.bid", meaning: "Submitting a bid that the board will consider" }],
    resources: ["The task description", "The bidding slot"],
    boundary: "Other tasks of the board, delivery, acceptance and payment are outside this scope.",
  };
  d["case-a/criteria.json"] = {
    awf: "1",
    kind: "criteria",
    name: "Qualified bidders",
    version: "1",
    statement:
      "A registered agent identity is a member while an accepted issuer asserts delivery capability of level 2 or higher for it, and its current controller shows two accepted task deliveries made within the last ninety days.",
    subjects: subjectsOf(
      ["awf.subject.entry"],
      "controller",
      "reverify",
      "The credential and the history are both tied to the controller. A new controller qualifies on its own evidence.",
    ),
    dimensions: [
      {
        dimension: "awf.credential",
        proposition: "An accepted issuer asserts at least the required level under the named scheme",
        source: "The assertion registry the evaluator is configured with, restricted to the accepted issuers",
        method: "onchain-read",
        observation: { kind: "current" },
        revocation: "Read at every evaluation; expiry, revocation and a changed controller remove the assertion",
        onMissing: "NO_MATCH",
        onUnavailable: "UNDETERMINED",
        disclosure: "Nothing beyond the level the registry already shows",
      },
      {
        dimension: "awf.performance",
        proposition: "The current controller made at least the required number of accepted deliveries within the window",
        source: "The task ledger the evaluator is configured with",
        method: "presented-and-checked",
        observation: { kind: "interval", window: 7776000 },
        onMissing: "NO_MATCH",
        onUnavailable: "UNDETERMINED",
        disclosure: "The requester names the deliveries it relies on",
      },
    ],
    combination: "all",
    evaluation: {
      evidenceFormat: "abi.encode((uint256 tokenId,uint256 submissionId)[]) in strictly ascending order, at most sixteen",
      parameters: {
        schemeId,
        minLevel: 2,
        issuers: [eip155(chainId, issuer)],
        minAccepted: 2,
        window: 7776000,
      },
    },
  };
  d["case-a/list-qualified.json"] = {
    awf: "1",
    kind: "list",
    name: "Qualified bidders",
    polarity: "ALLOW",
    mode: "PREDICATE",
    management: {
      manager: eip155(chainId, manager),
      authority: "A single account. It chooses the criteria version; it does not choose members.",
    },
    purpose: {
      statement: "Agents that may bid for tenders which require proven delivery capability",
      scopeDocument: documentHash(d["case-a/scope.json"]),
    },
    subjects: d["case-a/criteria.json"].subjects,
    basis: {
      statement: "Membership follows from the criteria alone and is computed when asked.",
      designation: false,
      criteriaDocument: documentHash(d["case-a/criteria.json"]),
    },
    time: {
      noticePeriod: 0,
      validity: "As long as the credential and the counted deliveries stay inside their windows",
      review: "At every request",
    },
    dueProcess: {
      notice: "not used",
      objection: "not used",
      appeal: "not used",
      effectDuringObjection: "not used",
    },
  };
  d["case-a/binding.json"] = {
    awf: "1",
    kind: "binding",
    name: "Tender 7 admits qualified bidders",
    adoption: {
      consumer: "The task board",
      authority: "The account the board named as its adopter",
    },
    scopeDocument: documentHash(d["case-a/scope.json"]),
    role: "ACTOR",
    actions: [
      {
        action: "awf.action.bid",
        once: false,
        effect: "Proceeding records the bid. Refusing leaves the bidder free to bid again with other evidence.",
      },
    ],
    lists: {
      allow: [{ list: "Qualified bidders (ALLOW, PREDICATE)", follows: "latest" }],
      allowThreshold: 1,
      deny: [],
      denyThreshold: 0,
    },
    rules: {
      onConflict: "DENY",
      onNoMatch: "DENY",
      onIndeterminate: "DEFER",
      onNotApplicable: "REFUSE",
    },
    standing: "The caller owns the agent identity or is approved for it.",
    updates: "Follows the list. Amended by the adopter.",
    workInProgress: "Not used: bidding has no continuing work. A bid already recorded stays recorded.",
  };

  // ---- Case B: a group refuses listed agents, with notice, and decides separately on related accounts
  d["case-b/scope.json"] = {
    awf: "1",
    kind: "scope",
    name: "Swarm alpha",
    activity: "Membership of one agent group. The context of the scope is the group identifier.",
    actions: [{ action: "awf.action.join", meaning: "Becoming a member of the group" }],
    boundary: "What members do inside the group, and what they were paid or are owed, is outside this scope.",
  };
  d["case-b/list-barred.json"] = {
    awf: "1",
    kind: "list",
    name: "Barred from swarm alpha",
    polarity: "DENY",
    mode: "ENUMERATED",
    management: {
      manager: eip155(chainId, manager),
      authority: "A single account acting on the decisions of the group",
      decisionRecord: "Each entry names the decision it carries out in its basis document.",
    },
    purpose: {
      statement: "Agent identities the group refuses to admit",
      scopeDocument: documentHash(d["case-b/scope.json"]),
    },
    subjects: subjectsOf(
      ["awf.subject.entry", "awf.subject.account"],
      "identity",
      "retain",
      "An entry names one object. Whether it reaches related objects is decided by whoever adopts the extension list.",
    ),
    basis: {
      statement: "Every entry states a breach of the group charter and commits to its evidence.",
      designation: false,
    },
    time: {
      noticePeriod,
      validity: "Until revoked",
      review: "On objection",
    },
    dueProcess: {
      notice: "An entry is on record for the notice period before it has effect.",
      objection: "Anyone may record an objection to an entry; the listed side is expected to do so within the notice period.",
      appeal: "The manager reviews objections. A dispute venue may be named in the basis document.",
      effectDuringObjection: "An objection does not delay or lift an entry. The manager may suspend the entry while it reviews.",
    },
  };
  d["case-b/criteria-extension.json"] = {
    awf: "1",
    kind: "criteria",
    name: "Anchors bound to barred identities",
    version: "1",
    statement:
      "An account is a member while it is bound as the anchor of an agent identity that the source list names, and that identity names the account as its owner or wallet.",
    subjects: subjectsOf(["awf.subject.account"], "identity", "reverify", "Read at every request."),
    dimensions: [
      {
        dimension: "awf.relation",
        proposition: "The account is the bound anchor of a listed identity",
        source: "The anchor registry and the identity registry the relation source is configured with",
        method: "onchain-read",
        observation: { kind: "current" },
        onMissing: "NO_MATCH",
        onUnavailable: "UNDETERMINED",
      },
      {
        dimension: "awf.list",
        proposition: "The identity is a member of the source list",
        source: "The source list, at its latest state",
        method: "list-reference",
        observation: { kind: "current" },
        onMissing: "NO_MATCH",
        onUnavailable: "UNDETERMINED",
      },
    ],
    combination: "all",
    extension: {
      relation: "awf.relation.bound-anchor",
      direction: "From the listed agent identity to the account bound to it",
      evidence:
        "Two acts, one by each side: the account bound itself to the identity, and the identity names the account as owner or wallet. A statement by one side alone, such as naming a successor, establishes nothing.",
      time: "current",
      fanout: 1,
      hops: 1,
    },
  };
  d["case-b/list-barred-anchors.json"] = {
    awf: "1",
    kind: "list",
    name: "Anchors of identities barred from swarm alpha",
    polarity: "DENY",
    mode: "DERIVED",
    management: {
      manager: eip155(chainId, manager),
      authority: "A single account. It chooses the source and the relation; it does not choose members.",
    },
    purpose: {
      statement: "Lets an adopter extend the refusal of an identity to the account bound to it, if the adopter decides to",
      scopeDocument: documentHash(d["case-b/scope.json"]),
    },
    subjects: d["case-b/criteria-extension.json"].subjects,
    basis: {
      statement: "Membership is derived at every request from the source list and the relation.",
      designation: false,
      criteriaDocument: documentHash(d["case-b/criteria-extension.json"]),
      source: "Barred from swarm alpha (DENY, ENUMERATED), followed at its latest state",
    },
    time: {
      noticePeriod: 0,
      validity: "While the origin is listed and the relation holds",
      review: "At every request",
    },
    dueProcess: {
      notice: "not used",
      objection: "An objection is directed at the entry of the origin in the source list.",
      appeal: "not used",
      effectDuringObjection: "not used",
    },
  };
  d["case-b/basis-incident.json"] = {
    awf: "1",
    kind: "basis",
    basis: "EVIDENCED",
    statement: "The agent accepted a task of the group and delivered a result copied from another member.",
    status: "interim measure",
    evidence: [
      {
        dimension: "awf.performance",
        proposition: "The delivery of the agent equals an earlier delivery of another member",
        source: "The group's task record",
        method: "presented-and-checked",
        observation: { kind: "snapshot", at: "2026-11-18T00:00:00Z" },
        reference: "Decision 12 of the group, with both result digests",
      },
    ],
  };
  const bindingB = (extended) => ({
    awf: "1",
    kind: "binding",
    name: extended ? "Swarm alpha refuses barred identities and their anchors" : "Swarm alpha refuses barred identities",
    adoption: {
      consumer: "The group's membership contract",
      authority: "The account the membership contract named as its adopter",
    },
    scopeDocument: documentHash(d["case-b/scope.json"]),
    role: "ACTOR",
    actions: [{ action: "awf.action.join", once: false, effect: "Proceeding makes the subject a member. Refusing does not." }],
    lists: {
      allow: [],
      allowThreshold: 0,
      deny: extended
        ? [
            { list: "Barred from swarm alpha (DENY, ENUMERATED)", follows: "latest" },
            {
              list: "Anchors of identities barred from swarm alpha (DENY, DERIVED)",
              follows: "latest",
              why: "The group decided that the refusal of an identity reaches the account bound to it.",
            },
          ]
        : [{ list: "Barred from swarm alpha (DENY, ENUMERATED)", follows: "latest" }],
      denyThreshold: 1,
    },
    rules: {
      onConflict: "DENY",
      onNoMatch: "ALLOW",
      onIndeterminate: "DEFER",
      onNotApplicable: "PROCEED",
    },
    standing: "The caller is the account, or owns the agent identity or is approved for it.",
    updates: "Follows both lists. Amended by the adopter.",
    workInProgress:
      "Joining is decided every time. Membership already held, and anything a member has earned, is not touched by this binding.",
  });
  d["case-b/binding.json"] = bindingB(false);
  d["case-b/binding-extended.json"] = bindingB(true);

  // ---- Case C: a service combines an allow list with two deny lists, and excludes tool versions
  d["case-c/scope.json"] = {
    awf: "1",
    kind: "scope",
    name: "Inference gateway",
    activity: "Calls to one service. The context of the scope is the service identifier.",
    actions: [
      { action: "awf.action.invoke", meaning: "Calling the service as an agent" },
      { action: "awf.action.use-tool", meaning: "Having the service run a tool on the caller's behalf" },
    ],
    resources: ["The service endpoint", "The tools the service can run"],
    boundary: "Billing and the content of requests are outside this scope.",
  };
  const designated = (name, polarity, statement, noticeUse) => ({
    awf: "1",
    kind: "list",
    name,
    polarity,
    mode: "ENUMERATED",
    management: { manager: eip155(chainId, manager), authority: "A single account" },
    purpose: { statement, scopeDocument: documentHash(d["case-c/scope.json"]) },
    subjects: subjectsOf(["awf.subject.account"], "identity", "retain"),
    basis: {
      statement: "The manager's own choice. An entry asserts nothing about the subject.",
      designation: true,
    },
    time: { noticePeriod: 0, validity: "Until revoked", review: "not used" },
    dueProcess: { notice: noticeUse, objection: "not used", appeal: "not used", effectDuringObjection: "not used" },
  });
  d["case-c/list-partners.json"] = designated("Partners", "ALLOW", "Accounts the operator of the service works with", "not used");
  d["case-c/list-barred.json"] = designated("Barred", "DENY", "Accounts the operator of the service does not work with", "not used");
  d["case-c/list-sanctioned.json"] = {
    awf: "1",
    kind: "list",
    name: "Sanctioned accounts",
    polarity: "DENY",
    mode: "COMMITTED",
    management: {
      manager: eip155(chainId, manager),
      authority: "A single account that commits the set a third party compiles",
    },
    purpose: {
      statement: "Accounts a service has to refuse, published as a commitment",
      scopeDocument: documentHash(d["case-c/scope.json"]),
    },
    subjects: subjectsOf(["awf.subject.account"], "identity", "retain"),
    basis: {
      statement: "The compiler of the set states its grounds outside this list.",
      designation: false,
    },
    time: { noticePeriod: 0, validity: "Until the next commitment", review: "At every commitment" },
    dueProcess: { notice: "not used", objection: "not used", appeal: "not used", effectDuringObjection: "not used" },
    set: {
      kind: "SORTED",
      disclosure:
        "The manager gives any account the proof for its own key. A proof of absence shows the two neighbouring keys and nothing else.",
    },
  };
  d["case-c/list-excluded-tools.json"] = {
    awf: "1",
    kind: "list",
    name: "Excluded tool versions",
    polarity: "DENY",
    mode: "ENUMERATED",
    management: { manager: eip155(chainId, manager), authority: "A single account" },
    purpose: {
      statement: "Tool packages the service must not run, named by the digest of the package",
      scopeDocument: documentHash(d["case-c/scope.json"]),
    },
    subjects: subjectsOf(
      ["awf.subject.digest"],
      "version",
      "lapse",
      "An entry names one package. Another version has another digest and is another object.",
    ),
    basis: { statement: "The manager's own choice, usually after a defect report.", designation: true },
    time: { noticePeriod: 0, validity: "Until revoked", review: "not used" },
    dueProcess: { notice: "not used", objection: "not used", appeal: "not used", effectDuringObjection: "not used" },
  };
  d["case-c/binding.json"] = {
    awf: "1",
    kind: "binding",
    name: "The gateway serves partners that are neither barred nor sanctioned",
    adoption: { consumer: "The service contract", authority: "The account the service named as its adopter" },
    scopeDocument: documentHash(d["case-c/scope.json"]),
    role: "ACTOR",
    actions: [{ action: "awf.action.invoke", once: false, effect: "Proceeding serves the call. Refusing and deferring do not." }],
    lists: {
      allow: [{ list: "Partners (ALLOW, ENUMERATED)", follows: "latest" }],
      allowThreshold: 1,
      deny: [
        { list: "Barred (DENY, ENUMERATED)", follows: "latest" },
        { list: "Sanctioned accounts (DENY, COMMITTED)", follows: "latest", why: "The caller presents a proof of absence." },
      ],
      denyThreshold: 1,
    },
    rules: { onConflict: "DENY", onNoMatch: "DENY", onIndeterminate: "DEFER", onNotApplicable: "PROCEED" },
    standing: "The caller is the account.",
    updates: "Follows all three lists. Amended by the adopter.",
    workInProgress: "Every call is decided on its own. A call already served is not undone.",
  };
  d["case-c/binding-tools.json"] = {
    awf: "1",
    kind: "binding",
    name: "The gateway does not run excluded tool versions",
    adoption: { consumer: "The service contract", authority: "The account the service named as its adopter" },
    scopeDocument: documentHash(d["case-c/scope.json"]),
    role: "OBJECT",
    actions: [{ action: "awf.action.use-tool", once: false, effect: "Proceeding runs the tool. Refusing does not." }],
    lists: {
      allow: [],
      allowThreshold: 0,
      deny: [{ list: "Excluded tool versions (DENY, ENUMERATED)", follows: "latest" }],
      denyThreshold: 1,
    },
    rules: { onConflict: "DENY", onNoMatch: "ALLOW", onIndeterminate: "REFUSE", onNotApplicable: "PROCEED" },
    updates: "Follows the list. Amended by the adopter.",
    workInProgress: "Every use is decided on its own. Excluding a tool version says nothing about the agent that asked for it.",
  };
  return d;
}

// ------------------------------------------------------------------ example world

const exampleAddress = (label) => getAddress("0x" + keccak256(toUtf8Bytes("awf.example." + label)).slice(-40));

const EXAMPLE = {
  chainId: 1,
  registry: exampleAddress("registry"),
  guard: exampleAddress("guard"),
  identities: exampleAddress("identity registry"),
  evaluator: exampleAddress("evaluator"),
  relationSource: exampleAddress("relation source"),
  board: exampleAddress("task board"),
  swarm: exampleAddress("swarm membership"),
  service: exampleAddress("service"),
  manager: exampleAddress("manager"),
  issuer: exampleAddress("issuer"),
  alice: exampleAddress("alice"),
  bob: exampleAddress("bob"),
  carol: exampleAddress("carol"),
  sanctioned: exampleAddress("sanctioned account"),
  noticePeriod: 172800,
  schemeId: tag("scheme/delivery-capability/1"),
  contexts: {
    task: word(7),
    swarm: tag("swarm/alpha"),
    service: tag("service/inference-gateway"),
  },
};

const exampleDocuments = () => documents(EXAMPLE);

/** The assessment record of the first step of Case C, as a consumer would log it. */
function exampleAssessment(world) {
  const subject = accountRef(EXAMPLE.chainId, EXAMPLE.alice);
  return {
    awf: "1",
    kind: "assessment",
    chainId: EXAMPLE.chainId,
    guard: EXAMPLE.guard,
    bindingId: world.bindings.find((b) => b.name === "case-c/binding").id,
    bindingVersion: 1,
    subject: { ...subject, label: "alice" },
    presenter: EXAMPLE.alice,
    controller: EXAMPLE.alice,
    action: "awf.action.invoke",
    context: EXAMPLE.contexts.service,
    standing: "MATCH",
    allowSide: "MATCH",
    denySide: "NO_MATCH",
    outcome: "ALLOW",
    reason: "ALLOW_MATCH",
    disposition: "PROCEED",
    assessedAt: 1800000000,
    validUntil: 1800086399,
    stateDigest: world.digests[0].digest,
    findings: world.digests[0].lists.map((l, i) => ({
      listId: l.id,
      polarity: i === 0 ? "ALLOW" : "DENY",
      result: i === 0 ? "MATCH" : "NO_MATCH",
      reason: i === 0 ? "LISTED" : i === 1 ? "NOT_LISTED" : "SET_NON_MEMBER",
      revision: l.revision,
      stateHash: l.stateHash,
    })),
  };
}

/** Everything the examples identify, computed from the rules. */
function exampleWorld() {
  const docs = exampleDocuments();
  const h = (name) => documentHash(docs[name]);
  const { chainId, registry, guard, manager } = EXAMPLE;

  const subjects = [
    { label: "alice (account)", ref: accountRef(chainId, EXAMPLE.alice) },
    { label: "bob (account)", ref: accountRef(chainId, EXAMPLE.bob) },
    { label: "carol (account)", ref: accountRef(chainId, EXAMPLE.carol) },
    { label: "sanctioned account", ref: accountRef(chainId, EXAMPLE.sanctioned) },
    { label: "agent identity 1", ref: entryRef(chainId, EXAMPLE.identities, 1) },
    { label: "agent identity 2", ref: entryRef(chainId, EXAMPLE.identities, 2) },
    { label: "summarizer 2.0.1 package", ref: digestRef(tag("summarizer 2.0.1 package")) },
    { label: "summarizer 2.0.2 package", ref: digestRef(tag("summarizer 2.0.2 package")) },
    { label: "alice on another chain", ref: accountRef(10, EXAMPLE.alice) },
  ].map((s) => ({ ...s, key: subjectKey(s.ref) }));

  const scopes = [
    { name: "case-a/scope", scope: { anchor: EXAMPLE.board, context: EXAMPLE.contexts.task, documentHash: h("case-a/scope.json") } },
    { name: "case-b/scope", scope: { anchor: EXAMPLE.swarm, context: EXAMPLE.contexts.swarm, documentHash: h("case-b/scope.json") } },
    { name: "case-c/scope", scope: { anchor: EXAMPLE.service, context: EXAMPLE.contexts.service, documentHash: h("case-c/scope.json") } },
  ].map((s) => ({ ...s, id: scopeId(chainId, s.scope) }));
  const scopeOf = (name) => scopes.find((s) => s.name === name);

  const criteria = [
    {
      name: "case-a/criteria",
      criteria: {
        documentHash: h("case-a/criteria.json"),
        module: EXAMPLE.evaluator,
        moduleCodeHash: tag("example evaluator code"),
        moduleConfig: tag("example evaluator configuration"),
        rule: tag("example evaluator configuration"),
        fanout: 0,
      },
    },
    {
      name: "case-b/criteria-extension",
      criteria: {
        documentHash: h("case-b/criteria-extension.json"),
        module: EXAMPLE.relationSource,
        moduleCodeHash: tag("example relation source code"),
        moduleConfig: tag("example relation source configuration"),
        rule: tag("awf.relation.bound-anchor"),
        fanout: 1,
      },
    },
  ].map((c) => ({ ...c, id: criteriaId(chainId, c.criteria) }));
  const criteriaOf = (name) => criteria.find((c) => c.name === name).id;

  const listConfig = (polarity, mode, scopeName, more = {}) => ({
    polarity: POLARITY[polarity],
    mode: MODE[mode],
    scopeId: scopeOf(scopeName).id,
    criteriaId: ZERO32,
    noticePeriod: 0,
    source: ZERO32,
    sourcePin: ZERO32,
    salt: ZERO32,
    ...more,
  });
  const lists = [];
  const addList = (name, config) => {
    const id = listId(chainId, registry, manager, config);
    const state = { listId: id, revision: 1, manager, closed: false, criteriaId: config.criteriaId, setRoot: ZERO32, sourcePin: config.sourcePin, sourceState: ZERO32 };
    if (config.mode === MODE.DERIVED) state.sourceState = lists.find((l) => l.id === config.source).stateHash;
    lists.push({ name, creator: manager, config, id, revision: 1, stateHash: stateHash(state) });
    return id;
  };
  addList("case-a/list-qualified", listConfig("ALLOW", "PREDICATE", "case-a/scope", { criteriaId: criteriaOf("case-a/criteria"), salt: word(1) }));
  const barred = addList("case-b/list-barred", listConfig("DENY", "ENUMERATED", "case-b/scope", { noticePeriod: EXAMPLE.noticePeriod, salt: word(2) }));
  addList(
    "case-b/list-barred-anchors",
    listConfig("DENY", "DERIVED", "case-b/scope", { criteriaId: criteriaOf("case-b/criteria-extension"), source: barred, salt: word(3) }),
  );
  addList("case-c/list-partners", listConfig("ALLOW", "ENUMERATED", "case-c/scope", { salt: word(4) }));
  addList("case-c/list-barred", listConfig("DENY", "ENUMERATED", "case-c/scope", { salt: word(5) }));
  addList("case-c/list-sanctioned", listConfig("DENY", "COMMITTED", "case-c/scope", { salt: word(6) }));
  addList("case-c/list-excluded-tools", listConfig("DENY", "ENUMERATED", "case-c/scope", { salt: word(7) }));
  const list = (name) => lists.find((l) => l.name === name);
  const ref = (name) => ({ registry, listId: list(name).id, pin: ZERO32 });

  const action = (name, once = false) => ({ action: tag(name), once });
  const binding = (name, scopeName, documentName, more, salt = ZERO32) => {
    const config = {
      scope: scopeOf(scopeName).scope,
      role: ROLE.ACTOR,
      actions: [],
      allow: [],
      allowThreshold: 0,
      deny: [],
      denyThreshold: 0,
      onConflict: OUTCOME.DENY,
      onNoMatch: OUTCOME.DENY,
      onIndeterminate: DISPOSITION.DEFER,
      onNotApplicable: DISPOSITION.PROCEED,
      resolver: ZERO_ADDRESS,
      documentHash: h(documentName),
      ...more,
    };
    return {
      name,
      consumer: config.scope.anchor,
      scopeId: scopeOf(scopeName).id,
      salt,
      id: bindingId(chainId, guard, config.scope.anchor, scopeOf(scopeName).id, salt),
      encoded: encodeBinding(config),
      configHash: bindingConfigHash(config),
    };
  };
  const bindings = [
    binding("case-a/binding", "case-a/scope", "case-a/binding.json", {
      actions: [action("awf.action.bid")],
      allow: [ref("case-a/list-qualified")],
      allowThreshold: 1,
      onNotApplicable: DISPOSITION.REFUSE,
    }),
    binding("case-b/binding", "case-b/scope", "case-b/binding.json", {
      actions: [action("awf.action.join")],
      deny: [ref("case-b/list-barred")],
      denyThreshold: 1,
      onNoMatch: OUTCOME.ALLOW,
    }),
    binding("case-b/binding-extended", "case-b/scope", "case-b/binding-extended.json", {
      actions: [action("awf.action.join")],
      deny: [ref("case-b/list-barred"), ref("case-b/list-barred-anchors")],
      denyThreshold: 1,
      onNoMatch: OUTCOME.ALLOW,
    }),
    binding("case-c/binding", "case-c/scope", "case-c/binding.json", {
      actions: [action("awf.action.invoke")],
      allow: [ref("case-c/list-partners")],
      allowThreshold: 1,
      deny: [ref("case-c/list-barred"), ref("case-c/list-sanctioned")],
      denyThreshold: 1,
    }),
    binding("case-c/binding-tools", "case-c/scope", "case-c/binding-tools.json", {
      role: ROLE.OBJECT,
      actions: [action("awf.action.use-tool")],
      deny: [ref("case-c/list-excluded-tools")],
      denyThreshold: 1,
      onNoMatch: OUTCOME.ALLOW,
      onIndeterminate: DISPOSITION.REFUSE,
    }, word(1)), // a second binding of the same consumer and scope takes another salt
  ];

  const used = ["case-c/list-partners", "case-c/list-barred", "case-c/list-sanctioned"].map(list);
  const digests = [
    {
      name: "case-c/binding at version 1, lists at revision 1",
      bindingId: bindings[3].id,
      version: 1,
      lists: used.map((l) => ({ id: l.id, revision: l.revision, stateHash: l.stateHash })),
      digest: stateDigest(bindings[3].id, 1, used.map((l) => l.stateHash)),
    },
  ];

  return { docs, subjects, scopes, criteria, lists, bindings, digests };
}

function setVectors() {
  const key = (label) => subjectKey(accountRef(EXAMPLE.chainId, exampleAddress(label)));
  const members = ["sanctioned account", "set member 2", "set member 3", "set member 4", "set member 5"].map(key);
  const sorted = sortedSet(members);
  const loose = buildSet(members); // committed in the order given, without sentinels: membership only
  const cases = [];
  const add = (label, set, kind, k, evidence, expect, reason) =>
    cases.push({ label, root: set.root, kind: SET_KIND[kind], size: set.size, key: k, evidence, expect: MATCH[expect], reason: encodeBytes32String(reason) });

  const alice = key("alice");
  const inside = sorted.keys[3];
  add("a member of a sorted set", sorted, "SORTED", inside, memberProof(sorted, 3), "MATCH", "SET_MEMBER");
  add("a key absent from a sorted set", sorted, "SORTED", alice, absenceProof(sorted, alice), "NO_MATCH", "SET_NON_MEMBER");
  add("the proof of another key", sorted, "SORTED", alice, memberProof(sorted, 3), "UNDETERMINED", "PROOF_INVALID");
  add("an absence proof offered for a member", sorted, "SORTED", inside, absenceProofAt(sorted, 2), "UNDETERMINED", "PROOF_INVALID");
  add("a member of a membership-only set", loose, "MEMBERSHIP", members[1], memberProof(loose, 1), "MATCH", "SET_MEMBER");
  add("an absence proof against a membership-only set", sorted, "MEMBERSHIP", alice, absenceProof(sorted, alice), "UNDETERMINED", "NEGATIVE_UNSUPPORTED");
  add("a proof against an earlier root", sortedSet([...members, alice]), "SORTED", alice, absenceProof(sorted, alice), "UNDETERMINED", "PROOF_INVALID");
  return { leafTag: TAGS.SET_LEAF_TAG, sortedKeys: sorted.keys, sortedRoot: sorted.root, count: cases.length, cases };

  function absenceProofAt(set, low) {
    return encodeProof({ member: false, index: low, path: pathOf(set, low), lowKey: set.keys[low], highKey: set.keys[low + 1], highPath: pathOf(set, low + 1) });
  }
}

function outcomeVectors() {
  const rows = { allowSide: [], denySide: [], onConflict: [], onNoMatch: [], outcome: [] };
  for (const onConflict of [OUTCOME.ALLOW, OUTCOME.DENY, OUTCOME.INDETERMINATE]) {
    for (const onNoMatch of [OUTCOME.ALLOW, OUTCOME.DENY, OUTCOME.NOT_APPLICABLE]) {
      for (const a of [0, 1, 2]) {
        for (const d of [0, 1, 2]) {
          rows.allowSide.push(a);
          rows.denySide.push(d);
          rows.onConflict.push(onConflict);
          rows.onNoMatch.push(onNoMatch);
          rows.outcome.push(combine(a, d, onConflict, onNoMatch));
        }
      }
    }
  }
  const thresholds = { first: [], second: [], third: [], threshold: [], side: [] };
  for (let t = 1; t <= 3; t += 1) {
    for (let n = 0; n < 27; n += 1) {
      const r = [n % 3, Math.floor(n / 3) % 3, Math.floor(n / 9)];
      thresholds.first.push(r[0]);
      thresholds.second.push(r[1]);
      thresholds.third.push(r[2]);
      thresholds.threshold.push(t);
      thresholds.side.push(side(r, t));
    }
  }
  return { enums: { match: MATCH, outcome: OUTCOME }, count: rows.outcome.length, ...rows, thresholdCount: thresholds.side.length, thresholds };
}

function interfaceVectors() {
  const out = {};
  for (const name of ["IAWFRegistry", "IAWFGuard", "IAWFEvaluator", "IAWFRelationSource", "IAWFSubjectResolver"]) {
    const file = path.join(ROOT, "out", `${name}.sol`, `${name}.json`);
    if (!fs.existsSync(file)) throw new Error(`${file} is missing; run forge build first`);
    const selectors = JSON.parse(fs.readFileSync(file, "utf8")).methodIdentifiers;
    let id = 0n;
    for (const selector of Object.values(selectors)) id ^= BigInt("0x" + selector);
    out[name] = {
      interfaceId: "0x" + id.toString(16).padStart(8, "0"),
      functions: Object.fromEntries(Object.entries(selectors).sort().map(([sig, sel]) => [sig, "0x" + sel])),
    };
  }
  return out;
}

function buildVectors() {
  const world = exampleWorld();
  const named = (names) => Object.fromEntries(names.map((n) => [n, tag(n)]));
  return {
    "constants.json": {
      tags: TAGS,
      subjectKinds: named(KIND_NAMES),
      actions: named(ACTION_NAMES),
      relations: named(RELATION_NAMES),
      enums: { polarity: POLARITY, mode: MODE, match: MATCH, outcome: OUTCOME, disposition: DISPOSITION, setKind: SET_KIND, role: ROLE },
      reasons: Object.fromEntries(REASONS.map((r) => [r, encodeBytes32String(r)])),
    },
    "identifiers.json": {
      note: "Identifiers of the worked cases on an example chain with example addresses.",
      chainId: EXAMPLE.chainId,
      registry: EXAMPLE.registry,
      guard: EXAMPLE.guard,
      accounts: {
        manager: EXAMPLE.manager,
        issuer: EXAMPLE.issuer,
        alice: EXAMPLE.alice,
        bob: EXAMPLE.bob,
        carol: EXAMPLE.carol,
        sanctioned: EXAMPLE.sanctioned,
        identityRegistry: EXAMPLE.identities,
        taskBoard: EXAMPLE.board,
        swarmMembership: EXAMPLE.swarm,
        service: EXAMPLE.service,
      },
      documents: Object.fromEntries(Object.entries(world.docs).map(([name, doc]) => [name, documentHash(doc)])),
      subjectKeys: world.subjects.map((s) => s.key),
      scopeIds: world.scopes.map((s) => s.id),
      criteriaIds: world.criteria.map((c) => c.id),
      listIds: world.lists.map((l) => l.id),
      bindingIds: world.bindings.map((b) => b.id),
      subjects: world.subjects,
      scopes: world.scopes,
      criteria: world.criteria,
      lists: world.lists,
      bindings: world.bindings,
      digests: world.digests,
    },
    "sets.json": setVectors(),
    "outcomes.json": outcomeVectors(),
    "interfaces.json": interfaceVectors(),
  };
}

// ------------------------------------------------------------------ files

const pretty = (value) => JSON.stringify(value, null, 2) + "\n";

function exampleFiles() {
  const world = exampleWorld();
  const files = {};
  for (const [name, doc] of Object.entries(world.docs)) files[name] = pretty(doc);
  files["assessment.json"] = pretty(exampleAssessment(world));
  return files;
}

function writeAll(dir, files) {
  for (const [name, text] of Object.entries(files)) {
    const target = path.join(dir, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, text);
  }
}

function validator() {
  const ajv = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true });
  const dir = path.join(ASSETS, "schemas");
  const schemas = {};
  for (const file of fs.readdirSync(dir).filter((f) => f.endsWith(".schema.json"))) {
    schemas[file] = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
    ajv.addSchema(schemas[file], file);
  }
  return (kind, doc, label) => {
    const validate = ajv.getSchema(`awf-${kind}.schema.json`);
    if (!validate) throw new Error(`no schema for kind ${kind}`);
    if (!validate(doc)) throw new Error(`${label}: ${ajv.errorsText(validate.errors)}`);
  };
}

function check() {
  const validate = validator();
  let problems = 0;
  const fail = (message) => {
    problems += 1;
    console.log("FAIL " + message);
  };

  const examples = exampleFiles();
  for (const [name, text] of Object.entries(examples)) {
    const file = path.join(ASSETS, "examples", name);
    if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") !== text) fail(`examples/${name} is not what the tool produces`);
    const doc = JSON.parse(text);
    try {
      validate(doc.kind, doc, name);
    } catch (error) {
      fail(error.message);
    }
  }
  const onDisk = walk(path.join(ASSETS, "examples"));
  for (const name of onDisk) if (!(name in examples)) fail(`examples/${name} is not produced by the tool`);

  // The vocabulary is a plain document; its names must be well formed and unique.
  const vocabulary = JSON.parse(fs.readFileSync(path.join(ASSETS, "schemas", "awf-dimensions.json"), "utf8"));
  const names = vocabulary.dimensions.map((d) => d.name);
  if (new Set(names).size !== names.length) fail("the dimension vocabulary repeats a name");
  for (const doc of Object.values(exampleWorld().docs)) {
    for (const rule of doc.dimensions ?? []) if (!names.includes(rule.dimension)) fail(`unknown dimension ${rule.dimension}`);
    for (const item of doc.evidence ?? []) if (!names.includes(item.dimension)) fail(`unknown dimension ${item.dimension}`);
  }

  const vectors = buildVectors();
  for (const [name, value] of Object.entries(vectors)) {
    const file = path.join(ASSETS, "vectors", name);
    if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") !== pretty(value)) fail(`vectors/${name} is not what the tool produces`);
  }

  // A document must hash the same however its keys are ordered.
  const sample = exampleWorld().docs["case-a/criteria.json"];
  const shuffled = Object.fromEntries(Object.entries(sample).reverse());
  if (documentHash(sample) !== documentHash(shuffled)) fail("the canonical form depends on key order");

  if (problems) process.exit(1);
  console.log(`check passed: ${Object.keys(examples).length} example documents, ${Object.keys(vectors).length} vector files`);
}

function walk(dir, prefix = "") {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) out.push(...walk(path.join(dir, entry.name), prefix + entry.name + "/"));
    else out.push(prefix + entry.name);
  }
  return out;
}

// ------------------------------------------------------------------ plan of an evidence run

const ACTORS = ["manager", "issuer", "alice", "bob", "carol", "operator", "mallory"];
const CHAINS = { anvil: 31337, sepolia: 11155111 };
const RECORD_BASE = {
  anvil: "file://deployments/anvil/documents/",
  sepolia: "https://raw.githubusercontent.com/garyyang-finchip/agent-whitelist-framework/main/deployments/sepolia/documents/",
};

function plan(network) {
  const chainId = CHAINS[network];
  if (!chainId) throw new Error("network is anvil or sepolia");
  const deployerPk = process.env.DEPLOYER_PK;
  if (!deployerPk) throw new Error("set DEPLOYER_PK");
  const deployer = new Wallet(deployerPk).address;
  const actors = {};
  for (const label of ACTORS) {
    actors[label] = new Wallet(keccak256(solidityPacked(["uint256", "string"], [deployerPk, label]))).address;
  }

  const noticePeriod = 120;
  const schemeId = tag("scheme/delivery-capability/1");
  const docs = documents({ chainId, manager: actors.manager, issuer: actors.issuer, noticePeriod, schemeId });
  const validate = validator();
  for (const [name, doc] of Object.entries(docs)) validate(doc.kind, doc, name);

  const account = (label) => accountRef(chainId, actors[label]);
  const sanctionedAccount = getAddress("0x" + keccak256(toUtf8Bytes("awf.evidence.sanctioned account")).slice(-40));
  const set = sortedSet([subjectKey(accountRef(chainId, sanctionedAccount))]);
  const grown = sortedSet([subjectKey(accountRef(chainId, sanctionedAccount)), subjectKey(account("alice"))]);
  const proofs = {};
  for (const label of ["alice", "bob", "carol"]) proofs[label] = absenceProof(set, subjectKey(account(label)));

  const out = {
    network,
    chainId,
    deployer,
    actors,
    parameters: {
      noticePeriod,
      credentialLifetime: 240,
      wait: 300,
      schemeId,
      minLevel: 2,
      minAccepted: 2,
      window: 7776000,
    },
    contexts: { task: word(7), swarm: tag("swarm/alpha"), service: tag("service/inference-gateway") },
    actions: Object.fromEntries(ACTION_NAMES.map((n) => [n.split(".").pop().replace("-", "_"), tag(n)])),
    recordBase: RECORD_BASE[network],
    documents: Object.fromEntries(Object.keys(docs).map((name) => [name.replace(/[/.-]/g, "_"), documentHash(docs[name])])),
    documentFiles: Object.keys(docs),
    set: {
      sanctionedAccount,
      size: set.size,
      root: set.root,
      proofAlice: proofs.alice,
      proofBob: proofs.bob,
      proofCarol: proofs.carol,
      grownSize: grown.size,
      grownRoot: grown.root,
      grownMemberProofAlice: memberProof(grown, grown.keys.indexOf(subjectKey(account("alice")))),
    },
    tools: {
      excluded: tag("summarizer 2.0.1 package"),
      current: tag("summarizer 2.0.2 package"),
    },
  };
  const dir = path.join(ROOT, "deployments", network);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "plan.json"), pretty(out));
  fs.rmSync(path.join(dir, "documents"), { recursive: true, force: true });
  // Documents are stored in canonical form, so that the bytes at the recorded location are the bytes hashed.
  writeAll(path.join(dir, "documents"), Object.fromEntries(Object.entries(docs).map(([name, doc]) => [name, canonical(doc)])));
  console.log(`wrote deployments/${network}/plan.json and ${Object.keys(docs).length} documents; deployer ${deployer}`);
}

// ------------------------------------------------------------------ command line

const command = process.argv[2];
if (command === "examples") {
  fs.rmSync(path.join(ASSETS, "examples"), { recursive: true, force: true });
  writeAll(path.join(ASSETS, "examples"), exampleFiles());
  console.log("examples written");
} else if (command === "vectors") {
  writeAll(path.join(ASSETS, "vectors"), Object.fromEntries(Object.entries(buildVectors()).map(([n, v]) => [n, pretty(v)])));
  console.log("vectors written");
} else if (command === "check") {
  check();
} else if (command === "plan") {
  plan(process.argv[3]);
} else if (command !== undefined || process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log("usage: node awf.mjs examples | vectors | check | plan <anvil|sepolia>");
  process.exit(command ? 1 : 0);
}
