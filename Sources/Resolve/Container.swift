//
//  Container.swift
//  
//
//  Created by Dzmitry Letko on 14/10/2023.
//

import Foundation

final class Container: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    
    func findOrCreate<V>(name: String, value: () -> V) -> V {
        lock.withLock {
            if let value = values[name] as? V {
                return value
            }
            
            let value = value()
            
            values[name] = value
            
            return value
        }
    }
}

extension Container {
    static func global(for identifier: some Hashable) -> Container {
        Global.shared.container(for: identifier)
    }
}

// MARK: - private
private extension Container {
    final class Global {
        private let lock = NSLock()
        private var containers: [AnyHashable: Container] = [:]
        
        private init() { }
        
        static let shared = Global()
        
        func container(for identifier: AnyHashable) -> Container {
            lock.withLock {
                if let container = containers[identifier] { return container }
                
                let container = Container()
                
                containers[identifier] = container
                
                return container
            }
        }
    }
}
