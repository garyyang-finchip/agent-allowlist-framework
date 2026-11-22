// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ITaskLedger} from "../../assets/erc-8507/contracts/adapters/AAFCredentialHistoryEvaluator.sol";

/// @dev Stand-in for a task ledger: submissions are written directly, with their status.
contract TaskLedgerFixture is ITaskLedger {
    bool public unavailable;
    mapping(uint256 => mapping(uint256 => Submission)) private _submissions;

    /// @dev Records a submission made now by the caller. Status: 0 pending, 1 accepted, 2 rejected.
    function record(uint256 tokenId, uint256 submissionId, uint8 status) external {
        _submissions[tokenId][submissionId] = Submission({
            fulfiller: msg.sender,
            resultHash: keccak256(abi.encode(tokenId, submissionId)),
            taskVersion: 1,
            submittedAt: uint64(block.timestamp),
            machineSettled: false,
            status: status
        });
    }

    function setUnavailable(bool value) external {
        unavailable = value;
    }

    function submissionOf(uint256 tokenId, uint256 submissionId) external view returns (Submission memory) {
        require(!unavailable, "unavailable");
        return _submissions[tokenId][submissionId];
    }
}
