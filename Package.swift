// swift-tools-version: 5.9
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
        .package(url: "git@github.com:apple/swift-syntax.git", from: "509.0.0"),
        .package(url: "git@github.com:realm/SwiftLint.git", from: "0.53.0")
    ],
    targets: [
        .macro(
            name: "Macros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/Macros",
            swiftSettings: [
                .strictConcurrency
            ],
            plugins: [
                .plugin(name: "SwiftLintPlugin", package: "SwiftLint")
            ]
        ),
        .target(
            name: "Resolve",
            dependencies: [
                "Macros"
            ],
            path: "Sources/Resolve",
            swiftSettings: [
                .strictConcurrency
            ],
            plugins: [
                .plugin(name: "SwiftLintPlugin", package: "SwiftLint")
            ]
        ),
        .executableTarget(
            name: "Playground",
            dependencies: [
                "Resolve"
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
