import Foundation

/// Errors that can occur during chain validation.
public enum ChainError: Error, CustomStringConvertible {
    case invalidGenesisBlock(String)
    case invalidBlockLinkage(Int, expected: String, got: String)
    case invalidProofOfWork(Int)
    case invalidMerkleRoot(Int)
    case invalidTransaction(Int, String)
    case blockIndexMismatch(Int, expected: Int)
    case forkDetected(Int, existingHash: String, newHash: String)

    public var description: String {
        switch self {
        case .invalidGenesisBlock(let msg):
            return "Invalid genesis block: \(msg)"
        case .invalidBlockLinkage(let idx, let expected, let got):
            return "Block \(idx): invalid linkage, expected previousHash \(expected), got \(got)"
        case .invalidProofOfWork(let idx):
            return "Block \(idx): invalid proof-of-work"
        case .invalidMerkleRoot(let idx):
            return "Block \(idx): invalid Merkle root"
        case .invalidTransaction(let idx, let msg):
            return "Block \(idx): invalid transaction - \(msg)"
        case .blockIndexMismatch(let idx, let expected):
            return "Block index mismatch: got \(idx), expected \(expected)"
        case .forkDetected(let idx, let existingHash, let newHash):
            return "Fork detected at index \(idx): existing \(existingHash) vs new \(newHash)"
        }
    }
}

/// A blockchain that maintains a chain of blocks and UTXO set.
public class Blockchain {
    public private(set) var blocks: [Block] = []
    public let utxoSet: UTXOSet
    public let miner: Miner

    public init(difficulty: Int = 2, reward: UInt64 = 50) {
        self.utxoSet = UTXOSet()
        self.miner = Miner(difficulty: difficulty, reward: reward)
    }

    /// The hash of the latest block, or a zero hash if chain is empty.
    public var latestHash: String {
        return blocks.last?.hash() ?? String(repeating: "0", count: 64)
    }

    /// Mine and add a new block with the given transactions.
    @discardableResult
    public func mineAndAddBlock(
        transactions: [Transaction] = [],
        minerAddress: String
    ) -> Block {
        let block = miner.mineBlock(
            transactions: transactions,
            previousHash: latestHash,
            index: blocks.count,
            minerAddress: minerAddress
        )
        // Apply all transactions to the UTXO set
        for tx in block.transactions {
            utxoSet.apply(transaction: tx)
        }
        blocks.append(block)
        return block
    }

    /// Validate the entire chain from scratch.
    public static func validateChain(_ blocks: [Block]) -> Result<Void, ChainError> {
        guard !blocks.isEmpty else { return .success(()) }

        let utxo = UTXOSet()

        for (i, block) in blocks.enumerated() {
            // Check block index
            if block.index != i {
                return .failure(.blockIndexMismatch(block.index, expected: i))
            }

            // Check linkage
            if i == 0 {
                let expectedPrev = String(repeating: "0", count: 64)
                if block.header.previousHash != expectedPrev {
                    return .failure(.invalidGenesisBlock("previousHash should be all zeros"))
                }
            } else {
                let expectedPrev = blocks[i - 1].hash()
                if block.header.previousHash != expectedPrev {
                    return .failure(.invalidBlockLinkage(i, expected: expectedPrev, got: block.header.previousHash))
                }
            }

            // Check proof-of-work
            if !block.header.satisfiesDifficulty() {
                return .failure(.invalidProofOfWork(i))
            }

            // Check Merkle root
            let expectedMerkle = Block.computeMerkleRoot(transactions: block.transactions)
            if block.header.merkleRoot != expectedMerkle {
                return .failure(.invalidMerkleRoot(i))
            }

            // Validate all transactions
            for tx in block.transactions {
                if let error = utxo.validate(transaction: tx) {
                    return .failure(.invalidTransaction(i, error))
                }
                utxo.apply(transaction: tx)
            }
        }

        return .success(())
    }

    /// Detect if adding a block at a given index would create a fork.
    public func detectFork(newBlock: Block) -> ChainError? {
        let idx = newBlock.index
        if idx < blocks.count {
            let existingHash = blocks[idx].hash()
            let newHash = newBlock.hash()
            if existingHash != newHash {
                return .forkDetected(idx, existingHash: existingHash, newHash: newHash)
            }
        }
        return nil
    }
}
