Educational project for the course Introduction to Finance. Not a real product, service or investment offer. Do not use with real funds.

# DiplomaChain — smart contract prototype

Team 05, Final Project, Introduction to Finance (2026–2027).

**Demo video:** link will be added here after upload to OneDrive.

## What the prototype does

DiplomaChain lets universities record tamper-evident diplomas on a blockchain and lets anyone (an employer, a foreign university) check a diploma for free.

- A university hashes each diploma file off-chain (salted SHA-256) and combines the hashes of one graduation batch into a Merkle tree.
- The `DiplomaRegistry` contract stores **only the Merkle root**, the issuing key and a timestamp: one transaction per batch. No names, IIN or grades are ever stored on-chain.
- A verifier calls `verify(batchId, docHash, proof)` (read-only, free) and gets `VALID`, `INVALID` or `REVOKED`.

| Role | Who | Functions |
|---|---|---|
| Admin (`DEFAULT_ADMIN_ROLE`) | DiplomaChain (a 2-of-3 multisig in production) | `addIssuer`, `removeIssuer`, `pause`, `unpause` |
| Issuer (`ISSUER_ROLE`) | approved university key | `issueBatch`, `revoke` (only its own batches) |
| Anyone | employer, foreign university, graduate | `verify`, `getBatch`, `batchCount` |

## Project structure

```
src/DiplomaRegistry.sol      the smart contract
test/DiplomaRegistry.t.sol   12 unit tests (11 unit + 1 fuzz test)
script/Demo.s.sol            step-by-step demo of the main use case
script/MerkleHelper.sol      off-chain helper: hashes diplomas, builds the Merkle tree
foundry.toml                 Foundry configuration
```

## How to run (local network only)

The prototype uses [Foundry](https://book.getfoundry.sh/) and its local network **Anvil**. Anvil runs on your computer with test accounts; nothing touches a public network or real funds.

1. Install Foundry (macOS / Linux / Windows via WSL or Git Bash):
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```
2. Install the libraries (OpenZeppelin Contracts v5.1.0 and forge-std):
   ```bash
   forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
   forge install foundry-rs/forge-std
   ```
3. Run the tests (with a gas report):
   ```bash
   forge test -vv --gas-report
   ```
4. Run the demo on a local Anvil network:
   ```bash
   # terminal 1: start the local blockchain (--quiet hides the test keys)
   anvil --quiet
   # terminal 2: deploy the contract and run the main use case
   forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
     --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
   ```
   The demo uses Anvil's unlocked test accounts, so no private key or `.env` file is needed.

Expected demo output:
```
1. Contract deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3
2. Admin approved university key: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
3. Off-chain: 4 diplomas hashed, Merkle root: 0x8cde...5448
4. University recorded batch id: 0
5. Employer checks genuine diploma of Student A -> VALID
6. Employer checks tampered diploma (BSc -> MSc) -> INVALID
7. University revoked Student C -> check now: REVOKED
8. Stranger tried to record a fake batch -> REJECTED (access control)
```

## Tests

| # | Test | What it checks |
|---|---|---|
| 1 | `test_AdminCanAddIssuer` | admin approves a university key |
| 2 | `test_RevertWhen_NonAdminAddsIssuer` | nobody else can approve keys (access control) |
| 3 | `test_IssuerRecordsBatch` | root, issuer and timestamp are stored; event emitted |
| 4 | `test_RevertWhen_StrangerIssuesBatch` | an unapproved account cannot record diplomas |
| 5 | `test_VerifyGenuineDiplomas` | every genuine diploma is VALID |
| 6 | `test_TamperedDiplomaIsInvalid` | changed diploma, wrong proof or unknown batch is INVALID |
| 7 | `test_RevokedDiplomaFailsVerification` | revoked diploma is REVOKED, others stay VALID |
| 8 | `test_RevertWhen_OtherUniversityRevokes` | a university cannot revoke another university's diploma |
| 9 | `test_RemovedIssuerCannotIssue_OldDiplomasStayValid` | lost key: removed key cannot issue, old diplomas stay valid |
| 10 | `test_PauseStopsIssuanceButNotVerification` | emergency pause stops issuance, verification still works |
| 11 | `test_RevertWhen_EmptyRootOrDoubleRevoke` | input validation |
| 12 | `testFuzz_RandomHashIsNeverValid` | 1,000 random hashes are never accepted |

Gas (from `forge test --gas-report`): deployment ≈ 790,700 gas; `issueBatch` ≈ 95,200 gas per batch (the whole graduation batch); `revoke` ≈ 46,800 gas; `verify` is a free read-only call.

## Safety rules followed

- Local Anvil network and its test accounts only; never deployed to a main network or a testnet.
- No private keys, seed phrases or `.env` files in this repository (`.gitignore` excludes `.env`).
- All test data is invented ("Student A" … "Student D"); no personal data of real people.

## Credits

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) v5.1.0 (MIT licence): `AccessControl`, `Pausable`, `MerkleProof`.
- [Foundry](https://github.com/foundry-rs/foundry) and [forge-std](https://github.com/foundry-rs/forge-std) (MIT / Apache-2.0).
- AI assistance: Claude (Claude Opus 5.5, Anthropic) helped draft the contract, tests, demo script and this README; the team reviewed, ran and can explain all of the code.

## Licence

MIT
