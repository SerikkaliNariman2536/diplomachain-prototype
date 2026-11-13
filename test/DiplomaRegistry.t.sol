// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {DiplomaRegistry} from "../src/DiplomaRegistry.sol";
import {MerkleHelper} from "../script/MerkleHelper.sol";

/// @notice Unit tests of DiplomaRegistry. All data is invented test data; no real people.
contract DiplomaRegistryTest is Test {
    DiplomaRegistry registry;

    address admin = makeAddr("admin"); // DiplomaChain admin (multisig in production)
    address uniA = makeAddr("universityA"); // approved issuer
    address uniB = makeAddr("universityB"); // another approved issuer
    address stranger = makeAddr("stranger"); // not approved
    address employer = makeAddr("employer"); // verifier

    bytes32[4] docs; // salted SHA-256 hashes of 4 invented diplomas
    bytes32 root;

    function setUp() public {
        registry = new DiplomaRegistry(admin);
        bytes32 salt = keccak256("test-salt");
        docs[0] = MerkleHelper.docHash(salt, '{"student":"Student A","degree":"BSc Software Engineering","year":2027}');
        docs[1] = MerkleHelper.docHash(salt, '{"student":"Student B","degree":"BSc Cybersecurity","year":2027}');
        docs[2] = MerkleHelper.docHash(salt, '{"student":"Student C","degree":"BSc Big Data","year":2027}');
        docs[3] = MerkleHelper.docHash(salt, '{"student":"Student D","degree":"MSc Computer Science","year":2027}');
        root = MerkleHelper.root4(docs);

        vm.startPrank(admin);
        registry.addIssuer(uniA);
        registry.addIssuer(uniB);
        vm.stopPrank();
    }

    function _issueByA() internal returns (uint256) {
        vm.prank(uniA);
        return registry.issueBatch(root);
    }

    // 1. Access control: the admin can approve a university key
    function test_AdminCanAddIssuer() public {
        address uniC = makeAddr("universityC");
        vm.prank(admin);
        registry.addIssuer(uniC);
        assertTrue(registry.hasRole(registry.ISSUER_ROLE(), uniC));
    }

    // 2. Access control: nobody else can approve a key
    function test_RevertWhen_NonAdminAddsIssuer() public {
        bytes32 adminRole = registry.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, adminRole)
        );
        vm.prank(stranger);
        registry.addIssuer(stranger);
    }

    // 3. An approved university records a batch; root, issuer and time are stored and an event is emitted
    function test_IssuerRecordsBatch() public {
        vm.warp(1_800_000_000);
        vm.expectEmit(true, true, false, true);
        emit DiplomaRegistry.BatchIssued(0, uniA, root, 1_800_000_000);
        uint256 id = _issueByA();

        DiplomaRegistry.Batch memory b = registry.getBatch(id);
        assertEq(id, 0);
        assertEq(b.root, root);
        assertEq(b.issuer, uniA);
        assertEq(b.issuedAt, 1_800_000_000);
        assertEq(registry.batchCount(), 1);
    }

    // 4. Access control: an unapproved account cannot record diplomas
    function test_RevertWhen_StrangerIssuesBatch() public {
        bytes32 issuerRole = registry.ISSUER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, issuerRole)
        );
        vm.prank(stranger);
        registry.issueBatch(root);
    }

    // 5. Every genuine diploma of the batch is VALID
    function test_VerifyGenuineDiplomas() public {
        uint256 id = _issueByA();
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(employer); // a view call, free for the verifier
            assertEq(
                uint256(registry.verify(id, docs[i], MerkleHelper.proof4(docs, i))),
                uint256(DiplomaRegistry.Status.VALID)
            );
        }
    }

    // 6. A diploma changed by one character, a wrong batch or a wrong proof is INVALID
    function test_TamperedDiplomaIsInvalid() public {
        uint256 id = _issueByA();
        bytes32 tampered = MerkleHelper.docHash(
            keccak256("test-salt"), '{"student":"Student A","degree":"MSc Software Engineering","year":2027}'
        );
        bytes32[] memory p0 = MerkleHelper.proof4(docs, 0);
        assertEq(uint256(registry.verify(id, tampered, p0)), uint256(DiplomaRegistry.Status.INVALID));
        assertEq(uint256(registry.verify(id, docs[1], p0)), uint256(DiplomaRegistry.Status.INVALID)); // wrong proof
        assertEq(uint256(registry.verify(99, docs[0], p0)), uint256(DiplomaRegistry.Status.INVALID)); // unknown batch
    }

    // 7. After revocation the diploma is REVOKED, the others stay VALID
    function test_RevokedDiplomaFailsVerification() public {
        uint256 id = _issueByA();
        bytes32[] memory p2 = MerkleHelper.proof4(docs, 2);
        vm.prank(uniA);
        registry.revoke(id, docs[2], p2);
        assertEq(uint256(registry.verify(id, docs[2], p2)), uint256(DiplomaRegistry.Status.REVOKED));
        assertEq(
            uint256(registry.verify(id, docs[3], MerkleHelper.proof4(docs, 3))), uint256(DiplomaRegistry.Status.VALID)
        );
    }

    // 8. Another university cannot revoke a diploma it did not issue
    function test_RevertWhen_OtherUniversityRevokes() public {
        uint256 id = _issueByA();
        bytes32[] memory p0 = MerkleHelper.proof4(docs, 0);
        vm.expectRevert(abi.encodeWithSelector(DiplomaRegistry.NotBatchIssuer.selector, id, uniB));
        vm.prank(uniB);
        registry.revoke(id, docs[0], p0);
    }

    // 9. Key loss: a removed key cannot issue, but diplomas it issued before stay VALID
    function test_RemovedIssuerCannotIssue_OldDiplomasStayValid() public {
        uint256 id = _issueByA();
        vm.prank(admin);
        registry.removeIssuer(uniA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, uniA, registry.ISSUER_ROLE()
            )
        );
        vm.prank(uniA);
        registry.issueBatch(keccak256("new batch"));

        assertEq(
            uint256(registry.verify(id, docs[0], MerkleHelper.proof4(docs, 0))), uint256(DiplomaRegistry.Status.VALID)
        );
    }

    // 10. Emergency pause stops new batches but verification keeps working
    function test_PauseStopsIssuanceButNotVerification() public {
        uint256 id = _issueByA();
        vm.prank(admin);
        registry.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(uniA);
        registry.issueBatch(keccak256("another batch"));

        assertEq(
            uint256(registry.verify(id, docs[1], MerkleHelper.proof4(docs, 1))), uint256(DiplomaRegistry.Status.VALID)
        );
    }

    // 11. Input validation: an empty root and a double revocation are rejected
    function test_RevertWhen_EmptyRootOrDoubleRevoke() public {
        vm.expectRevert(DiplomaRegistry.EmptyRoot.selector);
        vm.prank(uniA);
        registry.issueBatch(bytes32(0));

        uint256 id = _issueByA();
        bytes32[] memory p0 = MerkleHelper.proof4(docs, 0);
        vm.prank(uniA);
        registry.revoke(id, docs[0], p0);
        vm.expectRevert(abi.encodeWithSelector(DiplomaRegistry.AlreadyRevoked.selector, id, docs[0]));
        vm.prank(uniA);
        registry.revoke(id, docs[0], p0);
    }

    // 12. Fuzz test: a random hash is never accepted as a diploma of the batch
    function testFuzz_RandomHashIsNeverValid(bytes32 randomHash) public {
        vm.assume(randomHash != docs[0] && randomHash != docs[1] && randomHash != docs[2] && randomHash != docs[3]);
        uint256 id = _issueByA();
        for (uint256 i = 0; i < 4; i++) {
            assertEq(
                uint256(registry.verify(id, randomHash, MerkleHelper.proof4(docs, i))),
                uint256(DiplomaRegistry.Status.INVALID)
            );
        }
    }
}
