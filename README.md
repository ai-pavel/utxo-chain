# UTXOChain

[![CI](https://github.com/ai-pavel/utxo-chain/actions/workflows/ci.yml/badge.svg)](https://github.com/ai-pavel/utxo-chain/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ai-pavel/utxo-chain/branch/main/graph/badge.svg)](https://codecov.io/gh/ai-pavel/utxo-chain)

A minimal UTXO-based blockchain implementation in Swift.

## Features

- **Transaction model** with inputs (previous tx hash + output index) and outputs (recipient address + amount)
- **UTXO set tracker** that validates transactions: checks input existence, prevents double-spends, and verifies Ed25519 signatures (via swift-crypto)
- **Block structure** with header containing previous hash, Merkle root, nonce, and timestamp
- **Proof-of-work miner** with configurable difficulty
- **Chain validator** that checks block linkage, PoW, and transaction validity

## Project Structure

```
Sources/
  UTXOChain/
    Transaction.swift   - Transaction, TxInput, TxOutput models
    Block.swift         - Block and BlockHeader structs
    UTXOSet.swift       - UTXO set tracker with validation
    Miner.swift         - Proof-of-work miner
    Chain.swift         - Blockchain and chain validator
  CLI/
    main.swift          - Demo that mines a 10-block chain
Tests/
  UTXOChainTests/
    UTXOChainTests.swift - Tests for double-spend, signatures, forks, difficulty
```

## Build and Run

```bash
swift build
swift run cli
```

## Test

```bash
swift test
```

## Requirements

- Swift 5.9+
- macOS 13+
