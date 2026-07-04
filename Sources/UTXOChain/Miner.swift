import Foundation

/// A simple proof-of-work miner with configurable difficulty.
public class Miner {
    /// Number of leading zero hex characters required in block hash.
    public var difficulty: Int
    /// Block reward amount.
    public let reward: UInt64

    public init(difficulty: Int = 2, reward: UInt64 = 50) {
        self.difficulty = difficulty
        self.reward = reward
    }

    /// Mine a new block with the given transactions.
    /// - Parameters:
    ///   - transactions: User transactions to include (coinbase is prepended automatically).
    ///   - previousHash: Hash of the previous block.
    ///   - index: Block index.
    ///   - minerAddress: Address to receive the block reward.
    /// - Returns: A mined block with valid proof-of-work.
    public func mineBlock(
        transactions: [Transaction],
        previousHash: String,
        index: Int,
        minerAddress: String
    ) -> Block {
        let coinbase = Transaction.coinbase(recipientAddress: minerAddress, reward: reward, blockIndex: index)
        let allTransactions = [coinbase] + transactions
        let merkleRoot = Block.computeMerkleRoot(transactions: allTransactions)

        var nonce: UInt64 = 0
        let timestamp = Date()

        while true {
            let header = BlockHeader(
                previousHash: previousHash,
                merkleRoot: merkleRoot,
                nonce: nonce,
                timestamp: timestamp,
                difficulty: difficulty
            )
            if header.satisfiesDifficulty() {
                return Block(header: header, transactions: allTransactions, index: index)
            }
            nonce += 1
        }
    }
}
