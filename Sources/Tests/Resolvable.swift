//
//  Resolvable.swift
//
//
//  Created by Dzmitry Letko on 04/10/2023.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(Macros)
import Macros

let macros: [String: Macro.Type] = [
    "Resolvable": Resolvable.self,
    "Register": Register.self
]
#endif

final class ResolvableTests: XCTestCase {
    func testMacro() throws {
        #if canImport(Macros)
        assertMacroExpansion(
            """
            @Resolvable
            struct Container {
                @Register()
                func database() async throws -> Database {
                    return Database()
                }
            }
            """,
            expandedSource: """
            struct Container {
                func database() async throws -> Database {
                    return Database()
                }
            
                struct Resolved: Sendable {
                    let database: Database
                }

                struct Resolver: Sendable {
                    private let _container = Resolve.Container()
                    private let _resolvable: Container

                    var database: Database {
                        get async throws {
                            try await _container.register(for: "database") {
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
            """,
            macros: macros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
