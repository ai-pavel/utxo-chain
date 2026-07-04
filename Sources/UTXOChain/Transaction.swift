import Foundation
import Crypto

/// A reference to a specific output of a previous transaction.
public struct TxInput: Codable, Hashable {
    /// Hash of the previous transaction.
    public let previousTxHash: String
    /// Index of the output in the previous transaction.
    public let outputIndex: Int
    /// Ed25519 signature proving ownership (hex-encoded).
    public let signature: String
    /// Public key of the signer (hex-encoded, 32 bytes).
    public let publicKey: String

    public init(previousTxHash: String, outputIndex: Int, signature: String, publicKey: String) {
        self.previousTxHash = previousTxHash
        self.outputIndex = outputIndex
        self.signature = signature
        self.publicKey = publicKey
    }
}

/// A transaction output specifying a recipient and amount.
public struct TxOutput: Codable, Hashable {
    /// Recipient address (hex-encoded public key).
    public let recipientAddress: String
    /// Amount of value transferred.
    public let amount: UInt64

    public init(recipientAddress: String, amount: UInt64) {
        self.recipientAddress = recipientAddress
        self.amount = amount
    }
}

/// A transaction consisting of inputs and outputs.
public struct Transaction: Codable, Hashable {
    public let id: String
    public let inputs: [TxInput]
    public let outputs: [TxOutput]
    /// Whether this is a coinbase (block reward) transaction.
    public let isCoinbase: Bool

    /// Create a transaction. The id is computed as a SHA-256 hash of the inputs and outputs.
    public init(inputs: [TxInput], outputs: [TxOutput], isCoinbase: Bool = false) {
        self.inputs = inputs
        self.outputs = outputs
        self.isCoinbase = isCoinbase
        self.id = Transaction.computeID(inputs: inputs, outputs: outputs, isCoinbase: isCoinbase)
    }

    /// Computes the signing payload for a transaction (excludes signatures).
    public static func signingPayload(inputs: [TxInput], outputs: [TxOutput]) -> Data {
        var data = Data()
        for input in inputs {
            data.append(contentsOf: input.previousTxHash.utf8)
            var idx = input.outputIndex
            data.append(contentsOf: withUnsafeBytes(of: &idx) { Data($0) })
        }
        for output in outputs {
            data.append(contentsOf: output.recipientAddress.utf8)
            var amt = output.amount
            data.append(contentsOf: withUnsafeBytes(of: &amt) { Data($0) })
        }
        return data
    }

    /// Compute the transaction ID from its contents.
    static func computeID(inputs: [TxInput], outputs: [TxOutput], isCoinbase: Bool) -> String {
        var data = signingPayload(inputs: inputs, outputs: outputs)
        data.append(isCoinbase ? 1 : 0)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Create a coinbase transaction that rewards the miner.
    public static func coinbase(recipientAddress: String, reward: UInt64, blockIndex: Int) -> Transaction {
        // Coinbase has a single dummy input with the block index as "previousTxHash"
        let dummyInput = TxInput(
            previousTxHash: "coinbase-\(blockIndex)",
            outputIndex: 0,
            signature: "",
            publicKey: ""
        )
        let output = TxOutput(recipientAddress: recipientAddress, amount: reward)
        return Transaction(inputs: [dummyInput], outputs: [output], isCoinbase: true)
    }
}

// MARK: - Key Helpers

/// Helpers for Ed25519 key operations.
public enum KeyHelper {
    /// Generate a new Ed25519 key pair. Returns (privateKey, publicKey) both hex-encoded.
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let privKey = Curve25519.Signing.PrivateKey()
        let privHex = privKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        let pubHex = privKey.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        return (privHex, pubHex)
    }

    /// Sign data with a hex-encoded private key.
    public static func sign(data: Data, privateKeyHex: String) -> String {
        let keyData = hexToData(privateKeyHex)
        guard let privKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
            return ""
        }
        guard let signature = try? privKey.signature(for: data) else {
            return ""
        }
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    /// Verify a signature given hex-encoded public key and signature.
    public static func verify(data: Data, signatureHex: String, publicKeyHex: String) -> Bool {
        let sigData = hexToData(signatureHex)
        let pubData = hexToData(publicKeyHex)
        guard let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else {
            return false
        }
        return pubKey.isValidSignature(sigData, for: data)
    }

    /// Convert a hex string to Data.
    public static func hexToData(_ hex: String) -> Data {
        var data = Data()
        var chars = Array(hex)
        while chars.count >= 2 {
            let pair = String(chars[0]) + String(chars[1])
            if let byte = UInt8(pair, radix: 16) {
                data.append(byte)
            }
            chars.removeFirst(2)
        }
        return data
    }
}

/// Helper to create a signed transaction input.
public func createSignedInput(
    previousTxHash: String,
    outputIndex: Int,
    privateKeyHex: String,
    publicKeyHex: String,
    allInputRefs: [(String, Int)],
    outputs: [TxOutput]
) -> TxInput {
    // Build unsigned inputs for signing payload
    let unsignedInputs = allInputRefs.map {
        TxInput(previousTxHash: $0.0, outputIndex: $0.1, signature: "", publicKey: publicKeyHex)
    }
    let payload = Transaction.signingPayload(inputs: unsignedInputs, outputs: outputs)
    let signature = KeyHelper.sign(data: payload, privateKeyHex: privateKeyHex)
    return TxInput(
        previousTxHash: previousTxHash,
        outputIndex: outputIndex,
        signature: signature,
        publicKey: publicKeyHex
    )
}
