import Foundation
import Crypto

/// Block header containing metadata for proof-of-work.
public struct BlockHeader: Codable, Hashable {
    /// Hash of the previous block.
    public let previousHash: String
    /// Merkle root of the block's transactions.
    public let merkleRoot: String
    /// Proof-of-work nonce.
    public var nonce: UInt64
    /// Block creation timestamp.
    public let timestamp: Date
    /// Difficulty target (number of leading zero hex chars required).
    public let difficulty: Int

    public init(previousHash: String, merkleRoot: String, nonce: UInt64, timestamp: Date, difficulty: Int) {
        self.previousHash = previousHash
        self.merkleRoot = merkleRoot
        self.nonce = nonce
        self.timestamp = timestamp
        self.difficulty = difficulty
    }

    /// Compute the SHA-256 hash of this header.
    public func hash() -> String {
        var data = Data()
        data.append(contentsOf: previousHash.utf8)
        data.append(contentsOf: merkleRoot.utf8)
        var n = nonce
        data.append(contentsOf: withUnsafeBytes(of: &n) { Data($0) })
        var ts = timestamp.timeIntervalSince1970
        data.append(contentsOf: withUnsafeBytes(of: &ts) { Data($0) })
        var d = difficulty
        data.append(contentsOf: withUnsafeBytes(of: &d) { Data($0) })
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Check if the header hash satisfies the difficulty target.
    public func satisfiesDifficulty() -> Bool {
        let h = hash()
        let prefix = String(repeating: "0", count: difficulty)
        return h.hasPrefix(prefix)
    }
}

/// A block containing a header and a list of transactions.
public struct Block: Codable, Hashable {
    public let header: BlockHeader
    public let transactions: [Transaction]
    public let index: Int

    public init(header: BlockHeader, transactions: [Transaction], index: Int) {
        self.header = header
        self.transactions = transactions
        self.index = index
    }

    /// Compute the hash of this block (delegates to header).
    public func hash() -> String {
        return header.hash()
    }

    /// Compute the Merkle root of a list of transactions.
    public static func computeMerkleRoot(transactions: [Transaction]) -> String {
        guard !transactions.isEmpty else {
            return String(repeating: "0", count: 64)
        }

        var hashes = transactions.map { tx -> String in
            let digest = SHA256.hash(data: Data(tx.id.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        while hashes.count > 1 {
            var nextLevel: [String] = []
            var i = 0
            while i < hashes.count {
                let left = hashes[i]
                let right = (i + 1 < hashes.count) ? hashes[i + 1] : left
                let combined = left + right
                let digest = SHA256.hash(data: Data(combined.utf8))
                nextLevel.append(digest.map { String(format: "%02x", $0) }.joined())
                i += 2
            }
            hashes = nextLevel
        }

        return hashes[0]
    }
}
