//
//  Registrar.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import Foundation

public final class Registrar: Sendable {
    public struct Options {
        public let singleton: Bool
        
        public init(singleton: Bool = false) {
            self.singleton = singleton
        }
        
        public static let `default` = Options()
        public static let singleton = Options(singleton: true)
    }
    
    private let local = Container()
    private let typeIdentifier: ObjectIdentifier
    
    public init<T>(for type: T.Type) {
        self.typeIdentifier = ObjectIdentifier(type)
    }
    
    @discardableResult
    public func register<V: Sendable>(for name: String, options: Options = .default, _ dependency: @escaping @Sendable () async throws -> V) async throws -> V {
        try await container(options: options).findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
    
    @discardableResult
    public func register<V: Sendable>(for name: String, options: Options = .default, _ dependency: @escaping @Sendable () async -> V) async -> V {
        await container(options: options).findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
}

// MARK: - private
private extension Registrar {
    func container(options: Options) -> Container {
        options.singleton ? Container.global(for: typeIdentifier) : local
    }
}
