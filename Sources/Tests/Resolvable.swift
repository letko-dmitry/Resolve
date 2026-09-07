//
//  Resolvable.swift
//
//
//  Created by Dzmitry Letko on 04/10/2023.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(Macros)
import Macros

let macros: [String: any Macro.Type] = [
    "Resolvable": Resolvable.self,
    "Register": Register.self,
    "Perform": Perform.self
]
#endif

final class ResolvableTests: XCTestCase {
    func testMacro() throws {
        #if canImport(Macros)
        assertMacroExpansion(Self.source, expandedSource: Self.expanded, macros: macros)
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testPerformReturningVoid() throws {
        #if canImport(Macros)
        assertMacroExpansion(Self.voidSource, expandedSource: Self.voidExpanded, macros: macros)
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testQualifiedResolverParameter() throws {
        #if canImport(Macros)
        assertMacroExpansion(Self.qualifiedSource, expandedSource: Self.qualifiedExpanded, macros: macros)
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testForeignResolverParameter() throws {
        #if canImport(Macros)
        assertMacroExpansion(
            Self.foreignSource,
            expandedSource: Self.foreignExpanded,
            diagnostics: [
                DiagnosticSpec(message: "The only parameter allowed here is of type `Resolver`", line: 4, column: 19)
            ],
            macros: macros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}

// MARK: - private
private extension ResolvableTests {
    static let source = """
        @Resolvable
        struct Container {
            @Register()
            func database() async throws -> Database {
                return Database()
            }
        }
        """

    static let expanded = """
            struct Container {
                func database() async throws -> Database {
                    return Database()
                }

                struct Resolved: Sendable {
                    let database: Database
                }

                struct Resolver: Sendable {
                    private let _registrar = Resolve.Registrar(for: Container.self, minimumCapacity: 1)
                    private let _resolvable: Container

                    var database: Database {
                        get async throws {
                            try await _registrar.register(for: "database") {
                                try await _resolvable.database()
                            }
                        }
                    }

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    func resolve() async throws -> Resolved {
                        async let database = database

                        return try await .init(
                            database: database
                        )
                    }
                }
            }
            """
}

// MARK: - private
private extension ResolvableTests {
    static let voidSource = """
        @Resolvable
        struct Container {
            @Perform
            func warmUp() async -> Void {
            }
        }
        """

    static let voidExpanded = """
            struct Container {
                func warmUp() async -> Void {
                }

                struct Resolved: Sendable {
                }

                struct Resolver: Sendable {
                    private let _registrar = Resolve.Registrar(for: Container.self, minimumCapacity: 1)
                    private let _resolvable: Container

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    func warmUp() async {
                        await _registrar.register(for: "warmUp") {
                            await _resolvable.warmUp()
                        }
                    }

                    @discardableResult
                    func resolve() async -> Resolved {
                        await withDiscardingTaskGroup { group in
                            group.addTask {
                                await warmUp()
                            }
                        }

                        return .init()
                    }
                }
            }
            """
}

// MARK: - private
private extension ResolvableTests {
    static let qualifiedSource = """
        @Resolvable
        struct Container {
            @Register()
            func database(_ resolver: Container.Resolver) -> Database {
                return Database()
            }
        }
        """

    static let qualifiedExpanded = """
            struct Container {
                func database(_ resolver: Container.Resolver) -> Database {
                    return Database()
                }

                struct Resolved: Sendable {
                    let database: Database
                }

                struct Resolver: Sendable {
                    private let _registrar = Resolve.Registrar(for: Container.self, minimumCapacity: 1)
                    private let _resolvable: Container

                    var database: Database {
                        get async {
                            await _registrar.register(for: "database") {
                                _resolvable.database(self)
                            }
                        }
                    }

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    func resolve() async -> Resolved {
                        async let database = database

                        return await .init(
                            database: database
                        )
                    }
                }
            }
            """
}

// MARK: - private
private extension ResolvableTests {
    static let foreignSource = """
        @Resolvable
        struct Container {
            @Register()
            func database(_ resolver: Foo.Resolver) -> Database {
                return Database()
            }
        }
        """

    static let foreignExpanded = """
            struct Container {
                func database(_ resolver: Foo.Resolver) -> Database {
                    return Database()
                }

                struct Resolved: Sendable {
                }

                struct Resolver: Sendable {
                    private let _resolvable: Container

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    @discardableResult
                    func resolve() -> Resolved {
                        return .init()
                    }
                }
            }
            """
}
