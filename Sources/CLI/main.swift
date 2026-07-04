import Foundation
import UTXOChain

print("=== UTXO Blockchain Demo ===\n")

// Generate key pairs for two participants
let (alicePriv, alicePub) = KeyHelper.generateKeyPair()
let (_, bobPub) = KeyHelper.generateKeyPair()

print("Alice address: \(alicePub.prefix(16))...")
print("Bob address:   \(bobPub.prefix(16))...\n")

// Create blockchain with low difficulty for fast demo
let chain = Blockchain(difficulty: 2, reward: 50)

// Mine 10 blocks
for i in 0..<10 {
    var userTransactions: [Transaction] = []

    // After block 2, Alice has coinbase rewards she can spend
    if i >= 2 {
        // Find a UTXO belonging to Alice
        let aliceUTXOs = chain.utxoSet.utxos(for: alicePub)
        if let utxo = aliceUTXOs.first {
            let sendAmount: UInt64 = 10
            let changeAmount = utxo.output.amount - sendAmount

            let outputs = [
                TxOutput(recipientAddress: bobPub, amount: sendAmount),
                TxOutput(recipientAddress: alicePub, amount: changeAmount),
            ]

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

            // Validate before including
            if let error = chain.utxoSet.validate(transaction: tx) {
                print("  TX validation failed: \(error)")
            } else {
                userTransactions.append(tx)
                print("  Block \(i): Alice sends \(sendAmount) to Bob (change: \(changeAmount))")
            }
        }
    }

    let block = chain.mineAndAddBlock(transactions: userTransactions, minerAddress: alicePub)
    let hashPrefix = String(block.hash().prefix(16))
    print("Block \(i) mined: \(hashPrefix)... (nonce: \(block.header.nonce), txs: \(block.transactions.count))")
}

// Print balances
print("\n=== Final Balances ===")
print("Alice: \(chain.utxoSet.balance(for: alicePub))")
print("Bob:   \(chain.utxoSet.balance(for: bobPub))")

// Validate the full chain
print("\n=== Chain Validation ===")
switch Blockchain.validateChain(chain.blocks) {
case .success:
    print("Chain is valid! (\(chain.blocks.count) blocks)")
case .failure(let error):
    print("Chain validation FAILED: \(error)")
}

print("\nDone.")
