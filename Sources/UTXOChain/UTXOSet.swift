import Foundation
import Crypto

/// Represents an unspent transaction output.
public struct UTXO: Codable, Hashable {
    public let txHash: String
    public let outputIndex: Int
    public let output: TxOutput

    public init(txHash: String, outputIndex: Int, output: TxOutput) {
        self.txHash = txHash
        self.outputIndex = outputIndex
        self.output = output
    }
}

/// Outpoint uniquely identifies a UTXO.
public struct Outpoint: Hashable, Codable {
    public let txHash: String
    public let index: Int

    public init(txHash: String, index: Int) {
        self.txHash = txHash
        self.index = index
    }
}

/// Tracks the set of unspent transaction outputs and validates transactions.
public class UTXOSet {
    /// Maps outpoint to its UTXO.
    public private(set) var utxos: [Outpoint: UTXO] = [:]

    public init() {}

    /// Create a copy of this UTXO set.
    public func copy() -> UTXOSet {
        let newSet = UTXOSet()
        newSet.utxos = self.utxos
        return newSet
    }

    /// Validate a transaction against the current UTXO set.
    /// Returns nil on success, or an error description string on failure.
    public func validate(transaction tx: Transaction) -> String? {
        if tx.isCoinbase {
            // Coinbase transactions don't consume inputs from the UTXO set
            return nil
        }

        if tx.inputs.isEmpty {
            return "Transaction has no inputs"
        }
        if tx.outputs.isEmpty {
            return "Transaction has no outputs"
        }

        var inputSum: UInt64 = 0
        var spentOutpoints = Set<Outpoint>()

        for input in tx.inputs {
            let outpoint = Outpoint(txHash: input.previousTxHash, index: input.outputIndex)

            // Check for double-spend within the same transaction
            if spentOutpoints.contains(outpoint) {
                return "Double-spend: input \(outpoint.txHash):\(outpoint.index) used twice in same transaction"
            }
            spentOutpoints.insert(outpoint)

            // Check input existence in UTXO set
            guard let utxo = utxos[outpoint] else {
                return "Input \(outpoint.txHash):\(outpoint.index) not found in UTXO set"
            }

            // Verify that the public key matches the recipient address
            if input.publicKey != utxo.output.recipientAddress {
                return "Public key does not match UTXO recipient address"
            }

            // Verify Ed25519 signature
            let unsignedInputs = tx.inputs.map {
                TxInput(previousTxHash: $0.previousTxHash, outputIndex: $0.outputIndex, signature: "", publicKey: $0.publicKey)
            }
            let payload = Transaction.signingPayload(inputs: unsignedInputs, outputs: tx.outputs)
            if !KeyHelper.verify(data: payload, signatureHex: input.signature, publicKeyHex: input.publicKey) {
                return "Invalid signature for input \(outpoint.txHash):\(outpoint.index)"
            }

            inputSum += utxo.output.amount
        }

        let outputSum = tx.outputs.reduce(UInt64(0)) { $0 + $1.amount }
        if outputSum > inputSum {
            return "Output sum (\(outputSum)) exceeds input sum (\(inputSum))"
        }

        return nil
    }

    /// Apply a valid transaction: remove spent UTXOs and add new ones.
    public func apply(transaction tx: Transaction) {
        // Remove spent UTXOs (skip for coinbase)
        if !tx.isCoinbase {
            for input in tx.inputs {
                let outpoint = Outpoint(txHash: input.previousTxHash, index: input.outputIndex)
                utxos.removeValue(forKey: outpoint)
            }
        }

        // Add new UTXOs
        for (idx, output) in tx.outputs.enumerated() {
            let outpoint = Outpoint(txHash: tx.id, index: idx)
            utxos[outpoint] = UTXO(txHash: tx.id, outputIndex: idx, output: output)
        }
    }

    /// Validate and apply a transaction. Returns nil on success or error string.
    @discardableResult
    public func validateAndApply(transaction tx: Transaction) -> String? {
        if let error = validate(transaction: tx) {
            return error
        }
        apply(transaction: tx)
        return nil
    }

    /// Get all UTXOs belonging to a given address.
    public func utxos(for address: String) -> [UTXO] {
        return utxos.values.filter { $0.output.recipientAddress == address }
    }

    /// Get the total balance for an address.
    public func balance(for address: String) -> UInt64 {
        return utxos(for: address).reduce(0) { $0 + $1.output.amount }
    }
}
