// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Resolve",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
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
        .package(url: "git@github.com:swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .macro(
            name: "Macros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/Macros"
        ),
        .target(
            name: "Resolve",
            dependencies: [
                .target(name: "Macros")
            ],
            path: "Sources/Resolve",
            swiftSettings: [
                .disableReflectionMetadata,
                .strictMemorySafety,
                .approachableConcurrency,
                .existentialAny,
                .internalImportsByDefault,
                .memberImportVisibility
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
    static let disableReflectionMetadata = SwiftSetting.unsafeFlags(["-Xfrontend", "-disable-reflection-metadata"], .when(configuration: .release))
    static let strictMemorySafety = SwiftSetting.unsafeFlags(["-Xfrontend", "-strict-memory-safety"])
    static let approachableConcurrency = SwiftSetting.enableUpcomingFeature("ApproachableConcurrency")
    static let existentialAny = SwiftSetting.enableUpcomingFeature("ExistentialAny")
    static let internalImportsByDefault = SwiftSetting.enableUpcomingFeature("InternalImportsByDefault")
    static let memberImportVisibility = SwiftSetting.enableUpcomingFeature("MemberImportVisibility")
}
