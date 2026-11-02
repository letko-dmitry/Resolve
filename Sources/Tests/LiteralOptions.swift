//
//  LiteralOptions.swift
//
//
//  Created by Dzmitry Letko on 30/10/2026.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class LiteralOptionsTests: XCTestCase {
    func testEverySpellingReachesItsInstance() throws {
        #if canImport(Macros)
        for (options, instance) in Self.spellings {
            assertMacroExpansion(Self.source(options), expandedSource: Self.expanded(options, instance), macros: macros)
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}

// MARK: - private
private extension LiteralOptionsTests {
    static let spellings: KeyValuePairs<String, String> = [
        ".default": "local",
        "Registrar.Options.default": "local",
        "Resolve.Registrar.Options.default": "local",
        ".once": "global",
        "Registrar.Options.once": "global",
        "Resolve.Registrar.Options.once": "global",
        ".singleton": "global",
        "Registrar.Options.singleton": "global",
        "Resolve.Registrar.Options.singleton": "global"
    ]

    static func source(_ options: String) -> String {
        """
        @Resolvable
        struct Container {
            @Register(options: \(options))
            func reporter() -> Reporter {
                Reporter()
            }
        }
        """
    }

    static func expanded(_ options: String, _ instance: String) -> String {
        """
        struct Container {
            func reporter() -> Reporter {
                Reporter()
            }

            struct Resolved: Sendable {
                let reporter: Reporter
            }

            struct Resolver: Sendable {
                private let _registrar = Resolve.Registrar.Storage {
                    Registrations()
                }
                private let _resolvable: Container

                var reporter: Reporter {
                    get async {
                        await _registrar.\(instance).reporter.value(self)
                    }
                }

                init(_ resolvable: Container) {
                    self._resolvable = resolvable
                }

                func resolve() async -> Resolved {
                    _registrar.\(instance).reporter.start(self)

                    return await .init(
                        reporter: _registrar.\(instance).reporter.value(self)
                    )
                }

                private final class Registrations: Sendable {
                    let reporter = Resolve.Registration(options: \(options)) { (resolver: Resolver) in
                        resolver._resolvable.reporter()
                    }
                }
            }
        }
        """
    }
}
