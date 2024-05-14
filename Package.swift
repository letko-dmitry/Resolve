// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Resolve",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Resolve",
            targets: [
                "Resolve"
            ]
        )
    ],
    dependencies: [
        .package(url: "git@github.com:apple/swift-syntax.git", from: "510.0.2")
    ],
    targets: [
        .macro(
            name: "Macros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/Macros",
            swiftSettings: [
                .strictConcurrency
            ]
        ),
        .target(
            name: "Resolve",
            dependencies: [
                .target(name: "Macros")
            ],
            path: "Sources/Resolve",
            swiftSettings: [
                .strictConcurrency
            ]
        ),
        .executableTarget(
            name: "Playground",
            dependencies: [
                .target(name: "Resolve")
            ],
            path: "Sources/Playground"
        ),
        .testTarget(
            name: "Tests",
            dependencies: [
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .target(name: "Macros")
            ],
            path: "Sources/Tests"
        )
    ]
)

// MARK: - SwiftSetting
private extension SwiftSetting {
    static let strictConcurrency = SwiftSetting.unsafeFlags(["-Xfrontend", "-strict-concurrency=complete"])
}
