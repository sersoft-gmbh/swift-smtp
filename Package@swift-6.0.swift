// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: Array<SwiftSetting> = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "swift-smtp",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "SwiftSMTP",
            targets: ["SwiftSMTP"]),
        .library(
            name: "SwiftSMTPVapor",
            targets: ["SwiftSMTPVapor"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.78.0"),
        .package(url: "https://github.com/apple/swift-nio-extras", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl", from: "2.29.0"),
        .package(url: "https://github.com/vapor/vapor", from: "4.111.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SwiftSMTP",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            swiftSettings: swiftSettings),
        .target(
            name: "SwiftSMTPVapor",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "SwiftSMTP",
            ],
            swiftSettings: swiftSettings),
        .executableTarget(
            name: "SwiftSMTPCLI",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                "SwiftSMTP",
            ],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "SwiftSMTPTests",
            dependencies: ["SwiftSMTP"],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "SwiftSMTPVaporTests",
            dependencies: ["SwiftSMTPVapor"],
            swiftSettings: swiftSettings),
    ]
)
