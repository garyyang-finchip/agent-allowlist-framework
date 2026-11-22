// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Stand-in for an agent identity registry: the ERC-721 surface a guard reads to establish
/// standing, plus the agent wallet. Not a conforming implementation of anything.
contract IdentityFixture {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    uint256 public nextId = 1;
    mapping(uint256 => address) private _owner;
    mapping(uint256 => address) private _wallet;
    mapping(uint256 => address) private _approved;
    mapping(address => mapping(address => bool)) private _operators;

    function register() external returns (uint256 agentId) {
        agentId = nextId++;
        _owner[agentId] = msg.sender;
        emit Transfer(address(0), msg.sender, agentId);
    }

    function ownerOf(uint256 agentId) public view returns (address owner) {
        owner = _owner[agentId];
        require(owner != address(0), "unknown id");
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _wallet[agentId];
    }

    function setAgentWallet(uint256 agentId, address wallet) external {
        require(ownerOf(agentId) == msg.sender, "not owner");
        _wallet[agentId] = wallet;
    }

    function approve(address to, uint256 agentId) external {
        require(ownerOf(agentId) == msg.sender, "not owner");
        _approved[agentId] = to;
    }

    function getApproved(uint256 agentId) external view returns (address) {
        ownerOf(agentId);
        return _approved[agentId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operators[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operators[owner][operator];
    }

    /// @dev A transfer clears the wallet and the single approval.
    function transferFrom(address from, address to, uint256 agentId) external {
        require(ownerOf(agentId) == from && from == msg.sender && to != address(0), "not owner");
        _owner[agentId] = to;
        delete _wallet[agentId];
        delete _approved[agentId];
        emit Transfer(from, to, agentId);
    }
}
