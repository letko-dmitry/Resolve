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

    func testThrowingPerformAndOptions() throws {
        #if canImport(Macros)
        assertMacroExpansion(Self.optionsSource, expandedSource: Self.optionsExpanded, macros: macros)
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
                    private let _registrar = Resolve.Registrar.Storage(Registrations())
                    private let _resolvable: Container

                    var database: Database {
                        get async throws {
                            try await _registrar.database.value(self)
                        }
                    }

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    func resolve() async throws -> Resolved {
                        _registrar.database.start(self)

                        return try await .init(
                            database: _registrar.database.value(self)
                        )
                    }

                    private struct Registrations: Sendable {
                        let database = Resolve.RegistrationThrowable { (resolver: Resolver) in
                            try await resolver._resolvable.database()
                        }
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
                    private let _registrar = Resolve.Registrar.Storage(Registrations())
                    private let _resolvable: Container

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    func warmUp() async {
                        await _registrar.warmUp.value(self)
                    }

                    @discardableResult
                    func resolve() async -> Resolved {
                        _registrar.warmUp.start(self)

                        await _registrar.warmUp.value(self)

                        return .init()
                    }

                    private struct Registrations: Sendable {
                        let warmUp = Resolve.Registration { (resolver: Resolver) in
                            await resolver._resolvable.warmUp()
                        }
                    }
                }
            }
            """
}

// MARK: - private
private extension ResolvableTests {
    static let optionsSource = """
        @Resolvable
        struct Container {
            @Register(options: .once)
            func reporter() -> Reporter {
                Reporter()
            }

            @Perform
            func warmUp(_ resolver: Resolver) async throws {
            }
        }
        """

    static let optionsExpanded = """
            struct Container {
                func reporter() -> Reporter {
                    Reporter()
                }
                func warmUp(_ resolver: Resolver) async throws {
                }

                struct Resolved: Sendable {
                    let reporter: Reporter
                }

                struct Resolver: Sendable {
                    private let _registrar = Resolve.Registrar.Storage(Registrations())
                    private let _resolvable: Container

                    var reporter: Reporter {
                        get async {
                            await _registrar.reporter.value(self)
                        }
                    }

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    func warmUp() async throws {
                        try await _registrar.warmUp.value(self)
                    }

                    func resolve() async throws -> Resolved {
                        _registrar.reporter.start(self)
                        _registrar.warmUp.start(self)

                        try await _registrar.warmUp.value(self)

                        return await .init(
                            reporter: _registrar.reporter.value(self)
                        )
                    }

                    private struct Registrations: Sendable {
                        let reporter = Resolve.Registration(options: .once) { (resolver: Resolver) in
                            resolver._resolvable.reporter()
                        }

                        let warmUp = Resolve.RegistrationThrowable { (resolver: Resolver) in
                            try await resolver._resolvable.warmUp(resolver)
                        }
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
                    private let _registrar = Resolve.Registrar.Storage(Registrations())
                    private let _resolvable: Container

                    var database: Database {
                        get async {
                            await _registrar.database.value(self)
                        }
                    }

                    init(_ resolvable: Container) {
                        self._resolvable = resolvable
                    }

                    func resolve() async -> Resolved {
                        _registrar.database.start(self)

                        return await .init(
                            database: _registrar.database.value(self)
                        )
                    }

                    private struct Registrations: Sendable {
                        let database = Resolve.Registration { (resolver: Resolver) in
                            resolver._resolvable.database(resolver)
                        }
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
