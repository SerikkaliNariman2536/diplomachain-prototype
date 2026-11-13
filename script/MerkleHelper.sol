// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Off-chain helper used by the tests and the demo script. It plays the role of the
///         DiplomaChain back-end: it hashes diploma files and builds the Merkle tree of a batch.
///         Leaves and pairs are hashed exactly like OpenZeppelin MerkleProof expects
///         (double-hashed leaves, pairs sorted before hashing).
library MerkleHelper {
    /// @dev Salted SHA-256 hash of a diploma file (the file itself stays off-chain).
    function docHash(bytes32 salt, string memory diplomaJson) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(salt, diplomaJson));
    }

    function leaf(bytes32 h) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(h))));
    }

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @notice Merkle root of 4 document hashes (enough for the prototype).
    function root4(bytes32[4] memory h) internal pure returns (bytes32) {
        bytes32 l0 = hashPair(leaf(h[0]), leaf(h[1]));
        bytes32 l1 = hashPair(leaf(h[2]), leaf(h[3]));
        return hashPair(l0, l1);
    }

    /// @notice Merkle proof for document i (0..3) of a 4-document batch.
    function proof4(bytes32[4] memory h, uint256 i) internal pure returns (bytes32[] memory p) {
        p = new bytes32[](2);
        uint256 sibling = i ^ 1; // neighbour in the same pair
        p[0] = leaf(h[sibling]);
        p[1] = i < 2 ? hashPair(leaf(h[2]), leaf(h[3])) : hashPair(leaf(h[0]), leaf(h[1]));
    }
}
