//
//  Container.swift
//  
//
//  Created by Dzmitry Letko on 14/10/2023.
//

import os.lock

@usableFromInline
struct Container<Key: Sendable & Hashable>: Sendable {
    private let values: OSAllocatedUnfairLock<Dictionary<Key, any Sendable>>

    @usableFromInline
    init(minimumCapacity: Int = 0) {
        values = OSAllocatedUnfairLock(initialState: .init(minimumCapacity: minimumCapacity))
    }
    
    @usableFromInline
    func findOrCreate<V: Sendable>(key: Key, value: @Sendable () -> V) -> V {
        values.withLock { values in
            if let value = values[key] as? V {
                return value
            }
            
            let value = value()

            values[key] = value
            
            return value
        }
    }
}
