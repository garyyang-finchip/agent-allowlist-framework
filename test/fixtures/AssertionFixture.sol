// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAssertionSource} from "../../assets/erc-8507/contracts/adapters/AAFCredentialHistoryEvaluator.sol";

interface IOwnerOf {
    function ownerOf(uint256 id) external view returns (address);
}

/// @dev Stand-in for an assertion registry. It keeps one assertion per subject, scheme and issuer
/// and resolves them the way the example evaluator expects of a registry: an assertion counts
/// while it is not revoked, not expired and, when it was bound to the subject's controller, while
/// that controller is unchanged.
contract AssertionFixture is IAssertionSource {
    struct Assertion {
        uint8 level;
        uint64 expiresAt;
        bool revoked;
        address controller; // zero: bound to the identity itself
        bytes32 id;
    }

    bool public unavailable;
    uint256 private _count;
    mapping(bytes32 => mapping(bytes32 => mapping(address => Assertion))) private _assertions;

    /// @dev The caller is the issuer. With `bindController`, the assertion holds only while the
    /// subject's current owner stays the same.
    function attest(Subject calldata subject, bytes32 schemeId, uint8 level, uint64 expiresAt, bool bindController)
        external
        returns (bytes32 id)
    {
        address controller;
        if (bindController) controller = _ownerOf(subject);
        id = keccak256(abi.encode(address(this), ++_count));
        _assertions[_key(subject)][schemeId][msg.sender] = Assertion(level, expiresAt, false, controller, id);
    }

    function revoke(Subject calldata subject, bytes32 schemeId) external {
        _assertions[_key(subject)][schemeId][msg.sender].revoked = true;
    }

    function setUnavailable(bool value) external {
        unavailable = value;
    }

    function resolve(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)
        external
        view
        returns (uint8 level, uint64 expiresAt, bytes32 assertionId)
    {
        require(!unavailable, "unavailable");
        bytes32 key = _key(subject);
        for (uint256 i; i < issuers.length; ++i) {
            Assertion storage a = _assertions[key][schemeId][issuers[i]];
            if (a.id == bytes32(0) || a.revoked) continue;
            if (a.expiresAt != 0 && block.timestamp >= a.expiresAt) continue;
            if (a.controller != address(0) && _ownerOf(subject) != a.controller) continue;
            if (a.level > level) (level, expiresAt, assertionId) = (a.level, a.expiresAt, a.id);
        }
    }

    function _key(Subject calldata subject) private pure returns (bytes32) {
        return keccak256(abi.encode(subject.subjectType, subject.subjectData));
    }

    function _ownerOf(Subject calldata subject) private view returns (address) {
        (, address registry, uint256 id) = abi.decode(subject.subjectData, (uint256, address, uint256));
        return IOwnerOf(registry).ownerOf(id);
    }
}
