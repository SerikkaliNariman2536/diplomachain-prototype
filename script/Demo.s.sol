// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DiplomaRegistry} from "../src/DiplomaRegistry.sol";
import {MerkleHelper} from "./MerkleHelper.sol";

/// @notice Step-by-step demo of the main use case on a LOCAL Anvil network.
///         Uses the unlocked test accounts that Anvil creates; no private keys are needed.
///         Run:  anvil --quiet   (terminal 1)
///               forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --unlocked
///                 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266          (terminal 2)
contract Demo is Script {
    // Default Anvil test accounts (local network only, hold only test ETH)
    address constant ADMIN = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // DiplomaChain admin
    address constant UNIVERSITY = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // university key
    address constant STRANGER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // not approved

    function _status(DiplomaRegistry.Status s) internal pure returns (string memory) {
        if (s == DiplomaRegistry.Status.VALID) return "VALID";
        if (s == DiplomaRegistry.Status.REVOKED) return "REVOKED";
        return "INVALID";
    }

    function run() external {
        console.log("=== DiplomaChain prototype demo (local Anvil network, invented test data) ===");

        // Step 1. Deploy
        vm.startBroadcast(ADMIN);
        DiplomaRegistry registry = new DiplomaRegistry(ADMIN);
        console.log("1. Contract deployed at:", address(registry));

        // Step 2. Admin approves the university key
        registry.addIssuer(UNIVERSITY);
        console.log("2. Admin approved university key:", UNIVERSITY);
        vm.stopBroadcast();

        // Step 3. Off-chain: the university back-end hashes 4 diplomas and builds the Merkle tree
        bytes32 salt = keccak256("demo-salt");
        bytes32[4] memory docs;
        docs[0] = MerkleHelper.docHash(salt, '{"student":"Student A","degree":"BSc Software Engineering","year":2027}');
        docs[1] = MerkleHelper.docHash(salt, '{"student":"Student B","degree":"BSc Cybersecurity","year":2027}');
        docs[2] = MerkleHelper.docHash(salt, '{"student":"Student C","degree":"BSc Big Data","year":2027}');
        docs[3] = MerkleHelper.docHash(salt, '{"student":"Student D","degree":"MSc Computer Science","year":2027}');
        bytes32 root = MerkleHelper.root4(docs);
        console.log("3. Off-chain: 4 diplomas hashed, Merkle root:");
        console.logBytes32(root);

        // Step 4. The university records ONE transaction for the whole batch
        vm.startBroadcast(UNIVERSITY);
        uint256 batchId = registry.issueBatch(root);
        vm.stopBroadcast();
        console.log("4. University recorded batch id:", batchId);

        // Step 5. An employer verifies Student A's diploma (free read-only call)
        bytes32[] memory proofA = MerkleHelper.proof4(docs, 0);
        console.log(
            "5. Employer checks genuine diploma of Student A ->", _status(registry.verify(batchId, docs[0], proofA))
        );

        // Step 6. Someone changes one word in the diploma (BSc -> MSc)
        bytes32 tampered =
            MerkleHelper.docHash(salt, '{"student":"Student A","degree":"MSc Software Engineering","year":2027}');
        console.log(
            "6. Employer checks tampered diploma (BSc -> MSc) ->", _status(registry.verify(batchId, tampered, proofA))
        );

        // Step 7. The university revokes Student C's diploma (for example, issued by mistake)
        bytes32[] memory proofC = MerkleHelper.proof4(docs, 2);
        vm.startBroadcast(UNIVERSITY);
        registry.revoke(batchId, docs[2], proofC);
        vm.stopBroadcast();
        console.log("7. University revoked Student C -> check now:", _status(registry.verify(batchId, docs[2], proofC)));

        // Step 8. An unapproved account tries to record a fake batch (simulated, not broadcast)
        vm.prank(STRANGER);
        try registry.issueBatch(keccak256("fake batch")) {
            console.log("8. Stranger recorded a batch (should not happen!)");
        } catch {
            console.log("8. Stranger tried to record a fake batch -> REJECTED (access control)");
        }
        console.log("=== Demo finished ===");
    }
}
