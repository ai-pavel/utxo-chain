import XCTest
@testable import UTXOChain

final class UTXOChainTests: XCTestCase {

    // MARK: - Helpers

    /// Create a blockchain, mine one block, and return (chain, alice keys, bob keys).
    func setupChainWithFundedAlice() -> (Blockchain, String, String, String, String) {
        let (alicePriv, alicePub) = KeyHelper.generateKeyPair()
        let (_, bobPub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)
        // Mine one block to give Alice a coinbase reward
        chain.mineAndAddBlock(minerAddress: alicePub)
        return (chain, alicePriv, alicePub, "", bobPub)
    }

    func makeTransferTx(
        from utxo: UTXO,
        toAddress: String,
        amount: UInt64,
        changeAddress: String,
        privateKey: String,
        publicKey: String
    ) -> Transaction {
        let change = utxo.output.amount - amount
        var outputs = [TxOutput(recipientAddress: toAddress, amount: amount)]
        if change > 0 {
            outputs.append(TxOutput(recipientAddress: changeAddress, amount: change))
        }
        let inputRefs = [(utxo.txHash, utxo.outputIndex)]
        let signedInput = createSignedInput(
            previousTxHash: utxo.txHash,
            outputIndex: utxo.outputIndex,
            privateKeyHex: privateKey,
            publicKeyHex: publicKey,
            allInputRefs: inputRefs,
            outputs: outputs
        )
        return Transaction(inputs: [signedInput], outputs: outputs)
    }

    // MARK: - Double-Spend Rejection

    func testDoubleSpendRejection() {
        let (alicePriv, alicePub) = KeyHelper.generateKeyPair()
        let (_, bobPub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)
        chain.mineAndAddBlock(minerAddress: alicePub)

        let aliceUTXOs = chain.utxoSet.utxos(for: alicePub)
        XCTAssertFalse(aliceUTXOs.isEmpty, "Alice should have UTXOs after mining")

        let utxo = aliceUTXOs[0]

        // First spend should succeed
        let tx1 = makeTransferTx(
            from: utxo, toAddress: bobPub, amount: 50,
            changeAddress: alicePub, privateKey: alicePriv, publicKey: alicePub
        )
        let result1 = chain.utxoSet.validateAndApply(transaction: tx1)
        XCTAssertNil(result1, "First spend should succeed")

        // Second spend of the same UTXO should fail
        let tx2 = makeTransferTx(
            from: utxo, toAddress: bobPub, amount: 50,
            changeAddress: alicePub, privateKey: alicePriv, publicKey: alicePub
        )
        let result2 = chain.utxoSet.validate(transaction: tx2)
        XCTAssertNotNil(result2, "Double-spend should be rejected")
        XCTAssertTrue(result2?.contains("not found") ?? false, "Error should mention UTXO not found")
    }

    // MARK: - Invalid Signature Rejection

    func testInvalidSignatureRejection() {
        let (_, alicePub) = KeyHelper.generateKeyPair()
        let (evePriv, _) = KeyHelper.generateKeyPair() // Eve tries to steal
        let (_, bobPub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)
        chain.mineAndAddBlock(minerAddress: alicePub)

        let aliceUTXOs = chain.utxoSet.utxos(for: alicePub)
        XCTAssertFalse(aliceUTXOs.isEmpty)

        let utxo = aliceUTXOs[0]

        // Eve tries to spend Alice's UTXO using Eve's private key but Alice's public key
        let outputs = [TxOutput(recipientAddress: bobPub, amount: 100)]
        let inputRefs = [(utxo.txHash, utxo.outputIndex)]
        let badInput = createSignedInput(
            previousTxHash: utxo.txHash,
            outputIndex: utxo.outputIndex,
            privateKeyHex: evePriv,
            publicKeyHex: alicePub,
            allInputRefs: inputRefs,
            outputs: outputs
        )
        let badTx = Transaction(inputs: [badInput], outputs: outputs)

        let result = chain.utxoSet.validate(transaction: badTx)
        XCTAssertNotNil(result, "Transaction with invalid signature should be rejected")
        XCTAssertTrue(result?.contains("Invalid signature") ?? false, "Error should mention invalid signature")
    }

    // MARK: - Chain Fork Detection

    func testChainForkDetection() {
        let (_, alicePub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)

        // Mine 3 blocks
        chain.mineAndAddBlock(minerAddress: alicePub)
        chain.mineAndAddBlock(minerAddress: alicePub)
        chain.mineAndAddBlock(minerAddress: alicePub)

        // Create an alternative block at index 1 (a fork)
        let altMiner = Miner(difficulty: 1, reward: 100)
        let forkBlock = altMiner.mineBlock(
            transactions: [],
            previousHash: chain.blocks[0].hash(),
            index: 1,
            minerAddress: alicePub
        )

        // The fork block has a different hash than the existing block at index 1
        let forkError = chain.detectFork(newBlock: forkBlock)
        XCTAssertNotNil(forkError, "Fork should be detected")

        if case .forkDetected(let idx, _, _) = forkError {
            XCTAssertEqual(idx, 1, "Fork should be at index 1")
        } else {
            XCTFail("Expected forkDetected error")
        }
    }

    // MARK: - Difficulty Adjustment

    func testDifficultyAdjustment() {
        let (_, alicePub) = KeyHelper.generateKeyPair()

        // Mine with difficulty 1
        let chain1 = Blockchain(difficulty: 1, reward: 50)
        chain1.mineAndAddBlock(minerAddress: alicePub)
        let hash1 = chain1.blocks[0].hash()
        XCTAssertTrue(hash1.hasPrefix("0"), "Difficulty 1 block should start with '0'")

        // Mine with difficulty 2
        let chain2 = Blockchain(difficulty: 2, reward: 50)
        chain2.mineAndAddBlock(minerAddress: alicePub)
        let hash2 = chain2.blocks[0].hash()
        XCTAssertTrue(hash2.hasPrefix("00"), "Difficulty 2 block should start with '00'")

        // Changing difficulty on miner
        let miner = Miner(difficulty: 1, reward: 50)
        let block1 = miner.mineBlock(transactions: [], previousHash: String(repeating: "0", count: 64), index: 0, minerAddress: alicePub)
        XCTAssertTrue(block1.header.satisfiesDifficulty())
        XCTAssertEqual(block1.header.difficulty, 1)

        miner.difficulty = 2
        let block2 = miner.mineBlock(transactions: [], previousHash: block1.hash(), index: 1, minerAddress: alicePub)
        XCTAssertTrue(block2.header.satisfiesDifficulty())
        XCTAssertEqual(block2.header.difficulty, 2)
    }

    // MARK: - Chain Validation

    func testChainValidation() {
        let (alicePriv, alicePub) = KeyHelper.generateKeyPair()
        let (_, bobPub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)

        // Mine a few blocks with transactions
        chain.mineAndAddBlock(minerAddress: alicePub)
        chain.mineAndAddBlock(minerAddress: alicePub)

        // Create a transfer transaction
        let aliceUTXOs = chain.utxoSet.utxos(for: alicePub)
        if let utxo = aliceUTXOs.first {
            let tx = makeTransferTx(
                from: utxo, toAddress: bobPub, amount: 30,
                changeAddress: alicePub, privateKey: alicePriv, publicKey: alicePub
            )
            chain.mineAndAddBlock(transactions: [tx], minerAddress: alicePub)
        }

        // Validate the chain
        let result = Blockchain.validateChain(chain.blocks)
        switch result {
        case .success:
            break // expected
        case .failure(let error):
            XCTFail("Chain should be valid but got: \(error)")
        }
    }

    // MARK: - Tampered Chain Detection

    func testTamperedBlockRejection() {
        let (_, alicePub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)
        chain.mineAndAddBlock(minerAddress: alicePub)
        chain.mineAndAddBlock(minerAddress: alicePub)
        chain.mineAndAddBlock(minerAddress: alicePub)

        // Tamper with block 1 by creating a modified version
        var tamperedBlocks = chain.blocks
        let original = tamperedBlocks[1]
        let tamperedHeader = BlockHeader(
            previousHash: original.header.previousHash,
            merkleRoot: original.header.merkleRoot,
            nonce: original.header.nonce + 999999, // tampered nonce
            timestamp: original.header.timestamp,
            difficulty: original.header.difficulty
        )
        tamperedBlocks[1] = Block(header: tamperedHeader, transactions: original.transactions, index: 1)

        // Validation should fail (either PoW or linkage)
        let result = Blockchain.validateChain(tamperedBlocks)
        switch result {
        case .success:
            XCTFail("Tampered chain should not validate")
        case .failure:
            break // expected
        }
    }

    // MARK: - UTXO Balance Tracking

    func testBalanceTracking() {
        let (alicePriv, alicePub) = KeyHelper.generateKeyPair()
        let (_, bobPub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)

        // Mine two blocks for Alice
        chain.mineAndAddBlock(minerAddress: alicePub)
        chain.mineAndAddBlock(minerAddress: alicePub)
        XCTAssertEqual(chain.utxoSet.balance(for: alicePub), 200)
        XCTAssertEqual(chain.utxoSet.balance(for: bobPub), 0)

        // Send 30 from Alice to Bob
        let utxo = chain.utxoSet.utxos(for: alicePub).first!
        let tx = makeTransferTx(
            from: utxo, toAddress: bobPub, amount: 30,
            changeAddress: alicePub, privateKey: alicePriv, publicKey: alicePub
        )
        chain.mineAndAddBlock(transactions: [tx], minerAddress: alicePub)

        // Alice: 100 (remaining from first two) + 70 (change) + 100 (new reward) = 270
        // Bob: 30
        XCTAssertEqual(chain.utxoSet.balance(for: alicePub), 270)
        XCTAssertEqual(chain.utxoSet.balance(for: bobPub), 30)
    }

    // MARK: - Coinbase Transaction

    func testCoinbaseTransaction() {
        let (_, alicePub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 50)
        let block = chain.mineAndAddBlock(minerAddress: alicePub)

        XCTAssertEqual(block.transactions.count, 1)
        XCTAssertTrue(block.transactions[0].isCoinbase)
        XCTAssertEqual(block.transactions[0].outputs[0].amount, 50)
        XCTAssertEqual(block.transactions[0].outputs[0].recipientAddress, alicePub)
    }

    // MARK: - Merkle Root

    func testMerkleRoot() {
        let tx1 = Transaction.coinbase(recipientAddress: "addr1", reward: 50, blockIndex: 0)
        let tx2 = Transaction.coinbase(recipientAddress: "addr2", reward: 50, blockIndex: 1)

        let root1 = Block.computeMerkleRoot(transactions: [tx1])
        let root2 = Block.computeMerkleRoot(transactions: [tx1, tx2])
        let rootEmpty = Block.computeMerkleRoot(transactions: [])

        XCTAssertNotEqual(root1, root2, "Different transactions should yield different Merkle roots")
        XCTAssertNotEqual(root1, rootEmpty)
        XCTAssertEqual(rootEmpty, String(repeating: "0", count: 64))
    }

    // MARK: - Overspend Rejection

    func testOverspendRejection() {
        let (alicePriv, alicePub) = KeyHelper.generateKeyPair()
        let (_, bobPub) = KeyHelper.generateKeyPair()
        let chain = Blockchain(difficulty: 1, reward: 100)
        chain.mineAndAddBlock(minerAddress: alicePub)

        let utxo = chain.utxoSet.utxos(for: alicePub).first!

        // Try to send more than the UTXO value
        let outputs = [TxOutput(recipientAddress: bobPub, amount: 200)]
        let inputRefs = [(utxo.txHash, utxo.outputIndex)]
        let signedInput = createSignedInput(
            previousTxHash: utxo.txHash,
            outputIndex: utxo.outputIndex,
            privateKeyHex: alicePriv,
            publicKeyHex: alicePub,
            allInputRefs: inputRefs,
            outputs: outputs
        )
        let tx = Transaction(inputs: [signedInput], outputs: outputs)

        let result = chain.utxoSet.validate(transaction: tx)
        XCTAssertNotNil(result, "Overspend should be rejected")
        XCTAssertTrue(result?.contains("exceeds") ?? false)
    }
}
