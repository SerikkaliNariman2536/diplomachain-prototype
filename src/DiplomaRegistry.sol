// SPDX-License-Identifier: MIT
// Educational project for the course Introduction to Finance.
// Not a real product, service or investment offer. Do not use with real funds.
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title DiplomaRegistry - prototype of the DiplomaChain verification layer
/// @notice Universities record one Merkle root per graduation batch. Anyone can check
///         for free whether a diploma (its salted SHA-256 hash) belongs to a batch and
///         has not been revoked. No personal data is ever stored on-chain.
contract DiplomaRegistry is AccessControl, Pausable {
    /// @notice Role of an approved university or course provider key.
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    /// @notice Result of a verification.
    enum Status {
        INVALID, // unknown batch or the document is not part of the batch
        VALID, // the document is part of the batch and not revoked
        REVOKED // the document was part of the batch but the issuer revoked it
    }

    struct Batch {
        bytes32 root; // Merkle root of all document hashes in the batch
        address issuer; // university key that recorded the batch
        uint64 issuedAt; // block timestamp, cannot be backdated
    }

    Batch[] private _batches; // batchId = index in this array
    mapping(uint256 batchId => mapping(bytes32 docHash => bool)) private _revoked;

    event IssuerAdded(address indexed issuer, address indexed admin);
    event IssuerRemoved(address indexed issuer, address indexed admin);
    event BatchIssued(uint256 indexed batchId, address indexed issuer, bytes32 root, uint64 issuedAt);
    event DocumentRevoked(uint256 indexed batchId, bytes32 indexed docHash, address indexed issuer);

    error EmptyRoot();
    error UnknownBatch(uint256 batchId);
    error NotBatchIssuer(uint256 batchId, address caller);
    error NotInBatch(uint256 batchId, bytes32 docHash);
    error AlreadyRevoked(uint256 batchId, bytes32 docHash);

    /// @param admin DiplomaChain admin. In production this would be a 2-of-3 multisignature wallet.
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ----------------------------------------------------------------- admin

    /// @notice Approves a university key. Only the DiplomaChain admin can do this.
    function addIssuer(address issuer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(ISSUER_ROLE, issuer);
        emit IssuerAdded(issuer, msg.sender);
    }

    /// @notice Removes a university key (for example after it was lost or leaked).
    ///         Batches recorded earlier stay valid; a new key is added with addIssuer.
    function removeIssuer(address issuer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ISSUER_ROLE, issuer);
        emit IssuerRemoved(issuer, msg.sender);
    }

    /// @notice Emergency stop for new batches. Verification keeps working.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ---------------------------------------------------------------- issuer

    /// @notice Records the Merkle root of a graduation batch: one transaction for the whole batch.
    /// @return batchId identifier the graduates keep together with their Merkle proof
    function issueBatch(bytes32 root) external onlyRole(ISSUER_ROLE) whenNotPaused returns (uint256 batchId) {
        if (root == bytes32(0)) revert EmptyRoot();
        batchId = _batches.length;
        uint64 ts = uint64(block.timestamp);
        _batches.push(Batch({root: root, issuer: msg.sender, issuedAt: ts}));
        emit BatchIssued(batchId, msg.sender, root, ts);
    }

    /// @notice Revokes one document (error, annulment). Only the university that issued the
    ///         batch can do this, and it must prove that the document is part of the batch.
    function revoke(uint256 batchId, bytes32 docHash, bytes32[] calldata proof) external onlyRole(ISSUER_ROLE) {
        Batch storage b = _batch(batchId);
        if (b.issuer != msg.sender) revert NotBatchIssuer(batchId, msg.sender);
        if (!MerkleProof.verifyCalldata(proof, b.root, leaf(docHash))) revert NotInBatch(batchId, docHash);
        if (_revoked[batchId][docHash]) revert AlreadyRevoked(batchId, docHash);
        _revoked[batchId][docHash] = true;
        emit DocumentRevoked(batchId, docHash, msg.sender);
    }

    // ---------------------------------------------------------------- anyone

    /// @notice Free, read-only check used by employers and foreign universities.
    function verify(uint256 batchId, bytes32 docHash, bytes32[] calldata proof) external view returns (Status) {
        if (batchId >= _batches.length) return Status.INVALID;
        if (!MerkleProof.verifyCalldata(proof, _batches[batchId].root, leaf(docHash))) return Status.INVALID;
        if (_revoked[batchId][docHash]) return Status.REVOKED;
        return Status.VALID;
    }

    /// @notice Batch details: root, issuing key and timestamp.
    function getBatch(uint256 batchId) external view returns (Batch memory) {
        return _batch(batchId);
    }

    function batchCount() external view returns (uint256) {
        return _batches.length;
    }

    /// @notice Merkle leaf of a document hash. Hashing twice prevents second-preimage attacks.
    function leaf(bytes32 docHash) public pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(docHash))));
    }

    function _batch(uint256 batchId) private view returns (Batch storage) {
        if (batchId >= _batches.length) revert UnknownBatch(batchId);
        return _batches[batchId];
    }
}
