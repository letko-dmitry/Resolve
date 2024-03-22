//
//  Registrar.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import Foundation

public struct Registrar: Sendable {
    public struct Options: Sendable {
        public let once: Bool
        
        @inlinable
        public init(once: Bool = false) {
            self.once = once
        }
        
        public static let `default` = Options()
        public static let once = Options(once: true)
        
        @available(*, deprecated, renamed: "once")
        public static var singleton: Options { .once }
    }
    
    @usableFromInline let local: Container
    @usableFromInline let typeIdentifier: ObjectIdentifier
    
    @inlinable
    public init<T>(for type: T.Type, minimumCapacity: Int = 0) {
        self.local = Container(minimumCapacity: minimumCapacity)
        self.typeIdentifier = ObjectIdentifier(type)
    }
    
    @discardableResult
    @inlinable
    public func register<V: Sendable>(for name: String, options: Options = .default, _ dependency: @escaping @Sendable () async throws -> V) async throws -> V {
        try await container(options: options).findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
    
    @discardableResult
    @inlinable
    public func register<V: Sendable>(for name: String, options: Options = .default, _ dependency: @escaping @Sendable () async -> V) async -> V {
        await container(options: options).findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
}

extension Registrar {
    @usableFromInline
    func container(options: Options) -> Container {
        options.once ? Container.global(for: typeIdentifier) : local
    }
}
