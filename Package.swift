// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UTXOChain",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "UTXOChain", targets: ["UTXOChain"]),
        .executable(name: "cli", targets: ["CLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "UTXOChain",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/UTXOChain"
        ),
        .executableTarget(
            name: "CLI",
            dependencies: ["UTXOChain"],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "UTXOChainTests",
            dependencies: ["UTXOChain"],
            path: "Tests/UTXOChainTests"
        ),
    ]
)
