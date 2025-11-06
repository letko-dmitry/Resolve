// swift-tools-version: 6.1
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
        .package(url: "git@github.com:swiftlang/swift-syntax.git", from: "601.0.1")
    ],
    targets: [
        .macro(
            name: "Macros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ],
            path: "Sources/Macros",
            swiftSettings: .`default`
        ),
        .target(
            name: "Resolve",
            dependencies: [
                .target(name: "Macros")
            ],
            path: "Sources/Resolve",
            swiftSettings: .`default`
        ),
        .executableTarget(
            name: "Playground",
            dependencies: [
                .target(name: "Resolve")
            ],
            path: "Sources/Playground",
            swiftSettings: .`default`
        ),
        .testTarget(
            name: "Tests",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .target(name: "Macros")
            ],
            path: "Sources/Tests",
            swiftSettings: .`default`
        )
    ]
)

// MARK: - SwiftSetting
private extension SwiftSetting {
    static let disableReflectionMetadata = SwiftSetting.unsafeFlags(["-Xfrontend", "-disable-reflection-metadata"], .when(configuration: .release))
    static let internalizeAtLink = SwiftSetting.unsafeFlags(["-Xfrontend", "-internalize-at-link"], .when(configuration: .release))
    static let approachableConcurrency = SwiftSetting.enableUpcomingFeature("ApproachableConcurrency")
    static let existentialAny = SwiftSetting.enableUpcomingFeature("ExistentialAny")
    static let internalImportsByDefault = SwiftSetting.enableUpcomingFeature("InternalImportsByDefault")
    static let memberImportVisibility = SwiftSetting.enableUpcomingFeature("MemberImportVisibility")
}

// MARK: - SwiftSetting
private extension Array<SwiftSetting> {
    static let `default`: Self = [
        .disableReflectionMetadata,
        .internalizeAtLink,
        .approachableConcurrency,
        .existentialAny,
        .internalImportsByDefault,
        .memberImportVisibility,
        .strictMemorySafety()
    ]
}
