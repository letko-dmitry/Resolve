//
//  RunTimeOptions.swift
//
//
//  Created by Dzmitry Letko on 30/10/2026.
//

import Resolve
import Testing

final class RunTimeOptionsTests {
    @Test func `options known only at run time keep their cache scope`() async throws {
        let first = try await Graph.Resolver(.init()).resolve()
        let second = try await Graph.Resolver(.init()).resolve()

        #expect(first.shared === second.shared)
        #expect(first.global === second.global)
        #expect(first.sharedThrowing === second.sharedThrowing)
        #expect(first.own !== second.own)
        #expect(first.local !== second.local)
        #expect(first.ownThrowing !== second.ownThrowing)
    }
}

// MARK: - private
private extension RunTimeOptionsTests {
    final class Node: Sendable { }

    // Named constants, not the presets the macro recognizes: it leaves their scope to the storage, which reads `once`
    // at run time.
    @Resolvable
    struct Graph {
        static let processWide = Registrar.Options(once: true)
        static let perResolver = Registrar.Options(once: false)

        @Register(options: Graph.processWide)
        func shared() -> Node {
            Node()
        }

        @Register(options: Graph.perResolver)
        func own() -> Node {
            Node()
        }

        // Named like the storage's own instances, which a plain member access would reach instead of these registrations.
        @Register(options: Graph.processWide)
        func global() -> Node {
            Node()
        }

        @Register(options: Graph.perResolver)
        func local() -> Node {
            Node()
        }

        @Register(options: Graph.processWide)
        // swiftlint:disable:next unneeded_throws_rethrows - a throwing registration is the shape under test
        func sharedThrowing() throws -> Node {
            Node()
        }

        @Register(options: Graph.perResolver)
        // swiftlint:disable:next unneeded_throws_rethrows - a throwing registration is the shape under test
        func ownThrowing() throws -> Node {
            Node()
        }
    }
}
