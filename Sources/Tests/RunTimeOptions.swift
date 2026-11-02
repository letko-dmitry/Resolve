//
//  RunTimeOptions.swift
//
//
//  Created by Dzmitry Letko on 30/10/2026.
//

import os
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

    @Test func `an options expression can create a resolver`() {
        _ = Reentrant.Resolver(.init())
    }

    @Test func `first resolvers that race share the process-wide registrations`() async throws {
        let outer = Racing.Resolver(.init())
        let nested = try #require(Racing.nested.withLock { $0 })

        let first = await outer.node
        let second = await nested.node

        #expect(first === second)
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

    // Resolved nowhere else, so the test's `Resolver` is its first: the one that makes the process-wide registrations,
    // which evaluates `options:` once more.
    @Resolvable
    struct Reentrant {
        static var options: Registrar.Options {
            _ = Graph.Resolver(.init())

            return .once
        }

        @Register(options: Reentrant.options)
        func node() -> Node {
            Node()
        }
    }

    // Resolved nowhere else. Its first `Resolver` evaluates `options` for its own registrations, then once more for the
    // process-wide ones after finding none; that second time another `Resolver` gets in first and stores its own.
    @Resolvable
    struct Racing {
        static let evaluations = OSAllocatedUnfairLock(initialState: 0)
        static let nested = OSAllocatedUnfairLock<Racing.Resolver?>(initialState: nil)

        static var options: Registrar.Options {
            let evaluation = evaluations.withLock { evaluations in
                evaluations += 1

                return evaluations
            }

            if evaluation == 2 {
                let resolver = Racing.Resolver(.init())

                nested.withLock { nested in
                    nested = resolver
                }
            }

            return .once
        }

        @Register(options: Racing.options)
        func node() -> Node {
            Node()
        }
    }
}
