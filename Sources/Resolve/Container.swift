//
//  Container.swift
//  
//
//  Created by Dzmitry Letko on 14/10/2023.
//

import os.lock

@usableFromInline
struct Container: Sendable {
    private let values: OSAllocatedUnfairLock<Dictionary<String, any Sendable>>

    @usableFromInline
    init(minimumCapacity: Int = 0) {
        values = OSAllocatedUnfairLock(initialState: .init(minimumCapacity: minimumCapacity))
    }
    
    @usableFromInline
    func findOrCreate<V: Sendable>(name: String, value: @Sendable () -> V) -> V {
        values.withAdaptiveSpinIfPossible { values in
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
    struct Global {
        private let containers = OSAllocatedUnfairLock(uncheckedState: Dictionary<AnyHashable, Container>())
        
        private init() { }
        
        static let shared = Global()
        
        func container(for identifier: AnyHashable) -> Container {
            containers.withAdaptiveSpinUncheckedIfPossible { containers in
                if let container = containers[identifier] { return container }
                
                let container = Container()
                
                containers[identifier] = container
                
                return container
            }
        }
    }
}
