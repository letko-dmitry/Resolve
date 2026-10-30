//
//  Runtime.swift
//
//
//  Created by Dzmitry Letko on 28/10/2026.
//

import Darwin
import Resolve
import XCTest

final class RuntimeTests: XCTestCase {
    func testOnceIsSharedAcrossResolvers() async {
        let first = await Graph.Resolver(.init()).resolve()
        let second = await Graph.Resolver(.init()).resolve()

        XCTAssertTrue(first.shared === second.shared)
        XCTAssertFalse(first.local === second.local)
    }

    func testResolverHandsOutWhatItResolved() async {
        let resolver = Graph.Resolver(.init())
        let resolved = await resolver.resolve()
        let local = await resolver.local

        XCTAssertTrue(resolved.local === local)
    }

    // A task that runs in place – inside the lock its creator holds – must not take that lock again.
    func testTasksThatRunInPlace() async throws {
        guard #available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *) else {
            throw XCTSkip("Task executors need macOS 15")
        }
        guard let symbol = unsafe dlsym(dlopen(nil, 0), "swift_task_enqueueGlobal_hook") else {
            throw XCTSkip("The runtime has no global enqueue hook")
        }

        let hook = unsafe symbol.assumingMemoryBound(to: Hook?.self)

        unsafe hook.pointee = { job, _ in
            unsafe job.runSynchronously(on: InlineExecutor.shared.asUnownedTaskExecutor())
        }

        defer {
            unsafe hook.pointee = nil
        }

        let lazy = LazyAsync { 1 }
        let lazyThrowable = LazyAsyncThrowable { 2 }
        let resolver = Graph.Resolver(.init())
        let resolved = await resolver.resolve()

        let value = await lazy.value
        let valueThrowable = try await lazyThrowable.value
        let local = await resolver.local

        XCTAssertEqual(value, 1)
        XCTAssertEqual(lazy.valueIfResolved, 1)
        XCTAssertEqual(valueThrowable, 2)
        XCTAssertTrue(resolved.local === local)
    }

    func testFailedPerformIsRethrown() async {
        do {
            _ = try await Failing.Resolver(.init()).resolve()

            XCTFail("resolve() must rethrow the failure")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

// MARK: - private
private extension RuntimeTests {
    typealias Hook = @convention(thin) (UnownedJob, @convention(thin) (UnownedJob) -> Void) -> Void

    // Runs every job right away, inside `enqueue`: installed as the global enqueue hook, it makes `Task {}` run its
    // body in place.
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    final class InlineExecutor: TaskExecutor {
        static let shared = InlineExecutor()

        func enqueue(_ job: consuming ExecutorJob) {
            unsafe job.runSynchronously(on: asUnownedTaskExecutor())
        }
    }

    final class Node: Sendable { }

    @Resolvable
    struct Graph {
        @Register(options: .once)
        func shared() -> Node {
            Node()
        }

        @Register
        func local(_ resolver: Resolver) async -> Node {
            _ = await resolver.shared

            return Node()
        }
    }

    @Resolvable
    struct Failing {
        @Register
        func value() -> Int {
            0
        }

        @Perform
        // swiftlint:disable:next async_without_await - an async performable is the shape under test
        func fail() async throws {
            throw CancellationError()
        }
    }
}
